/**
 * Verifica que `syncMenuStatusOnIngredientChange` persista el estado derivado
 * del stock escribiendo directamente en Firestore (sin pasar por la API web).
 *
 * Uso: node firebase/scripts/verify-menu-status-trigger.mjs
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

async function patchDoc(collection, id, data) {
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

async function getDoc(collection, id) {
  const token = await getAccessToken();
  const response = await fetch(`${BASE_URL}/${collection}/${encodeURIComponent(id)}`, {
    headers: { Authorization: `Bearer ${token}` },
    cache: "no-store",
  });
  if (!response.ok) {
    throw new Error(
      `Firestore GET ${collection}/${id} respondió ${response.status}: ${await response.text()}`,
    );
  }
  const payload = await response.json();
  return decodeFields(payload.fields ?? {});
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function waitForStatus(expected, timeoutMs = 60000) {
  const deadline = Date.now() + timeoutMs;
  let last;
  while (Date.now() < deadline) {
    last = await getDoc("menuItems", "item-cafe");
    if (last.status === expected) return last;
    await sleep(2000);
  }
  throw new Error(
    `La Function no dejó item-cafe en "${expected}" en ${timeoutMs}ms. Último estado: ${JSON.stringify(last)}`,
  );
}

async function main() {
  if (process.argv.includes("--inspect")) {
    console.log("ingredients/cafe:", JSON.stringify(await getDoc("ingredients", "cafe"), null, 2));
    console.log("menuItems/item-cafe:", JSON.stringify(await getDoc("menuItems", "item-cafe"), null, 2));
    return;
  }

  console.log("1) Dejar item-cafe en available escribiendo directo en Firestore...");
  await patchDoc("menuItems", "item-cafe", {
    status: "available",
    statusReason: "manual",
  });

  console.log("2) ingredients/cafe.stock = 0 (debe disparar el trigger)...");
  await patchDoc("ingredients", "cafe", {
    stock: 0,
    updatedAt: new Date().toISOString(),
  });
  const agotado = await waitForStatus("unavailable");
  console.log("   ✅ Agotado persistido:", {
    status: agotado.status,
    statusReason: agotado.statusReason,
    manualStatus: agotado.manualStatus ?? null,
  });

  console.log("3) Dejar item-cafe en unavailable escribiendo directo en Firestore...");
  await patchDoc("menuItems", "item-cafe", {
    status: "unavailable",
    statusReason: "manual",
  });

  console.log("4) ingredients/cafe.stock = 100 (debe disparar el trigger)...");
  await patchDoc("ingredients", "cafe", {
    stock: 100,
    updatedAt: new Date().toISOString(),
  });
  const disponible = await waitForStatus("available");
  console.log("   ✅ Disponible persistido:", {
    status: disponible.status,
    statusReason: disponible.statusReason,
  });

  console.log("5) Restaurar estado final (stock 0)...");
  await patchDoc("ingredients", "cafe", {
    stock: 0,
    updatedAt: new Date().toISOString(),
  });
  const final = await waitForStatus("unavailable");
  console.log("   ✅ Estado final:", {
    stock: 0,
    status: final.status,
    statusReason: final.statusReason,
    manualStatus: final.manualStatus ?? null,
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
