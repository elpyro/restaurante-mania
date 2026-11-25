import { cartTotals } from "./cart";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import path from "node:path";
import {
  createDocument,
  getDocument,
  isFirestoreConfigured,
  listDocuments,
  setDocument,
} from "./firebase/rest";
import { getMenu } from "./menu";
import { getRestaurantConfig } from "./restaurant-config";
import { demoIngredientStocks } from "./seed";
import type {
  MenuItem,
  Order,
  OrderItem,
  OrderStatus,
  OrderType,
  PaymentMethod,
  PaymentStatus,
} from "./types";

const ORDER_TYPES: OrderType[] = ["pickup", "delivery", "table"];
const PAYMENT_METHODS: PaymentMethod[] = ["cash", "card", "nequi", "daviplata"];

/** Política publicada desde la APK; por defecto todo está disponible. */
export interface OrderPolicy {
  showOrderTypeOptions: boolean;
  deliveryOptions: Record<OrderType, boolean>;
  paymentMethods: PaymentMethod[];
}

export const DEFAULT_ORDER_POLICY: OrderPolicy = {
  showOrderTypeOptions: true,
  deliveryOptions: { pickup: true, delivery: true, table: true },
  paymentMethods: [...PAYMENT_METHODS],
};

export function restaurantOrderPolicy(
  config: Awaited<ReturnType<typeof getRestaurantConfig>>["config"],
): OrderPolicy {
  return {
    showOrderTypeOptions: config.showOrderTypeOptions,
    deliveryOptions: config.deliveryOptions,
    paymentMethods: config.paymentMethods,
  };
}

export interface OrderInputItem {
  menuItemId: string;
  quantity: number;
}

export interface OrderInput {
  customerName: string;
  customerPhone: string;
  deliveryAddress: string;
  type: OrderType;
  tableNumber: number | null;
  paymentMethod: PaymentMethod;
  notes: string;
  items: OrderInputItem[];
}

export type ValidationResult =
  | { ok: true; value: OrderInput }
  | { ok: false; errors: string[] };

export type ItemsValidationResult =
  | { ok: true; items: OrderInputItem[] }
  | { ok: false; errors: string[] };

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function validateOrderItems(raw: unknown): ItemsValidationResult {
  const errors: string[] = [];
  const rawItems = Array.isArray(raw) ? raw : [];
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
  return { ok: true, items };
}

