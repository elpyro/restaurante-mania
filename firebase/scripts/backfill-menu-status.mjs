/**
 * Recalcula y persiste `menuItems.status` desde el stock real de Firestore.
 *
 * Uso:
 *   node firebase/scripts/backfill-menu-status.mjs
 *   node firebase/scripts/backfill-menu-status.mjs --set cafe=0
 *   node firebase/scripts/backfill-menu-status.mjs --dry-run
 *
 * `--set id=stock` permite corregir un insumo antes de recalcular. Es
 * idempotente y respeta los bloqueos manuales (`manualStatus: "unavailable"`).
 * Requiere firebase/service-account.json con rol `datastore.user`.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { webcrypto } from "node:crypto";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..", "..");
const PROJECT_ID = "restaurante-mania-e47a0";
const BASE_URL = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const serviceAccount = JSON.parse(
  fs.readFileSync(path.join(root, "firebase", "service-account.json"), "utf8"),
);

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const rawAdjustments = [];
for (let index = 0; index < args.length; index++) {
  const arg = args[index];
  if (arg === "--set") {
    rawAdjustments.push(args[++index] ?? "");
  } else if (arg.startsWith("--set=")) {
    rawAdjustments.push(arg.slice("--set=".length));
  }
}
const adjustments = rawAdjustments
  .filter(Boolean)
  .map((entry) => {
    const separator = entry.indexOf("=");
    return {
      id: entry.slice(0, separator).trim(),
      stock: Number(entry.slice(separator + 1)),
    };
  });

let authToken = "";

function base64url(value) {
  return Buffer.from(value).toString("base64url");
}

function pemToDer(pem) {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s/g, "");
  return new Uint8Array(Buffer.from(body, "base64"));
}

async function getAccessToken() {
  if (authToken) return authToken;
  const now = Math.floor(Date.now() / 1000);
  const unsigned = [
    base64url(JSON.stringify({ alg: "RS256", typ: "JWT" })),
    base64url(
      JSON.stringify({
        iss: serviceAccount.client_email,
        scope:
          "https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/cloud-platform",
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 3600,
      }),
    ),
  ].join(".");
  const key = await webcrypto.subtle.importKey(
    "pkcs8",
    pemToDer(serviceAccount.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await webcrypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    Buffer.from(unsigned),
  );
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${base64url(new Uint8Array(signature))}`,
    }),
  });
  if (!response.ok) {
    throw new Error(`OAuth respondió ${response.status}: ${await response.text()}`);
  }
  authToken = (await response.json()).access_token;
  return authToken;
}

function encodeValue(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(encodeValue) } };
  }
  if (typeof value === "object") {
    return { mapValue: { fields: encodeFields(value) } };
  }
  return { nullValue: null };
}

function encodeFields(data) {
  return Object.fromEntries(
    Object.entries(data).map(([key, value]) => [key, encodeValue(value)]),
  );
}

function decodeValue(value) {
  if ("stringValue" in value) return value.stringValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return value.doubleValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("nullValue" in value) return null;
  if ("arrayValue" in value) {
    return (value.arrayValue.values ?? []).map(decodeValue);
  }
  if ("mapValue" in value) return decodeFields(value.mapValue.fields ?? {});
  return null;
}

function decodeFields(fields) {
  return Object.fromEntries(
    Object.entries(fields ?? {}).map(([key, value]) => [key, decodeValue(value)]),
  );
}

async function listCollection(collection) {
  const token = await getAccessToken();
  const response = await fetch(
    `${BASE_URL}/${collection}?pageSize=300&key=${process.env.NEXT_PUBLIC_FIREBASE_API_KEY ?? ""}`,
    {
      headers: { Authorization: `Bearer ${token}` },
      cache: "no-store",
    },
  );
  if (!response.ok) {
    throw new Error(
      `Firestore GET ${collection} respondió ${response.status}: ${await response.text()}`,
    );
  }
  const payload = await response.json();
  return (payload.documents ?? []).map((doc) => ({
    id: doc.name.split("/").pop(),
    data: decodeFields(doc.fields),
  }));
}

async function patchDoc(collection, id, data) {
  if (dryRun) return;
  const token = await getAccessToken();
  const fields = encodeFields(data);
  const mask = Object.keys(fields)
    .map((field) => `updateMask.fieldPaths=${encodeURIComponent(field)}`)
    .join("&");
  const response = await fetch(
    `${BASE_URL}/${collection}/${encodeURIComponent(id)}?${mask}`,
    {
      method: "PATCH",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ fields }),
      cache: "no-store",
    },
  );
  if (!response.ok) {
    throw new Error(
      `Firestore PATCH ${collection}/${id} respondió ${response.status}: ${await response.text()}`,
    );
  }
}

function maxServings(recipe, stocks) {
  if (!Array.isArray(recipe) || recipe.length === 0) return null;
  let max = Number.POSITIVE_INFINITY;
  for (const line of recipe) {
    if (!line || typeof line.ingredientId !== "string") continue;
    const quantity = Number(line.quantity ?? 0);
    if (!Number.isFinite(quantity) || quantity <= 0) continue;
    const stock = stocks.get(line.ingredientId);
    if (stock === undefined) continue;
    const canMake = stock <= 0 ? 0 : Math.floor(stock / quantity);
    if (canMake < max) max = canMake;
  }
  return Number.isFinite(max) ? Math.max(0, max) : null;
}

async function main() {
  for (const adjustment of adjustments) {
    if (!adjustment.id || !Number.isFinite(adjustment.stock)) {
      throw new Error(`--set inválido: ${JSON.stringify(adjustment)}`);
    }
    console.log(
      `${dryRun ? "[dry-run] " : ""}ingredients/${adjustment.id}.stock = ${adjustment.stock}`,
    );
    await patchDoc("ingredients", adjustment.id, {
      stock: adjustment.stock,
      updatedAt: new Date().toISOString(),
    });
  }

  const ingredients = await listCollection("ingredients");
  const stocks = new Map(
    ingredients.map((doc) => [doc.id, Number(doc.data.stock ?? 0)]),
  );
  const items = await listCollection("menuItems");
  const updatedAt = new Date().toISOString();
  let changed = 0;

  for (const item of items) {
    if (item.data.manualStatus === "unavailable") {
      console.log(`${item.id}: bloqueo manual, sin cambios`);
      continue;
    }
    const servings = maxServings(item.data.recipe, stocks);
    const status = servings === 0 ? "unavailable" : "available";
    if (item.data.status === status) {
      console.log(`${item.id}: ${status} (sin cambios)`);
      continue;
    }
    console.log(`${item.id}: ${item.data.status ?? ""} → ${status}`);
    await patchDoc("menuItems", item.id, {
      status,
      statusReason: "ingredients",
      statusUpdatedAt: updatedAt,
    });
    changed++;
  }

  console.log(
    `${dryRun ? "[dry-run] " : ""}Backfill completado: ${changed} platos actualizados de ${items.length}.`,
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
