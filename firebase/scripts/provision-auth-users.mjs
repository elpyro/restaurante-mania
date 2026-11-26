#!/usr/bin/env node
/**
 * Crea (si hace falta) un usuario de Firebase Auth y le asigna su rol en
 * Firestore `users/{uid}`. La web verifica el ID token y lee el rol desde
 * Firestore, así que no se necesitan custom claims ni permisos de Auth Admin.
 *
 * Uso (la contraseña NUNCA se guarda en el repositorio):
 *   EMAIL=admin.qa@restaurante.com PASSWORD=... ROLE=admin TENANT=all \
 *     node firebase/scripts/provision-auth-users.mjs
 *
 * TENANT admite `all` (mania,fuego,verde) o una lista separada por comas.
 * Las variables NEXT_PUBLIC_FIREBASE_* y FIREBASE_SERVICE_ACCOUNT_JSON se
 * leen de web/.env.local si no están en process.env.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const require = createRequire(path.join(root, "web", "package.json"));

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
delete process.env.FIREBASE_AUTH_EMULATOR_HOST;

const apiKey = process.env.NEXT_PUBLIC_FIREBASE_API_KEY?.trim();
const projectId = process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID?.trim();
const serviceAccountRaw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
const email = (process.env.EMAIL ?? "admin@restaurante.com").trim();
const password = process.env.PASSWORD ?? "";
const role = (process.env.ROLE ?? "admin").trim();

if (!apiKey || !projectId || !serviceAccountRaw) {
  console.error("Faltan NEXT_PUBLIC_FIREBASE_API_KEY, NEXT_PUBLIC_FIREBASE_PROJECT_ID o FIREBASE_SERVICE_ACCOUNT_JSON.");
  process.exit(1);
}
if (!password) {
  console.error("Define PASSWORD en el entorno. No se permite contraseña por defecto.");
  process.exit(1);
}
if (!["admin", "cashier", "waiter", "cook"].includes(role)) {
  console.error("ROLE debe ser admin, cashier, waiter o cook.");
  process.exit(1);
}

const knownTenants = ["mania", "fuego", "verde"];
const tenantInput = (process.env.TENANT ?? "mania").trim();
const tenantIds =
  tenantInput === "all"
    ? knownTenants
    : tenantInput.split(",").map((value) => value.trim()).filter(Boolean);
if (tenantIds.length === 0) {
  console.error("Define TENANT=all o una lista de tenants separada por comas.");
  process.exit(1);
}
const unknownTenants = tenantIds.filter((id) => !knownTenants.includes(id));
if (unknownTenants.length > 0) {
  console.error(`Tenant desconocido: ${unknownTenants.join(", ")}`);
  process.exit(1);
}

let serviceAccount;
try {
  serviceAccount = JSON.parse(serviceAccountRaw);
} catch {
  console.error("FIREBASE_SERVICE_ACCOUNT_JSON no es JSON válido.");
  process.exit(1);
}

const signUpResponse = await fetch(
  `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${encodeURIComponent(apiKey)}`,
  {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  },
);
const signUp = await signUpResponse.json();
let uid = signUp.localId;

if (!signUpResponse.ok) {
  if (signUp.error?.message !== "EMAIL_EXISTS") {
    console.error(`No se pudo crear el usuario: ${signUp.error?.message ?? signUpResponse.status}`);
    process.exit(1);
  }
  // El usuario ya existe: buscamos su uid con el token de sesión.
  const signInResponse = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${encodeURIComponent(apiKey)}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const signIn = await signInResponse.json();
  if (!signInResponse.ok) {
    console.error(`El usuario ya existe pero las credenciales no coinciden: ${signIn.error?.message ?? signInResponse.status}`);
    process.exit(1);
  }
  uid = signIn.localId;
}

const { cert, initializeApp, getApps } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
if (getApps().length === 0) {
  initializeApp({
    credential: cert({
      projectId: serviceAccount.project_id ?? projectId,
      clientEmail: serviceAccount.client_email,
      privateKey: serviceAccount.private_key,
    }),
  });
}

const userDocument = {
  uid,
  name: email.split("@")[0],
  email,
  role,
  status: "active",
  createdAt: new Date().toISOString(),
};

for (const tenantId of tenantIds) {
  await getFirestore()
    .collection("tenants")
    .doc(tenantId)
    .collection("users")
    .doc(uid)
    .set(userDocument, { merge: true });
}

console.log(
  `OK: ${email} (uid=${uid}, role=${role}) en ${tenantIds.join(", ")} de ${projectId}`,
);
console.log("La web autoriza PATCH /api/restaurant/config con el token de este usuario y su rol en Firestore.");
