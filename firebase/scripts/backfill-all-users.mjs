#!/usr/bin/env node
/**
 * Respaldiza la colección raíz `all_user/{email}` desde los usuarios reales
 * de `tenants/{tenantId}/users/{uid}`.
 *
 * Es idempotente: fusiona memberships por (tenantId, uid) y no borra nada.
 * Las credenciales se leen de web/.env.local (FIREBASE_SERVICE_ACCOUNT_JSON).
 *
 *   node firebase/scripts/backfill-all-users.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const require = createRequire(path.join(root, "web", "package.json"));
const { GoogleAuth } = require("google-auth-library");

function loadEnv() {
  const file = path.join(root, "web", ".env.local");
  if (!fs.existsSync(file)) return;
  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    const index = line.indexOf("=");
    if (index <= 0 || line.trim().startsWith("#")) continue;
    const key = line.slice(0, index).trim();
    if (!(key in process.env)) process.env[key] = line.slice(index + 1).trim();
  }
}

loadEnv();
delete process.env.FIRESTORE_EMULATOR_HOST;

const serviceAccountRaw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
if (!serviceAccountRaw) {
  console.error("Falta FIREBASE_SERVICE_ACCOUNT_JSON en web/.env.local");
  process.exit(1);
}
let serviceAccount;
try {
  serviceAccount = JSON.parse(serviceAccountRaw);
} catch {
  console.error("FIREBASE_SERVICE_ACCOUNT_JSON no es JSON válido.");
  process.exit(1);
}

const projectId = serviceAccount.project_id ?? process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID ?? "restaurante-mania-e47a0";
const auth = new GoogleAuth({
  credentials: {
    client_email: serviceAccount.client_email,
    private_key: serviceAccount.private_key,
  },
  scopes: ["https://www.googleapis.com/auth/datastore", "https://www.googleapis.com/auth/cloud-platform"],
});
const tokenResponse = await auth.getAccessToken();
const accessToken = typeof tokenResponse === "string" ? tokenResponse : tokenResponse.token;
const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
const headers = { Authorization: `Bearer ${accessToken}` };

function encodeValue(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") {
    return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  }
  if (Array.isArray(value)) return { arrayValue: { values: value.map(encodeValue) } };
  if (typeof value === "object") {
    return { mapValue: { fields: Object.fromEntries(Object.entries(value).map(([k, v]) => [k, encodeValue(v)])) } };
  }
  return { stringValue: String(value) };
}

function decodeValue(value) {
  if (!value) return undefined;
  if ("stringValue" in value) return value.stringValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return value.doubleValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("nullValue" in value) return null;
  if ("timestampValue" in value) return value.timestampValue;
  if ("arrayValue" in value) return (value.arrayValue.values ?? []).map(decodeValue);
  if ("mapValue" in value) return decodeFields(value.mapValue.fields ?? {});
  return undefined;
}

function decodeFields(fields) {
  return Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, decodeValue(v)]));
}

async function list(pathName) {
  const res = await fetch(`${base}/${pathName}`, { headers });
  const text = await res.text();
  if (!res.ok) throw new Error(`GET ${pathName} -> ${res.status}: ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : {};
}

async function patch(pathName, fields) {
  const res = await fetch(`${base}/${pathName}`, {
    method: "PATCH",
    headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify({ fields: Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, encodeValue(v)])) }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`PATCH ${pathName} -> ${res.status}: ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : {};
}

const tenants = ((await list("tenants")).documents ?? [])
  .map((doc) => doc.name.split("/").pop())
  .filter(Boolean);

const byEmail = new Map();
let total = 0;
for (const tenantId of tenants) {
  const docs = (await list(`tenants/${tenantId}/users`)).documents ?? [];
  for (const doc of docs) {
    const fields = decodeFields(doc.fields ?? {});
    const email = String(fields.email ?? "").trim().toLowerCase();
    if (!email || !email.includes("@")) continue;
    const uid = doc.name.split("/").pop();
    const role = String(fields.role ?? "");
    if (!["admin", "cashier", "waiter", "cook"].includes(role)) continue;
    const name = String(fields.name ?? email);
    if (!byEmail.has(email)) byEmail.set(email, { email, name, memberships: new Map() });
    const entry = byEmail.get(email);
    entry.memberships.set(`${tenantId}:${uid}`, { tenantId, role, uid, name, email });
    total += 1;
  }
  console.log(`${tenantId}: ${docs.length} usuarios`);
}

let written = 0;
for (const [email, entry] of byEmail) {
  const memberships = [...entry.memberships.values()];
  // El id del documento es el email sin codificar (mismo criterio que la web).
  // Conservar los dispositivos ya registrados (notificaciones push).
  const previous = (await list(`all_user/${email}`)).fields ?? {};
  const decoded = decodeFields(previous);
  const deviceIds = Array.isArray(decoded.deviceIds)
    ? decoded.deviceIds.filter((id) => typeof id === "string" && id)
    : [];
  const lastDevice = typeof decoded.deviceId === "string" && decoded.deviceId
    ? decoded.deviceId
    : "";
  for (const id of [lastDevice, ...deviceIds]) {
    if (id && !deviceIds.includes(id)) deviceIds.push(id);
  }
  await patch(`all_user/${email}`, {
    email,
    name: entry.name,
    memberships,
    ...(lastDevice ? { deviceId: lastDevice } : {}),
    ...(deviceIds.length ? { deviceIds } : {}),
    updatedAt: new Date().toISOString(),
  });
  written += 1;
  console.log(`all_user/${email} -> ${memberships.map((m) => `${m.tenantId}(${m.role})`).join(", ")}`);
}

console.log(`\nOK: ${written} documentos all_user escritos desde ${total} usuarios en ${tenants.length} tenants.`);
