import { NextResponse } from "next/server";
import {
  isFirestoreConfigured,
  listDocuments,
  setDocument,
} from "@/lib/firebase/rest";
import { normalizeDayKey, visitDocumentId } from "@/lib/visit-identity";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const COLLECTION = "webVisits";
const MAX_VISITS = 2000;
const MAX_RESPONSE = 500;

type VisitPayload = {
  id?: string;
  visitorId?: string;
  occurredAt?: string;
  dayKey?: string;
  registered?: boolean | string;
  customerName?: string;
  customerPhone?: string;
  normalizedPhone?: string;
  referenceLabel?: string;
  referenceUrl?: string;
  referrer?: string;
};

type StoredVisit = {
  id: string;
  visitorId: string;
  occurredAt: string;
  dayKey: string;
  registered: boolean;
  customerName: string;
  customerPhone: string;
  normalizedPhone: string;
  referenceLabel: string;
  referenceUrl: string;
  referrer: string;
};

// Modo demo (sin credenciales de Firebase): mantiene el feed mientras el
// servidor está vivo para poder probar el panel CRM de extremo a extremo.
type DemoStore = { visits: StoredVisit[] };
const globalForVisits = globalThis as typeof globalThis & {
  __restauranteWebVisits?: DemoStore;
};
const demoStore =
  globalForVisits.__restauranteWebVisits ??
  (globalForVisits.__restauranteWebVisits = { visits: [] });

function text(value: unknown, max = 160): string {
  return String(value ?? "").trim().slice(0, max);
}

function absoluteUrl(value: string, request: Request): string {
  const raw = value.trim();
  if (!raw) return new URL(request.url).origin;
  const base = request.headers.get("origin") ?? new URL(request.url).origin;
  try {
    const url = new URL(raw, base);
    return url.protocol === "http:" || url.protocol === "https:"
      ? url.toString().slice(0, 500)
      : "";
  } catch {
    return "";
  }
}

function optionalUrl(value: string, request: Request): string {
  return value.trim() ? absoluteUrl(value, request) : "";
}

function labelFor(url: string, fallback: string): string {
  const provided = text(fallback, 160);
  if (provided) return provided;
  try {
    const parsed = new URL(url);
    const path = parsed.pathname || "/";
    return `${path}${parsed.search}`.slice(0, 160);
  } catch {
    return "/";
  }
}

function mapDoc(doc: { id: string; data: Record<string, unknown> }): StoredVisit {
  const d = doc.data;
  return {
    id: String(d.id ?? doc.id),
    visitorId: text(d.visitorId, 120),
    occurredAt: String(d.occurredAt ?? new Date().toISOString()),
    dayKey: String(d.dayKey ?? ""),
    registered: d.registered === true || d.registered === "true",
    customerName: text(d.customerName),
    customerPhone: text(d.customerPhone, 30),
    normalizedPhone: text(d.normalizedPhone, 30),
    referenceLabel: text(d.referenceLabel, 160),
    referenceUrl: text(d.referenceUrl, 500),
    referrer: text(d.referrer, 500),
  };
}

function identityKey(visit: StoredVisit): string {
  if (visit.visitorId) return visit.visitorId;
  if (visit.registered && visit.normalizedPhone) {
    return `phone:${visit.normalizedPhone}`;
  }
  return `id:${visit.id}`;
}

/**
 * Una sola visita por identidad/día. Para documentos antiguos sin `visitorId`
 * usamos el teléfono normalizado; los anónimos se conservan tal cual.
 */
function sorted(visits: StoredVisit[]): StoredVisit[] {
  const seen = new Set<string>();
  const firstPerDay = [...visits]
    .sort((a, b) => a.occurredAt.localeCompare(b.occurredAt))
    .filter((visit) => {
      const key = `${visit.dayKey}|${identityKey(visit)}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  return firstPerDay
    .sort((a, b) => b.occurredAt.localeCompare(a.occurredAt))
    .slice(0, MAX_RESPONSE);
}

export async function GET() {
  if (!isFirestoreConfigured()) {
    return NextResponse.json(
      { visits: sorted(demoStore.visits), configured: false },
      { headers: { "Cache-Control": "no-store" } },
    );
  }
  try {
    const visits = await listDocuments(COLLECTION, mapDoc, 0);
    return NextResponse.json(
      { visits: sorted(visits), configured: true },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch (error) {
    console.error("[api/visits] GET", error);
    return NextResponse.json(
      { error: "No se pudieron cargar las visitas" },
      { status: 500 },
    );
  }
}

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json(
      { ok: false, error: "JSON inválido" },
      { status: 400 },
    );
  }
  const input = (body ?? {}) as VisitPayload;

  const occurredAtRaw = text(input.occurredAt, 40);
  const parsedDate = occurredAtRaw ? new Date(occurredAtRaw) : new Date();
  const occurredAt = Number.isNaN(parsedDate.getTime())
    ? new Date()
    : parsedDate;

  const referenceUrl = absoluteUrl(text(input.referenceUrl, 500), request);
  const registered =
    input.registered === true ||
    input.registered === "true" ||
    text(input.customerName).length >= 2 ||
    text(input.customerPhone).replace(/\D/g, "").length >= 7;

  const visitorId = text(input.visitorId, 120);
  const dayKey = normalizeDayKey(input.dayKey, occurredAt);
  const visit: StoredVisit = {
    id: visitorId
      ? visitDocumentId(visitorId, dayKey)
      : text(input.id, 80) || `vis_${occurredAt.getTime()}_${Math.random().toString(36).slice(2, 8)}`,
    visitorId,
    occurredAt: occurredAt.toISOString(),
    dayKey,
    registered,
    customerName: registered ? text(input.customerName) : "",
    customerPhone: registered ? text(input.customerPhone, 30) : "",
    normalizedPhone: registered
      ? text(input.normalizedPhone, 30) || text(input.customerPhone, 30).replace(/\D/g, "")
      : "",
    referenceLabel: labelFor(referenceUrl, input.referenceLabel ?? ""),
    referenceUrl,
    referrer: optionalUrl(text(input.referrer, 500), request),
  };

  try {
    if (isFirestoreConfigured()) {
      await setDocument(COLLECTION, visit.id, visit);
    } else {
      const withoutId = demoStore.visits.filter((v) => v.id !== visit.id);
      demoStore.visits = [visit, ...withoutId].slice(0, MAX_VISITS);
    }
    return NextResponse.json({ ok: true, visit });
  } catch (error) {
    console.error("[api/visits] POST", error);
    return NextResponse.json(
      { ok: false, error: "No se pudo registrar la visita" },
      { status: 500 },
    );
  }
}
