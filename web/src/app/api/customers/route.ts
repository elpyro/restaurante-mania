import { NextResponse } from "next/server";
import { isFirestoreConfigured, listDocuments, setDocument } from "@/lib/firebase/rest";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type CustomerPayload = {
  id?: string;
  name?: string;
  phone?: string;
  normalizedPhone?: string;
  address?: string;
  tags?: unknown;
  notes?: string;
  createdAt?: string;
  updatedAt?: string;
  lastOrderAt?: string;
  orderCount?: number;
  totalSpent?: number;
  lastType?: string;
  addresses?: unknown;
  visitCount?: number;
  visitHistory?: unknown;
};

function normalizePhone(value: string): string {
  return value.replace(/\D/g, "");
}

export async function GET() {
  if (!isFirestoreConfigured()) {
    return NextResponse.json({ customers: [], configured: false });
  }
  try {
    const customers = await listDocuments("customers", (doc) => {
      const d = doc.data as Record<string, unknown>;
      const rawHistory = d.visitHistory;
      const visitHistory: Record<string, number> = {};
      if (rawHistory && typeof rawHistory === "object" && !Array.isArray(rawHistory)) {
        for (const [k, v] of Object.entries(rawHistory as Record<string, unknown>)) {
          if (typeof v === "number" && Number.isFinite(v)) visitHistory[k] = Math.max(0, Math.floor(v));
        }
      }
      return {
        id: String(d.id ?? doc.id),
        name: String(d.name ?? ""),
        phone: String(d.phone ?? ""),
        normalizedPhone: String(d.normalizedPhone ?? normalizePhone(String(d.phone ?? ""))),
        address: String(d.address ?? ""),
        tags: Array.isArray(d.tags) ? d.tags.filter((t): t is string => typeof t === "string") : [],
        notes: String(d.notes ?? ""),
        createdAt: String(d.createdAt ?? new Date().toISOString()),
        updatedAt: String(d.updatedAt ?? new Date().toISOString()),
        lastOrderAt: String(d.lastOrderAt ?? new Date().toISOString()),
        orderCount: typeof d.orderCount === "number" ? d.orderCount : Number(d.orderCount ?? 0),
        totalSpent: typeof d.totalSpent === "number" ? d.totalSpent : Number(d.totalSpent ?? 0),
        lastType: String(d.lastType ?? "pickup"),
        addresses: Array.isArray(d.addresses) ? d.addresses.filter((a): a is string => typeof a === "string") : [],
        visitCount: typeof d.visitCount === "number" ? d.visitCount : Number(d.visitCount ?? 0),
        visitHistory,
      };
    }, 0);
    return NextResponse.json(
      { customers, configured: true },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch (error) {
    console.error("[api/customers] GET", error);
    return NextResponse.json({ error: "No se pudieron cargar clientes" }, { status: 500 });
  }
}

export async function POST(request: Request) {
  if (!isFirestoreConfigured()) {
    return NextResponse.json({ ok: false, configured: false, error: "Firestore no configurado" }, { status: 503 });
  }
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ ok: false, error: "JSON inválido" }, { status: 400 });
  }
  const input = (body ?? {}) as CustomerPayload;
  const phone = String(input.phone ?? "").trim();
  const normalized = normalizePhone(String(input.normalizedPhone ?? phone));
  if (normalized.length < 7) {
    return NextResponse.json({ ok: false, error: "Teléfono inválido" }, { status: 400 });
  }
  const id = String(input.id ?? `cus_${normalized}`);
  const now = new Date().toISOString();
  const rawHistory = input.visitHistory;
  const visitHistory: Record<string, number> = {};
  if (rawHistory && typeof rawHistory === "object" && !Array.isArray(rawHistory)) {
    for (const [k, v] of Object.entries(rawHistory as Record<string, unknown>)) {
      if (typeof v === "number" && Number.isFinite(v)) visitHistory[k] = Math.max(0, Math.floor(v));
    }
  }
  const record = {
    id,
    name: String(input.name ?? "").trim(),
    phone,
    normalizedPhone: normalized,
    address: String(input.address ?? "").trim(),
    tags: Array.isArray(input.tags) ? input.tags.filter((t): t is string => typeof t === "string").slice(0, 20) : [],
    notes: String(input.notes ?? "").trim().slice(0, 1000),
    createdAt: String(input.createdAt ?? now),
    updatedAt: String(input.updatedAt ?? now),
    lastOrderAt: String(input.lastOrderAt ?? now),
    orderCount: Math.max(0, Number(input.orderCount ?? 0) || 0),
    totalSpent: Math.max(0, Number(input.totalSpent ?? 0) || 0),
    lastType: ["pickup", "delivery", "table"].includes(String(input.lastType)) ? String(input.lastType) : "pickup",
    addresses: Array.isArray(input.addresses) ? input.addresses.filter((a): a is string => typeof a === "string").slice(0, 20) : [],
    visitCount: Math.max(0, Number(input.visitCount ?? 0) || 0),
    visitHistory,
  };
  try {
    await setDocument("customers", id, record);
    return NextResponse.json({ ok: true, customer: record });
  } catch (error) {
    console.error("[api/customers] POST", error);
    return NextResponse.json({ ok: false, error: "No se pudo guardar cliente" }, { status: 500 });
  }
}
