import { webcrypto } from "node:crypto";

type FsValue =
  | { stringValue: string }
  | { integerValue: string }
  | { doubleValue: number }
  | { booleanValue: boolean }
  | { nullValue: null }
  | { timestampValue: string }
  | { arrayValue: { values?: FsValue[] } }
  | { mapValue: { fields?: Record<string, FsValue> } };

interface FirestoreDocument {
  name: string;
  fields?: Record<string, FsValue>;
}

export interface FirestoreDoc<T = Record<string, unknown>> {
  id: string;
  data: T;
}

interface ServiceAccount {
  client_email: string;
  private_key: string;
}

type TokenCache = { token: string; expiresAt: number };

const FIRESTORE_SCOPE =
  "https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/cloud-platform";

let tokenCache: TokenCache | null = null;
let tokenInFlight: Promise<string> | null = null;

function encodeValue(value: unknown): FsValue {
  if (value === null || value === undefined) return { nullValue: null };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
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
    return { mapValue: { fields: encodeFields(value as Record<string, unknown>) } };
  }
  return { nullValue: null };
}

function encodeFields(data: Record<string, unknown>): Record<string, FsValue> {
  return Object.fromEntries(
    Object.entries(data).map(([key, value]) => [key, encodeValue(value)]),
  );
}

function decodeValue(value: FsValue): unknown {
  if ("stringValue" in value) return value.stringValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return value.doubleValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("nullValue" in value) return null;
  if ("timestampValue" in value) return value.timestampValue;
  if ("arrayValue" in value) {
    return (value.arrayValue.values ?? []).map(decodeValue);
  }
  if ("mapValue" in value) return decodeFields(value.mapValue.fields ?? {});
  return null;
}

function decodeFields(
  fields: Record<string, FsValue>,
): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(fields).map(([key, value]) => [key, decodeValue(value)]),
  );
}

function readConfig(): { apiKey: string; projectId: string } | null {
  const apiKey = process.env.NEXT_PUBLIC_FIREBASE_API_KEY?.trim();
  const projectId = process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID?.trim();
  if (!apiKey || !projectId) return null;
  if (
    apiKey.startsWith("tu_") ||
    apiKey.startsWith("YOUR_") ||
    projectId.startsWith("tu-") ||
    projectId.startsWith("your-")
  ) {
    return null;
  }
  return { apiKey, projectId };
}

export function isFirestoreConfigured(): boolean {
  return readConfig() !== null;
}

function isDynamicUsageError(error: unknown): boolean {
  return (
    error instanceof Error &&
    (error as Error & { digest?: unknown }).digest === "DYNAMIC_SERVER_USAGE"
  );
}

function readServiceAccount(): ServiceAccount | null {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as Partial<ServiceAccount>;
    if (!parsed.client_email || !parsed.private_key) return null;
    return { client_email: parsed.client_email, private_key: parsed.private_key };
  } catch {
    return null;
  }
}

function base64url(value: string | Uint8Array): string {
  return Buffer.from(value).toString("base64url");
}

function pemToDer(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s/g, "");
  return new Uint8Array(Buffer.from(body, "base64"));
}

async function googleAccessToken(account: ServiceAccount): Promise<string> {
  if (tokenCache && tokenCache.expiresAt > Date.now() + 60_000) {
    return tokenCache.token;
  }
  if (tokenInFlight) return tokenInFlight;

  tokenInFlight = (async () => {
    const issuedAt = Math.floor(Date.now() / 1000);
    const header = { alg: "RS256", typ: "JWT" };
    const claims = {
      iss: account.client_email,
      scope: FIRESTORE_SCOPE,
      aud: "https://oauth2.googleapis.com/token",
      iat: issuedAt,
      exp: issuedAt + 3600,
    };
    const unsigned = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claims))}`;
    const key = await webcrypto.subtle.importKey(
      "pkcs8",
      pemToDer(account.private_key),
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const signature = await webcrypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      Buffer.from(unsigned),
    );
    const assertion = `${unsigned}.${base64url(new Uint8Array(signature))}`;
    const response = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion,
      }),
      cache: "no-store",
    });
    if (!response.ok) {
      throw new Error(`Google OAuth respondió ${response.status}`);
    }
    const payload = (await response.json()) as {
      access_token?: string;
      expires_in?: number;
    };
    if (!payload.access_token) throw new Error("Google OAuth sin access_token");
    tokenCache = {
      token: payload.access_token,
      expiresAt: Date.now() + (payload.expires_in ?? 3600) * 1000,
    };
    return payload.access_token;
  })();

  try {
    return await tokenInFlight;
  } finally {
    tokenInFlight = null;
  }
}

async function authHeaders(): Promise<Record<string, string>> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  const account = readServiceAccount();
  if (!account) return headers;
  try {
    const token = await googleAccessToken(account);
    headers.Authorization = `Bearer ${token}`;
  } catch (error) {
    if (!isDynamicUsageError(error)) {
      console.warn("[firebase/rest] No se pudo obtener token de servicio:", error);
    }
  }
  return headers;
}

function baseUrl(config: { apiKey: string; projectId: string }): string {
  return `https://firestore.googleapis.com/v1/projects/${config.projectId}/databases/(default)/documents`;
}

