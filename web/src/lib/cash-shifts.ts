import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

import { getDemoState } from "./demo-store";
import {
  isFirestoreConfigured,
  listDocuments,
  setDocument,
  tenantPath,
} from "./firebase/rest";
import { DEFAULT_TENANT_ID, isDemoTenant } from "./tenants";
import type { CashShift, PaymentMethod } from "./types";

const PAYMENT_METHODS: PaymentMethod[] = ["cash", "card", "nequi", "daviplata"];

const globalStore = globalThis as unknown as {
  __restauranteCashShifts?: Map<string, CashShift>;
};

function demoShifts(tenantId = DEFAULT_TENANT_ID): Map<string, CashShift> {
  if (isDemoTenant(tenantId)) return getDemoState(tenantId).shifts;
  if (!globalStore.__restauranteCashShifts) {
    globalStore.__restauranteCashShifts = new Map();
  }
  return globalStore.__restauranteCashShifts;
}

const DATA_DIR = path.join(process.cwd(), ".data");
const disablePersistence =
  process.env.VITEST === "true" ||
  process.env.NODE_ENV === "test" ||
  process.env.DISABLE_ORDER_PERSISTENCE === "true";

const diskLoaded = new Set<string>();

function shiftsFile(tenantId: string): string {
  return isDemoTenant(tenantId)
    ? path.join(DATA_DIR, tenantId, "cash-shifts.json")
    : path.join(DATA_DIR, "cash-shifts.json");
}

async function loadFromDisk(tenantId = DEFAULT_TENANT_ID): Promise<void> {
  if (disablePersistence || diskLoaded.has(tenantId)) return;
  diskLoaded.add(tenantId);
  try {
    const raw = await readFile(shiftsFile(tenantId), "utf8");
    const parsed: unknown = JSON.parse(raw);
    if (Array.isArray(parsed)) {
      for (const entry of parsed) {
        if (entry && typeof entry.id === "string") {
          demoShifts(tenantId).set(entry.id, normalizeShift(entry, entry.id));
        }
      }
    }
  } catch {
    /* archivo inexistente o inválido */
  }
}

async function persistToDisk(tenantId = DEFAULT_TENANT_ID): Promise<void> {
  if (disablePersistence || isFirestoreConfigured()) return;
  try {
    const file = shiftsFile(tenantId);
    await mkdir(path.dirname(file), { recursive: true });
    await writeFile(
      file,
      JSON.stringify(sortedShifts([...demoShifts(tenantId).values()]), null, 2),
      "utf8",
    );
  } catch {
    /* no bloquear el cierre de caja */
  }
}

export class CashShiftValidationError extends Error {
  errors: string[];
  constructor(errors: string[]) {
    super(errors.join(" "));
    this.name = "CashShiftValidationError";
    this.errors = errors;
  }
}

function pad(value: number): string {
  return value.toString().padStart(2, "0");
}

function iso(value: unknown, fallback: string): string {
  if (typeof value !== "string" || !value.trim()) return fallback;
  const timestamp = Date.parse(value);
  return Number.isNaN(timestamp) ? fallback : new Date(timestamp).toISOString();
}