export function validateOrderInput(
  raw: unknown,
  policy: OrderPolicy = DEFAULT_ORDER_POLICY,
): ValidationResult {
  const errors: string[] = [];
  if (!raw || typeof raw !== "object") {
    return { ok: false, errors: ["El cuerpo del pedido es inválido."] };
  }
  const body = raw as Record<string, unknown>;

  const customerName = text(body.customerName);
  const customerPhone = text(body.customerPhone);
  const deliveryAddress = text(body.deliveryAddress);
  const type = text(body.type) as OrderType;
  const isTable = type === "table";
  const isDelivery = type === "delivery";

  if (!ORDER_TYPES.includes(type)) {
    errors.push("El tipo de pedido no es válido.");
  } else if (!policy.deliveryOptions[type]) {
    errors.push("Ese tipo de pedido no está disponible en este momento.");
  }

  if (!isTable) {
    if (customerName.length < 2 || customerName.length > 80) {
      errors.push("El nombre debe tener entre 2 y 80 caracteres.");
    }
    const phoneDigits = customerPhone.replace(/\D/g, "");
    if (phoneDigits.length < 7 || phoneDigits.length > 15) {
      errors.push("El teléfono debe tener entre 7 y 15 dígitos.");
    }
  } else {
    if (customerName.length > 80) {
      errors.push("El nombre no puede superar 80 caracteres.");
    }
    const phoneDigits = customerPhone.replace(/\D/g, "");
    if (customerPhone && (phoneDigits.length < 7 || phoneDigits.length > 15)) {
      errors.push("El teléfono debe tener entre 7 y 15 dígitos.");
    }
  }

  if (isDelivery) {
    if (deliveryAddress.length < 5 || deliveryAddress.length > 160) {
      errors.push("La dirección de domicilio debe tener entre 5 y 160 caracteres.");
    }
  } else if (deliveryAddress.length > 160) {
    errors.push("La dirección no puede superar 160 caracteres.");
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
  if (
    !PAYMENT_METHODS.includes(paymentMethod) ||
    !policy.paymentMethods.includes(paymentMethod)
  ) {
    errors.push("El método de pago no está disponible en este momento.");
  }

  const notes = text(body.notes);
  if (notes.length > 300) {
    errors.push("Las notas no pueden superar 300 caracteres.");
  }

  const itemsResult = validateOrderItems(body.items);
  if (!itemsResult.ok) errors.push(...itemsResult.errors);
  const items = itemsResult.ok ? itemsResult.items : [];

  if (errors.length > 0) return { ok: false, errors };

  return {
    ok: true,
    value: {
      customerName,
      customerPhone,
      deliveryAddress,
      type,
      tableNumber,
      paymentMethod,
      notes,
      items,
    },
  };
}

export interface InsufficientItem {
  menuItemId: string;
  name: string;
  requested: number;
  available: number;
}

export class OrderValidationError extends Error {
  errors: string[];
  insufficientItems: InsufficientItem[];
  constructor(errors: string[], insufficientItems: InsufficientItem[] = []) {
    super(errors.join(" "));
    this.name = "OrderValidationError";
    this.errors = errors;
    this.insufficientItems = insufficientItems;
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

function mapOrderDoc(doc: {
  id: string;
  data: Record<string, unknown>;
}): Order {
  const d = doc.data;
  const items: OrderItem[] = Array.isArray(d.items)
    ? d.items
        .filter((entry): entry is Record<string, unknown> => Boolean(entry) && typeof entry === "object")
        .map((entry) => ({
          menuItemId: String(entry.menuItemId ?? ""),
          name: String(entry.name ?? ""),
          price: Number(entry.price ?? 0),
          quantity: Number(entry.quantity ?? 0),
          emoji: String(entry.emoji ?? ""),
          imageUrl: String(entry.imageUrl ?? ""),
        }))
    : [];
  return {
    id: String(d.id ?? doc.id),
    code: String(d.code ?? ""),
    customerName: String(d.customerName ?? ""),
    customerPhone: String(d.customerPhone ?? ""),
    deliveryAddress: String(d.deliveryAddress ?? ""),
    type: (String(d.type ?? "pickup") as Order["type"]),
    tableNumber:
      typeof d.tableNumber === "number" && Number.isFinite(d.tableNumber)
        ? Math.trunc(d.tableNumber)
        : null,
    items,
    subtotal: Number(d.subtotal ?? 0),
    tax: Number(d.tax ?? 0),
    total: Number(d.total ?? 0),
    status: String(d.status ?? "pending") as Order["status"],
    paymentStatus: String(d.paymentStatus ?? "pending") as Order["paymentStatus"],
    paymentMethod: String(d.paymentMethod ?? "cash") as Order["paymentMethod"],
    notes: String(d.notes ?? ""),
    createdAt: String(d.createdAt ?? new Date().toISOString()),
    updatedAt: String(d.updatedAt ?? d.createdAt ?? new Date().toISOString()),
    source: d.source === "app" ? "app" : "web",
    ...(typeof d.inventoryDeducted === "boolean"
      ? { inventoryDeducted: d.inventoryDeducted }
      : {}),
    ...(typeof d.paidAt === "string" && d.paidAt.trim()
      ? { paidAt: d.paidAt }
      : {}),
    ...(typeof d.paidBy === "string" ? { paidBy: d.paidBy } : {}),
    ...(typeof d.paidByName === "string" ? { paidByName: d.paidByName } : {}),
  };
}

const DATA_DIR = path.join(process.cwd(), ".data");
const DATA_FILE = path.join(DATA_DIR, "orders.json");
const disablePersistence =
  process.env.VITEST === "true" ||
  process.env.NODE_ENV === "test" ||
  process.env.DISABLE_ORDER_PERSISTENCE === "true";

let diskLoaded = false;

async function loadFromDisk() {
  if (disablePersistence || diskLoaded) return;
  diskLoaded = true;
  try {
    const raw = await readFile(DATA_FILE, "utf8");
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) {
      for (const entry of parsed) {
        if (entry && typeof entry.id === "string") {
          demoOrders().set(entry.id, entry as Order);
        }
      }
    }
  } catch {
    /* archivo inexistente o inválido */
  }
}

async function persistOrdersToDisk() {
  if (disablePersistence) return;
  try {
    await mkdir(DATA_DIR, { recursive: true });
    await writeFile(
      DATA_FILE,
      JSON.stringify(listDemoOrders().slice(0, 200), null, 2),
      "utf8",
    );
  } catch {
    /* no bloquear la creación del pedido */
  }
}

async function loadIngredientStocks(): Promise<Map<string, number>> {
  if (isFirestoreConfigured()) {
    const ingredientDocs = await listDocuments(
      "ingredients",
      (doc) => ({
        id: doc.id,
        stock:
          typeof doc.data.stock === "number" && Number.isFinite(doc.data.stock)
            ? (doc.data.stock as number)
            : 0,
      }),
      0,
    );
    return new Map(ingredientDocs.map((i) => [i.id, i.stock]));
  }
  return new Map(Object.entries(demoIngredientStocks));
}

type StockLine = Pick<OrderInputItem, "menuItemId" | "quantity">;
type StockUpdate = { id: string; stock: number };

/** Estado a partir del cual el pedido ya consume insumos (pendiente no consume). */
function isDeductibleStatus(status: OrderStatus): boolean {
  return (
    status !== "pending" &&
    status !== "cancelled" &&
    ORDER_STATUSES.includes(status)
  );
}

function stockConsumption(
  items: StockLine[],
  menuById: Map<string, MenuItem>,
): Map<string, number> {
  const consumption = new Map<string, number>();
  for (const line of items) {
    const menuItem = menuById.get(line.menuItemId);
    if (!menuItem?.recipe?.length) continue;
    for (const recipeLine of menuItem.recipe) {
      if (!recipeLine.ingredientId || recipeLine.quantity <= 0) continue;
      consumption.set(
        recipeLine.ingredientId,
        (consumption.get(recipeLine.ingredientId) ?? 0) +
          recipeLine.quantity * line.quantity,
      );
    }
  }
  return consumption;
}

async function applyStockUpdates(updates: StockUpdate[]): Promise<void> {
  if (updates.length === 0) return;
  if (isFirestoreConfigured()) {
    const updatedAt = new Date().toISOString();
    await Promise.all(
      updates.map(({ id, stock }) =>
        setDocument("ingredients", id, { stock, updatedAt }),
      ),
    );
  } else {
    for (const { id, stock } of updates) demoIngredientStocks[id] = stock;
  }
}

/** Descuenta los insumos cuando el pedido avanza más allá de `pending`. */
async function deductStockForItems(
  items: StockLine[],
  menuById: Map<string, MenuItem>,
): Promise<StockUpdate[]> {
  const consumption = stockConsumption(items, menuById);
  if (consumption.size === 0) return [];

  const stocks = await loadIngredientStocks();
  const updates: StockUpdate[] = [];
  for (const [ingredientId, required] of consumption) {
    const current = stocks.get(ingredientId);
    if (current === undefined) continue;
    updates.push({ id: ingredientId, stock: Math.max(0, current - required) });
  }
  await applyStockUpdates(updates);
  return updates;
}

/** Repone los insumos al cancelar un pedido que ya había descontado. */
async function restoreStockForItems(
  items: StockLine[],
  menuById: Map<string, MenuItem>,
): Promise<StockUpdate[]> {
  const consumption = stockConsumption(items, menuById);
  if (consumption.size === 0) return [];

  const stocks = await loadIngredientStocks();
  const updates: StockUpdate[] = [];
  for (const [ingredientId, required] of consumption) {
    const current = stocks.get(ingredientId);
    if (current === undefined) continue;
    updates.push({ id: ingredientId, stock: current + required });
  }
  await applyStockUpdates(updates);
  return updates;
}

export async function getInsufficientItems(
  inputItems: OrderInputItem[],
  menuById: Map<string, MenuItem>,
): Promise<InsufficientItem[]> {
  const hasRecipe = inputItems.some(
    (line) => (menuById.get(line.menuItemId)?.recipe?.length ?? 0) > 0,
  );
  if (!hasRecipe) return [];

  const stocks = await loadIngredientStocks();
  const consumption = new Map<string, number>();
  for (const line of inputItems) {
    const menuItem = menuById.get(line.menuItemId);
    if (!menuItem?.recipe) continue;
    for (const r of menuItem.recipe) {
      consumption.set(
        r.ingredientId,
        (consumption.get(r.ingredientId) ?? 0) + r.quantity * line.quantity,
      );
    }
  }

  const overStock = [...consumption.entries()].filter(([ingredientId, required]) => {
    const stock = stocks.get(ingredientId);
    return stock !== undefined && required > stock + 0.0001;
  });
  if (overStock.length === 0) return [];

  const insufficient: InsufficientItem[] = [];
  for (const line of inputItems) {
    const menuItem = menuById.get(line.menuItemId);
    if (!menuItem?.recipe?.length) continue;
    const contributes = menuItem.recipe.some((r) =>
      overStock.some(([id]) => id === r.ingredientId),
    );
    if (!contributes) continue;

    const othersConsumption = new Map<string, number>();
    for (const other of inputItems) {
      if (other.menuItemId === line.menuItemId) continue;
      const otherItem = menuById.get(other.menuItemId);
      if (!otherItem?.recipe) continue;
      for (const r of otherItem.recipe) {
        othersConsumption.set(
          r.ingredientId,
          (othersConsumption.get(r.ingredientId) ?? 0) + r.quantity * other.quantity,
        );
      }
    }

    let available = line.quantity;
    for (const r of menuItem.recipe) {
      const stock = stocks.get(r.ingredientId);
      if (stock === undefined) continue;
      const remaining = stock - (othersConsumption.get(r.ingredientId) ?? 0);
      const canMake = remaining <= 0 ? 0 : Math.floor(remaining / r.quantity);
      if (canMake < available) available = canMake;
    }
    available = Math.max(0, available);
    if (available < line.quantity) {
      insufficient.push({
        menuItemId: line.menuItemId,
        name: menuItem.name,
        requested: line.quantity,
        available,
      });
    }
  }
  return insufficient;
}

export async function createOrder(raw: unknown): Promise<Order> {
  const { config } = await getRestaurantConfig();
  const validation = validateOrderInput(raw, restaurantOrderPolicy(config));
  if (!validation.ok) throw new OrderValidationError(validation.errors);

  const input = validation.value;
  const resolvedCustomerName =
    input.type === "table" && input.customerName.trim().length < 2
      ? `Mesa ${input.tableNumber}`
      : input.customerName;
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
      imageUrl: menuItem.imageUrl,
    });
  }

  let insufficientItems: InsufficientItem[] = [];
  if (errors.length === 0) {
    const hasRecipe = input.items.some(
      (line) => (menuById.get(line.menuItemId)?.recipe?.length ?? 0) > 0,
    );
    if (hasRecipe) {
      try {
        insufficientItems = await getInsufficientItems(input.items, menuById);
      } catch (error) {
        console.warn("[orders] No se pudo validar stock de ingredientes:", error);
        errors.push(
          "No pudimos verificar la disponibilidad de ingredientes. Intenta de nuevo.",
        );
      }
    }
  }

  if (insufficientItems.length > 0) {
    const details = insufficientItems
      .map((i) =>
        i.available > 0
          ? `${i.name}: solo hay ${i.available} disponible(s)`
          : `${i.name}: sin ingredientes disponibles`,
      )
      .join(". ");
    errors.push(`Ingredientes insuficientes. ${details}.`);
  }

  if (errors.length > 0) throw new OrderValidationError(errors, insufficientItems);

  // Un pedido recién creado queda en `pending` y aún no consume insumos.
  // El descuento ocurre al avanzar a un estado superior (ver `updateOrder`).
  const totals = cartTotals(orderItems);
  const now = new Date();
  const base = {
    code: orderCode(),
    customerName: resolvedCustomerName,
    customerPhone: input.customerPhone,
    deliveryAddress: input.type === "delivery" ? input.deliveryAddress : "",
    type: input.type,
    tableNumber: input.tableNumber,
    items: orderItems,
    subtotal: totals.subtotal,
    tax: totals.tax,
    total: totals.total,
    status: "pending" as const,
    paymentStatus: "pending" as const,
    inventoryDeducted: false,
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
  await persistOrdersToDisk();
  return order;
}

