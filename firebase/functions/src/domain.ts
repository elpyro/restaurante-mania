/**
 * Lógica de dominio pura (sin SDK de Firebase) para poder probarla en
 * aislamiento. Las Cloud Functions solo orquestan E/S alrededor de estas
 * reglas de negocio.
 */

export const TAX_RATE = 0;

export type OrderStatus =
  | "pending"
  | "confirmed"
  | "preparing"
  | "ready"
  | "sent"
  | "delivered"
  | "cancelled";

export type OrderType = "pickup" | "delivery" | "table";
export type PaymentMethod = "cash" | "card" | "nequi" | "daviplata";

export interface PricedLine {
  menuItemId: string;
  name: string;
  price: number;
  quantity: number;
  emoji: string;
}

export interface Totals {
  subtotal: number;
  tax: number;
  total: number;
  count: number;
}

/** Redondea a pesos colombianos (sin centavos) evitando errores de coma flotante. */
export function roundMoney(value: number): number {
  return Math.round(value * 100) / 100;
}

export function computeTotals(lines: PricedLine[], taxRate = TAX_RATE): Totals {
  const subtotal = roundMoney(
    lines.reduce((sum, line) => sum + line.price * line.quantity, 0),
  );
  const tax = roundMoney(subtotal * taxRate);
  return {
    subtotal,
    tax,
    total: roundMoney(subtotal + tax),
    count: lines.reduce((sum, line) => sum + line.quantity, 0),
  };
}

/** Transiciones de estado permitidas para cada rol. */
export const ROLE_TRANSITIONS: Record<string, OrderStatus[]> = {
  cook: ["preparing", "ready", "sent"],
  waiter: ["confirmed", "delivered", "sent"],
  cashier: ["confirmed", "delivered", "cancelled", "sent"],
  admin: [
    "confirmed",
    "preparing",
    "ready",
    "sent",
    "delivered",
    "cancelled",
  ],
};

const NEXT_STATUS: Record<OrderStatus, OrderStatus | null> = {
  pending: "confirmed",
  confirmed: "preparing",
  preparing: "ready",
  ready: "delivered",
  sent: null,
  delivered: null,
  cancelled: null,
};

export function nextStatus(current: OrderStatus): OrderStatus | null {
  return NEXT_STATUS[current] ?? null;
}

export function nextStatusFor(
  current: OrderStatus,
  type: OrderType,
): OrderStatus | null {
  if (current === "ready") {
    return type === "delivery" ? "sent" : "delivered";
  }
  return NEXT_STATUS[current] ?? null;
}

export function canTransition(
  role: string | undefined,
  current: OrderStatus,
  target: OrderStatus,
  type?: OrderType,
): boolean {
  if (!role) return false;
  const allowed = ROLE_TRANSITIONS[role];
  if (!allowed) return false;
  if (current === target) return false;
  if (current === "delivered" || current === "cancelled" || current === "sent") {
    return false;
  }
  if (target === "cancelled") return role === "admin" || role === "cashier";
  if (target === "sent" && type && type !== "delivery") return false;
  if (target === "delivered" && type === "delivery") return false;
  return allowed.includes(target);
}

/** Clave de día en formato YYYY-MM-DD usada por las métricas. */
export function dayKey(date: Date): string {
  const year = date.getUTCFullYear();
  const month = `${date.getUTCMonth() + 1}`.padStart(2, "0");
  const day = `${date.getUTCDate()}`.padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function buildOrderCode(date: Date, random: string): string {
  const stamp = dayKey(date).replace(/-/g, "");
  return `RM-${stamp}-${random}`;
}

export function isValidQuantity(value: unknown): value is number {
  return (
    typeof value === "number" &&
    Number.isInteger(value) &&
    value >= 1 &&
    value <= 20
  );
}

export function isValidOrderType(value: unknown): value is OrderType {
  return value === "pickup" || value === "delivery" || value === "table";
}

export function isValidPaymentMethod(value: unknown): value is PaymentMethod {
  return (
    value === "cash" ||
    value === "card" ||
    value === "nequi" ||
    value === "daviplata"
  );
}

export function isValidTableNumber(value: unknown): value is number {
  return (
    typeof value === "number" &&
    Number.isInteger(value) &&
    value >= 1 &&
    value <= 100
  );
}

export function isValidCustomerName(value: unknown): value is string {
  return typeof value === "string" && value.trim().length >= 2 && value.trim().length <= 80;
}

export function isValidPhone(value: unknown): value is string {
  if (typeof value !== "string") return false;
  const digits = value.replace(/\D/g, "");
  return digits.length >= 7 && digits.length <= 15;
}