function numeric(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function optionalNumeric(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return value;
}

function optionalText(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function totalsFrom(raw: unknown): Partial<Record<PaymentMethod, number>> {
  const totals: Partial<Record<PaymentMethod, number>> = {};
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return totals;
  for (const method of PAYMENT_METHODS) {
    const value = (raw as Record<string, unknown>)[method];
    if (typeof value === "number" && Number.isFinite(value)) {
      totals[method] = value;
    }
  }
  return totals;
}

function labelFor(openedAt: string): string {
  const date = new Date(openedAt);
  return `Turno ${pad(date.getDate())}/${pad(date.getMonth() + 1)} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function newId(): string {
  return `shift-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

export function makeCashShift(
  openedAt: string,
  openedBy?: string,
  openedByName = "Sistema",
): CashShift {
  const isoOpenedAt = iso(openedAt, new Date().toISOString());
  return {
    id: newId(),
    label: labelFor(isoOpenedAt),
    openedAt: isoOpenedAt,
    openedBy,
    openedByName,
    closedAt: null,
    orderCount: 0,
    total: 0,
    totalsByPaymentMethod: {},
    closingAmount: null,
    notes: "",
    status: "open",
  };
}

function normalizeShift(raw: unknown, fallbackId: string): CashShift {
  const source =
    raw && typeof raw === "object" && !Array.isArray(raw)
      ? (raw as Record<string, unknown>)
      : {};
  const openedAt = iso(source.openedAt, new Date().toISOString());
  const status = source.status === "closed" ? "closed" : "open";
  return {
    id: optionalText(source.id) ?? fallbackId,
    label: optionalText(source.label) ?? labelFor(openedAt),
    openedAt,
    openedBy: optionalText(source.openedBy),
    openedByName: optionalText(source.openedByName) ?? "Sistema",
    closedAt:
      source.closedAt === null || source.closedAt === undefined
        ? null
        : iso(source.closedAt, openedAt),
    closedBy: optionalText(source.closedBy),
    closedByName: optionalText(source.closedByName),
    orderCount: Math.max(0, Math.trunc(numeric(source.orderCount))),
    total: numeric(source.total),
    totalsByPaymentMethod: totalsFrom(source.totalsByPaymentMethod),
    closingAmount: optionalNumeric(source.closingAmount),
    notes: typeof source.notes === "string" ? source.notes.slice(0, 500) : "",
    status,
  };
}

function mapShiftDoc(doc: {
  id: string;
  data: Record<string, unknown>;
}): CashShift {
  return normalizeShift({ ...doc.data, id: doc.data.id ?? doc.id }, doc.id);
}

function sortedShifts(shifts: CashShift[]): CashShift[] {
  return [...shifts].sort(
    (a, b) => Date.parse(b.openedAt) - Date.parse(a.openedAt),
  );
}

async function readAllShifts(
  tenantId = DEFAULT_TENANT_ID,
): Promise<CashShift[]> {
  if (!isFirestoreConfigured()) {
    await loadFromDisk(tenantId);
    return sortedShifts([...demoShifts(tenantId).values()]);
  }
  try {
    const remote = await listDocuments(
      tenantPath(tenantId, "cashShifts"),
      mapShiftDoc,
      0,
    );
    if (remote.length > 0) return sortedShifts(remote);
  } catch (error) {
    console.warn("[cash-shifts] Firestore no disponible, usando caché local:", error);
  }
  return sortedShifts([...demoShifts(tenantId).values()]);
}

async function writeShift(
  shift: CashShift,
  tenantId = DEFAULT_TENANT_ID,
): Promise<void> {
  if (isFirestoreConfigured()) {
    // PATCH con updateMask crea el documento si aún no existe, así el id local
    // de la app se conserva y los reintentos son idempotentes.
    await setDocument(
      tenantPath(tenantId, "cashShifts"),
      shift.id,
      shift as unknown as Record<string, unknown>,
    );
  }
  demoShifts(tenantId).set(shift.id, shift);
  await persistToDisk(tenantId);
}

/** Solo tests: reinicia el almacén en memoria entre casos. */
export function resetCashShiftStoreForTests(tenantId?: string): void {
  if (tenantId && isDemoTenant(tenantId)) {
    demoShifts(tenantId).clear();
    return;
  }
  globalStore.__restauranteCashShifts = new Map();
}

export async function listCashShifts(
  tenantId = DEFAULT_TENANT_ID,
): Promise<CashShift[]> {
  return readAllShifts(tenantId);
}

export async function getCurrentCashShift(
  tenantId = DEFAULT_TENANT_ID,
): Promise<CashShift> {
  const shifts = await readAllShifts(tenantId);
  const open = shifts.find((shift) => shift.status === "open");
  if (open) return open;
  const created = makeCashShift(new Date().toISOString());
  await writeShift(created, tenantId);
  return created;
}

export interface CloseShiftResult {
  shift: CashShift;
  currentShift: CashShift;
  shifts: CashShift[];
}

/**
 * Cierra un turno y deja exactamente uno abierto. Es idempotente por `id`:
 * reenviar el mismo cierre (cola offline) no crea turnos nuevos.
 */
export async function closeCashShift(
  raw: unknown,
  tenantId = DEFAULT_TENANT_ID,
): Promise<CloseShiftResult> {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new CashShiftValidationError(["El turno enviado no es válido."]);
  }
  const source = raw as Record<string, unknown>;
  const id = optionalText(source.id);
  if (!id) {
    throw new CashShiftValidationError(["El turno enviado no tiene identificador."]);
  }
  if (Number.isNaN(Date.parse(iso(source.openedAt, "")))) {
    throw new CashShiftValidationError(["La fecha de apertura no es válida."]);
  }

  if (!isFirestoreConfigured()) await loadFromDisk(tenantId);
  const existing = await readAllShifts(tenantId);
  const incoming = normalizeShift(source, id);
  const alreadyClosed = existing.find(
    (shift) => shift.id === id && shift.status === "closed",
  );
  const closed: CashShift = alreadyClosed ?? {
    ...incoming,
    status: "closed",
    closedAt: incoming.closedAt ?? new Date().toISOString(),
    label: incoming.label || labelFor(incoming.openedAt),
  };

  if (!alreadyClosed) {
    await writeShift(closed, tenantId);
    for (const open of existing) {
      if (open.id === id || open.status !== "open") continue;
      await writeShift({
        ...open,
        status: "closed",
        closedAt: closed.closedAt,
        closedBy: closed.closedBy,
        closedByName: closed.closedByName,
        orderCount: 0,
        total: 0,
        totalsByPaymentMethod: {},
        closingAmount: null,
        notes: "Cerrado automáticamente al cerrar caja.",
      }, tenantId);
    }
  }

  const afterClose = await readAllShifts(tenantId);
  const open = afterClose.find((shift) => shift.status === "open");
  const currentShift =
    open ?? makeCashShift(new Date().toISOString(), closed.closedBy, closed.closedByName);
  if (!open) await writeShift(currentShift, tenantId);

  return {
    shift: closed,
    currentShift,
    shifts: sortedShifts(
      afterClose.some((shift) => shift.id === currentShift.id)
        ? afterClose
        : [...afterClose, currentShift],
    ),
  };
}
