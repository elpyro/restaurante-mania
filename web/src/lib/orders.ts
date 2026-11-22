import { cartTotals } from "./cart";
import { createDocument, getDocument, isFirestoreConfigured } from "./firebase/rest";
import { getMenu } from "./menu";
import type {
  Order,
  OrderItem,
  OrderType,
  PaymentMethod,
} from "./types";

const ORDER_TYPES: OrderType[] = ["pickup", "delivery", "table"];
const PAYMENT_METHODS: PaymentMethod[] = ["cash", "card", "nequi", "daviplata"];

export interface OrderInputItem {
  menuItemId: string;
  quantity: number;
}

export interface OrderInput {
  customerName: string;
  customerPhone: string;
  type: OrderType;
  tableNumber: number | null;
  paymentMethod: PaymentMethod;
  notes: string;
  items: OrderInputItem[];
}

export type ValidationResult =
  | { ok: true; value: OrderInput }
  | { ok: false; errors: string[] };

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function validateOrderInput(raw: unknown): ValidationResult {
  const errors: string[] = [];
  if (!raw || typeof raw !== "object") {
    return { ok: false, errors: ["El cuerpo del pedido es inválido."] };
  }
  const body = raw as Record<string, unknown>;

  const customerName = text(body.customerName);
  if (customerName.length < 2 || customerName.length > 80) {
    errors.push("El nombre debe tener entre 2 y 80 caracteres.");
  }

  const customerPhone = text(body.customerPhone);
  const phoneDigits = customerPhone.replace(/\D/g, "");
  if (phoneDigits.length < 7 || phoneDigits.length > 15) {
    errors.push("El teléfono debe tener entre 7 y 15 dígitos.");
  }

  const type = text(body.type) as OrderType;
  if (!ORDER_TYPES.includes(type)) {
    errors.push("El tipo de pedido no es válido.");
  }

  let tableNumber: number | null = null;
  if (type === "table") {
    const parsed = Number(body.tableNumber);
    if (!Number.isInteger(parsed) || parsed < 1 || parsed > 100) {
      errors.push("El número de mesa debe estar entre 1 y 100.");
    } else {
      tableNumber = parsed;
    }
  }

  const paymentMethod = text(body.paymentMethod) as PaymentMethod;
  if (!PAYMENT_METHODS.includes(paymentMethod)) {
    errors.push("El método de pago no es válido.");
  }

  const notes = text(body.notes);
  if (notes.length > 300) {
    errors.push("Las notas no pueden superar 300 caracteres.");
  }

  const rawItems = Array.isArray(body.items) ? body.items : [];
  if (rawItems.length === 0 || rawItems.length > 50) {
    errors.push("El pedido debe tener entre 1 y 50 productos.");
  }

  const items: OrderInputItem[] = [];
  const quantities = new Map<string, number>();
  for (const rawItem of rawItems) {
    if (!rawItem || typeof rawItem !== "object") {
      errors.push("Hay un producto con formato inválido.");
      continue;
    }
    const entry = rawItem as Record<string, unknown>;
    const menuItemId = text(entry.menuItemId);
    const quantity = Number(entry.quantity);
    if (!menuItemId) {
      errors.push("Hay un producto sin identificador.");
      continue;
    }
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 20) {
      errors.push("Las cantidades deben ser enteros entre 1 y 20.");
      continue;
    }
    const next = (quantities.get(menuItemId) ?? 0) + quantity;
    if (next > 20) {
      errors.push("La cantidad total por producto no puede superar 20.");
      continue;
    }
    quantities.set(menuItemId, next);
    items.push({ menuItemId, quantity });
  }

  if (errors.length > 0) return { ok: false, errors };

  return {
    ok: true,
    value: {
      customerName,
      customerPhone,
      type,
      tableNumber,
      paymentMethod,
      notes,
      items,
    },
  };
}

export class OrderValidationError extends Error {
  errors: string[];
  constructor(errors: string[]) {
    super(errors.join(" "));
    this.name = "OrderValidationError";
    this.errors = errors;
  }
}

function orderCode(): string {
  const date = new Date().toISOString().slice(0, 10).replace(/-/g, "");
  const random = Math.random().toString(36).slice(2, 6).toUpperCase();
  return `RM-${date}-${random}`;
}

const globalStore = globalThis as unknown as {
  __restauranteOrders?: Map<string, Order>;
};

function demoOrders(): Map<string, Order> {
  if (!globalStore.__restauranteOrders) {
    globalStore.__restauranteOrders = new Map();
  }
  return globalStore.__restauranteOrders;
}

export async function createOrder(raw: unknown): Promise<Order> {
  const validation = validateOrderInput(raw);
  if (!validation.ok) throw new OrderValidationError(validation.errors);

  const input = validation.value;
  const { items: menuItems } = await getMenu();
  const menuById = new Map(menuItems.map((item) => [item.id, item]));

  const errors: string[] = [];
  const orderItems: OrderItem[] = [];
  for (const line of input.items) {
    const menuItem = menuById.get(line.menuItemId);
    if (!menuItem) {
      errors.push(`El producto ${line.menuItemId} no existe en el menú.`);
      continue;
    }
    if (menuItem.status === "unavailable") {
      errors.push(`${menuItem.name} no está disponible en este momento.`);
      continue;
    }
    orderItems.push({
      menuItemId: menuItem.id,
      name: menuItem.name,
      price: menuItem.price,
      quantity: line.quantity,
      emoji: menuItem.emoji,
    });
  }

  if (errors.length > 0) throw new OrderValidationError(errors);

  const totals = cartTotals(orderItems);
  const now = new Date();
  const base = {
    code: orderCode(),
    customerName: input.customerName,
    customerPhone: input.customerPhone,
    type: input.type,
    tableNumber: input.tableNumber,
    items: orderItems,
    subtotal: totals.subtotal,
    tax: totals.tax,
    total: totals.total,
    status: "pending" as const,
    paymentStatus: "pending" as const,
    paymentMethod: input.paymentMethod,
    notes: input.notes,
    source: "web" as const,
    createdAt: now,
    updatedAt: now,
  };

  let id: string;
  if (isFirestoreConfigured()) {
    try {
      id = await createDocument("orders", base);
    } catch (error) {
      console.warn("[orders] No se pudo escribir en Firestore:", error);
      id = `demo-${now.getTime()}`;
    }
  } else {
    id = `demo-${now.getTime()}-${Math.random().toString(36).slice(2, 7)}`;
  }

  const order: Order = {
    ...base,
    id,
    createdAt: now.toISOString(),
    updatedAt: now.toISOString(),
  };

  const store = demoOrders();
  store.set(order.id, order);
  if (store.size > 200) {
    const oldest = store.keys().next().value;
    if (oldest) store.delete(oldest);
  }
  return order;
}

export async function getOrderById(id: string): Promise<Order | null> {
  const demo = demoOrders().get(id);
  if (demo) return demo;
  if (!isFirestoreConfigured()) return null;
  try {
    const data = await getDocument<Record<string, unknown>>("orders", id);
    if (!data) return null;
    return {
      ...(data as unknown as Order),
      id,
    };
  } catch {
    return null;
  }
}

export function listDemoOrders(): Order[] {
  return [...demoOrders().values()].sort(
    (a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt),
  );
}
