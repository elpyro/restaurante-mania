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
  const response = await fetch(url, { next: { revalidate } });
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
  const response = await fetch(url, { next: { revalidate } });
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
    headers: { "Content-Type": "application/json" },
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