export async function getOrderById(id: string): Promise<Order | null> {
  await loadFromDisk();
  const demo = demoOrders().get(id);
  if (demo && !isFirestoreConfigured()) return demo;
  if (!isFirestoreConfigured()) return null;
  try {
    const data = await getDocument<Record<string, unknown>>("orders", id);
    if (data) return mapOrderDoc({ id, data });
  } catch (error) {
    console.warn("[orders] No se pudo leer el pedido de Firestore:", error);
  }
  return demo ?? null;
}

export function listDemoOrders(): Order[] {
  return [...demoOrders().values()].sort(
    (a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt),
  );
}

export async function listOrders(): Promise<Order[]> {
  await loadFromDisk();
  if (isFirestoreConfigured()) {
    try {
      const orders = await listDocuments("orders", mapOrderDoc, 0);
      return orders.sort(
        (a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt),
      );
    } catch (error) {
      console.warn("[orders] Firestore no disponible, usando pedidos locales:", error);
    }
  }
  return listDemoOrders();
}

const ORDER_STATUSES: OrderStatus[] = [
  "pending",
  "confirmed",
  "preparing",
  "ready",
  "sent",
  "delivered",
  "cancelled",
];
const PAYMENT_STATUSES: PaymentStatus[] = ["pending", "paid", "refunded"];