function docId(document: FirestoreDocument): string {
  return document.name.split("/").pop() ?? "";
}

export async function listDocuments<T>(
  collection: string,
  mapper: (doc: FirestoreDoc) => T,
  revalidate = 60,
): Promise<T[]> {
  const config = readConfig();
  if (!config) return [];
  const url = `${baseUrl(config)}/${collection}?key=${config.apiKey}&pageSize=200`;
  const response = await fetch(url, {
    headers: await authHeaders(),
    next: { revalidate },
  });
  if (!response.ok) {
    throw new Error(
      `Firestore ${collection} respondió ${response.status}: ${await response.text()}`,
    );
  }
  const payload = (await response.json()) as { documents?: FirestoreDocument[] };
  return (payload.documents ?? []).map((document) =>
    mapper({
      id: docId(document),
      data: decodeFields(document.fields ?? {}),
    }),
  );
}

export async function getDocument<T>(
  collection: string,
  id: string,
  revalidate = 0,
): Promise<T | null> {
  const config = readConfig();
  if (!config) return null;
  const url = `${baseUrl(config)}/${collection}/${encodeURIComponent(id)}?key=${config.apiKey}`;
  const response = await fetch(url, {
    headers: await authHeaders(),
    next: { revalidate },
  });
  if (response.status === 404) return null;
  if (!response.ok) {
    throw new Error(`Firestore GET ${collection}/${id} respondió ${response.status}`);
  }
  const document = (await response.json()) as FirestoreDocument;
  return decodeFields(document.fields ?? {}) as T;
}

export async function createDocument(
  collection: string,
  data: Record<string, unknown>,
): Promise<string> {
  const config = readConfig();
  if (!config) throw new Error("Firestore no está configurado");
  const url = `${baseUrl(config)}/${collection}?key=${config.apiKey}`;
  const response = await fetch(url, {
    method: "POST",
    headers: await authHeaders(),
    body: JSON.stringify({ fields: encodeFields(data) }),
    cache: "no-store",
  });
  if (!response.ok) {
    throw new Error(
      `Firestore POST ${collection} respondió ${response.status}: ${await response.text()}`,
    );
  }
  const document = (await response.json()) as FirestoreDocument;
  return docId(document);
}

export async function deleteDocument(
  collection: string,
  id: string,
): Promise<void> {
  const config = readConfig();
  if (!config) throw new Error("Firestore no está configurado");
  const url = `${baseUrl(config)}/${collection}/${encodeURIComponent(id)}?key=${config.apiKey}`;
  const response = await fetch(url, {
    method: "DELETE",
    headers: await authHeaders(),
    cache: "no-store",
  });
  if (!response.ok) {
    throw new Error(
      `Firestore DELETE ${collection}/${id} respondió ${response.status}: ${await response.text()}`,
    );
  }
}

export async function setDocument(
  collection: string,
  id: string,
  data: Record<string, unknown>,
): Promise<void> {
  const config = readConfig();
  if (!config) throw new Error("Firestore no está configurado");
  const fields = encodeFields(data);
  const mask = Object.keys(fields)
    .map((f) => `updateMask.fieldPaths=${encodeURIComponent(f)}`)
    .join("&");
  const url = `${baseUrl(config)}/${collection}/${encodeURIComponent(id)}?key=${config.apiKey}&${mask}`;
  const response = await fetch(url, {
    method: "PATCH",
    headers: await authHeaders(),
    body: JSON.stringify({ fields }),
    cache: "no-store",
  });
  if (!response.ok) {
    throw new Error(
      `Firestore PATCH ${collection}/${id} respondió ${response.status}: ${await response.text()}`,
    );
  }
}