function normalizePaidAt(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  if (!trimmed) return undefined;
  const timestamp = Date.parse(trimmed);
  return Number.isNaN(timestamp) ? undefined : new Date(timestamp).toISOString();
}

export interface OrderPaymentPatch {
  paidAt?: string;
  paidBy?: string;
  paidByName?: string;
}

export async function updateOrder(
  id: string,
  patch: {
    status?: OrderStatus;
    paymentStatus?: PaymentStatus;
    inventoryDeducted?: boolean;
  } & OrderPaymentPatch,
): Promise<Order | null> {
  await loadFromDisk();
  // Con Firestore, la fuente de verdad es el documento remoto: la copia en
  // memoria puede tener un `inventoryDeducted` viejo (p. ej. el pedido ya
  // descontó en otro proceso del servidor) y Reponer/Deductir se decidiría mal.
  // `getOrderById` ya cae al caché local si la lectura remota falla.
  const current = isFirestoreConfigured()
    ? await getOrderById(id)
    : demoOrders().get(id) ?? null;
  if (!current) return null;

  const wasDeducted = current.inventoryDeducted === true;
  const next: Order = { ...current };
  if (patch.status) {
    if (!ORDER_STATUSES.includes(patch.status)) {
      throw new OrderValidationError(["Estado de pedido inválido."]);
    }
    next.status = patch.status;
  }
  if (patch.paymentStatus) {
    if (!PAYMENT_STATUSES.includes(patch.paymentStatus)) {
      throw new OrderValidationError(["Estado de pago inválido."]);
    }
    next.paymentStatus = patch.paymentStatus;
  }
  if (typeof patch.inventoryDeducted === "boolean") {
    next.inventoryDeducted = patch.inventoryDeducted;
  }
  const paidAt = normalizePaidAt(patch.paidAt);
  if (paidAt) next.paidAt = paidAt;
  if (typeof patch.paidBy === "string") {
    const paidBy = patch.paidBy.trim();
    if (paidBy) next.paidBy = paidBy;
  }
  if (typeof patch.paidByName === "string") {
    const paidByName = patch.paidByName.trim();
    if (paidByName) next.paidByName = paidByName;
  }
  // Cobros heredados o desde la web pública: dejar huella aunque el cliente
  // no envíe metadata. Los datos enviados por la app tienen prioridad.
  if (next.paymentStatus === "paid" && current.paymentStatus !== "paid") {
    next.paidAt ??= new Date().toISOString();
    next.paidByName ??= current.source === "web" ? "Web pública" : "Sistema";
  }
  next.updatedAt = new Date().toISOString();

  // `pending` no descuenta insumos. El descuento se hace una sola vez al
  // avanzar a cualquier estado superior y se repone al cancelar/reabrir.
  if (patch.status) {
    const { items: menuItems } = await getMenu();
    const menuById = new Map(menuItems.map((item) => [item.id, item]));
    // La decisión la manda el flag persistido, no el que envía el cliente: la
    // app reenvía `inventoryDeducted: true` junto al cambio de estado después
    // de descontar localmente, pero la web aún no había descontado.
    if (isDeductibleStatus(patch.status) && !wasDeducted) {
      try {
        const updates = await deductStockForItems(current.items, menuById);
        if (updates.length > 0) next.inventoryDeducted = true;
      } catch (error) {
        console.error("[orders] No se pudo descontar el inventario:", error);
        throw new OrderValidationError([
          "No se pudo descontar el inventario. Intenta de nuevo.",
        ]);
      }
    } else if (
      (patch.status === "cancelled" || patch.status === "pending") &&
      wasDeducted
    ) {
      try {
        await restoreStockForItems(current.items, menuById);
        next.inventoryDeducted = false;
      } catch (error) {
        console.error("[orders] No se pudo reponer el inventario:", error);
        throw new OrderValidationError([
          "No se pudo reponer el inventario. Intenta de nuevo.",
        ]);
      }
    }
  }

  if (isFirestoreConfigured()) {
    try {
      await setDocument("orders", id, next as unknown as Record<string, unknown>);
    } catch (error) {
      console.error("[orders] No se pudo actualizar Firestore:", error);
      throw error;
    }
  }

  demoOrders().set(id, next);
  await persistOrdersToDisk();
  return next;
}
