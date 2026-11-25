import { setGlobalOptions } from "firebase-functions/v2";
import {
  HttpsError,
  onCall,
  onRequest,
  type CallableRequest,
} from "firebase-functions/v2/https";
import {
  onDocumentCreated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import { initializeApp } from "firebase-admin/app";
import {
  FieldValue,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";

import {
  buildOrderCode,
  canTransition,
  computeTotals,
  dayKey,
  deriveMenuItemStatus,
  isValidCustomerName,
  isValidOrderType,
  isValidPaymentMethod,
  isValidPhone,
  isValidQuantity,
  isValidTableNumber,
  type OrderStatus,
  type PricedLine,
  type RecipeLine,
} from "./domain";

setGlobalOptions({ region: "us-central1", maxInstances: 20 });
initializeApp();

const db = getFirestore();

// =============================================================================
// Tipos de entrada
// =============================================================================

interface PlaceOrderItem {
  menuItemId: string;
  quantity: number;
}

interface PlaceOrderPayload {
  customerName: string;
  customerPhone: string;
  deliveryAddress?: string;
  type: "pickup" | "delivery" | "table";
  tableNumber?: number | null;
  paymentMethod: "cash" | "card" | "nequi" | "daviplata";
  notes?: string;
  items: PlaceOrderItem[];
}

interface UpdateStatusPayload {
  orderId: string;
  status: OrderStatus;
}

// =============================================================================
// Health check
// =============================================================================

export const health = onRequest((_request, response) => {
  response.status(200).json({
    status: "ok",
    service: "restaurante-mania-functions",
    timestamp: new Date().toISOString(),
  });
});

// =============================================================================
// placeOrder: crea un pedido validando precios en el servidor.
// Evita que un cliente manipule el total enviado desde el dispositivo.
// =============================================================================

export const placeOrder = onCall(async (request: CallableRequest) => {
  const payload = request.data as Partial<PlaceOrderPayload> | undefined;
  if (!payload || typeof payload !== "object") {
    throw new HttpsError("invalid-argument", "El pedido es inválido.");
  }

  const errors: string[] = [];

  const isTable = payload.type === "table";
  const isDelivery = payload.type === "delivery";
  const deliveryAddress =
    typeof payload.deliveryAddress === "string" ? payload.deliveryAddress.trim() : "";
  if (isTable) {
    if (
      payload.customerName !== undefined &&
      payload.customerName !== null &&
      payload.customerName !== "" &&
      !isValidCustomerName(payload.customerName)
    ) {
      errors.push("El nombre debe tener entre 2 y 80 caracteres.");
    }
    if (
      payload.customerPhone !== undefined &&
      payload.customerPhone !== null &&
      payload.customerPhone !== "" &&
      !isValidPhone(payload.customerPhone)
    ) {
      errors.push("El teléfono debe tener entre 7 y 15 dígitos.");
    }
  } else {
    if (!isValidCustomerName(payload.customerName)) {
      errors.push("El nombre debe tener entre 2 y 80 caracteres.");
    }
    if (!isValidPhone(payload.customerPhone)) {
      errors.push("El teléfono debe tener entre 7 y 15 dígitos.");
    }
  }
  if (!isValidOrderType(payload.type)) {
    errors.push("El tipo de pedido no es válido.");
  }
  if (!isValidPaymentMethod(payload.paymentMethod)) {
    errors.push("El método de pago no es válido.");
  }
  if (payload.type === "table" && !isValidTableNumber(payload.tableNumber)) {
    errors.push("El número de mesa debe estar entre 1 y 100.");
  }
  if (isDelivery) {
    if (deliveryAddress.length < 5 || deliveryAddress.length > 160) {
      errors.push("La dirección de domicilio debe tener entre 5 y 160 caracteres.");
    }
  } else if (deliveryAddress.length > 160) {
    errors.push("La dirección no puede superar 160 caracteres.");
  }
  const notes = typeof payload.notes === "string" ? payload.notes.trim() : "";
  if (notes.length > 300) {
    errors.push("Las notas no pueden superar 300 caracteres.");
  }

  const rawItems = Array.isArray(payload.items) ? payload.items : [];
  if (rawItems.length === 0 || rawItems.length > 50) {
    errors.push("El pedido debe tener entre 1 y 50 productos.");
  }

  const quantities = new Map<string, number>();
  for (const item of rawItems) {
    if (!item || typeof item !== "object") {
      errors.push("Hay un producto con formato inválido.");
      continue;
    }
    const { menuItemId, quantity } = item as PlaceOrderItem;
    if (typeof menuItemId !== "string" || menuItemId.length === 0) {
      errors.push("Hay un producto sin identificador.");
      continue;
    }
    if (!isValidQuantity(quantity)) {
      errors.push("Las cantidades deben ser enteros entre 1 y 20.");
      continue;
    }
    const next = (quantities.get(menuItemId) ?? 0) + quantity;
    if (next > 20) {
      errors.push("La cantidad total por producto no puede superar 20.");
      continue;
    }
    quantities.set(menuItemId, next);
  }

  if (errors.length > 0) {
    throw new HttpsError("invalid-argument", errors.join(" "), { errors });
  }

  // Precios siempre desde Firestore, nunca desde el cliente.
  const ids = [...quantities.keys()];
  const refs = ids.map((id) => db.collection("menuItems").doc(id));
  const snapshots = await db.getAll(...refs);

  const lines: PricedLine[] = [];
  const missing: string[] = [];

  snapshots.forEach((snapshot) => {
    if (!snapshot.exists) {
      missing.push(snapshot.id);
      return;
    }
    const data = snapshot.data() ?? {};
    const quantity = quantities.get(snapshot.id) ?? 0;
    if (data.status === "unavailable") {
      missing.push(String(data.name ?? snapshot.id));
      return;
    }
    const price = typeof data.price === "number" ? data.price : 0;
    if (price <= 0) {
      missing.push(String(data.name ?? snapshot.id));
      return;
    }
    lines.push({
      menuItemId: snapshot.id,
      name: String(data.name ?? "Producto"),
      price,
      quantity,
      emoji: String(data.emoji ?? "🍽️"),
    });

  });

  if (missing.length > 0) {
    throw new HttpsError(
      "failed-precondition",
      `Productos no disponibles: ${missing.join(", ")}`,
      { unavailable: missing },
    );
  }

  const totals = computeTotals(lines);
  const now = Timestamp.now();
  const code = buildOrderCode(
    now.toDate(),
    Math.random().toString(36).slice(2, 6).toUpperCase(),
  );

  const resolvedCustomerName =
    isTable && (typeof payload.customerName !== "string" || !payload.customerName.trim())
      ? `Mesa ${payload.tableNumber}`
      : String(payload.customerName).trim();
  const resolvedCustomerPhone =
    isTable && (typeof payload.customerPhone !== "string" || !payload.customerPhone.trim())
      ? ""
      : String(payload.customerPhone).trim();

  const orderRef = db.collection("orders").doc();
  await db.runTransaction(async (transaction) => {
    // Pendiente no consume insumos; el descuento ocurre en updateOrderStatus.
    transaction.set(orderRef, {
      code,
      customerName: resolvedCustomerName,
      customerPhone: resolvedCustomerPhone,
      deliveryAddress: isDelivery ? deliveryAddress : "",
      type: payload.type,
      tableNumber: payload.type === "table" ? payload.tableNumber ?? null : null,
      items: lines,
      subtotal: totals.subtotal,
      tax: totals.tax,
      total: totals.total,
      status: "pending",
      paymentStatus: "pending",
      inventoryDeducted: false,
      paymentMethod: payload.paymentMethod,
      notes,
      source: request.auth ? "app" : "web",
      createdBy: request.auth?.uid ?? null,
      createdAt: now,
      updatedAt: now,
    });
  });

  if (isTable && isValidTableNumber(payload.tableNumber)) {
    const tableQuery = await db
      .collection("tables")
      .where("number", "==", payload.tableNumber)
      .limit(1)
      .get();
    const tableDoc = tableQuery.docs[0];
    if (tableDoc) {
      await tableDoc.ref.update({
        status: "ocupada",
        currentOrderId: orderRef.id,
        updatedAt: now,
      });
    }
  }

  logger.info("Pedido creado", {
    orderId: orderRef.id,
    code,
    total: totals.total,
  });

  return {
    id: orderRef.id,
    code,
    subtotal: totals.subtotal,
    tax: totals.tax,
    total: totals.total,
    itemCount: totals.count,
  };
});

// =============================================================================
// syncMenuStatusOnIngredientChange: persistir la disponibilidad derivada del
// stock. La web y la app siguen calculando `maxServings` al leer, pero el
// estado escrito en Firestore debe quedar sincronizado para el catálogo, los
// pedidos y cualquier consumer externo.
// =============================================================================

function readRecipe(value: unknown): RecipeLine[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry) => {
    if (!entry || typeof entry !== "object") return [];
    const row = entry as Record<string, unknown>;
    const ingredientId =
      typeof row.ingredientId === "string" ? row.ingredientId : "";
    const quantity =
      typeof row.quantity === "number" && Number.isFinite(row.quantity)
        ? row.quantity
        : 0;
    return ingredientId.length > 0 && quantity > 0
      ? [{ ingredientId, quantity }]
      : [];
  });
}

export const syncMenuStatusOnIngredientChange = onDocumentWritten(
  "ingredients/{ingredientId}",
  async (event) => {
    const changedId = event.params.ingredientId;
    const menuSnapshot = await db.collection("menuItems").get();
    const affected = menuSnapshot.docs.filter((doc) =>
      readRecipe(doc.data()?.recipe).some(
        (line) => line.ingredientId === changedId,
      ),
    );
    if (affected.length === 0) return;

    const ingredientIds = [
      ...new Set(
        affected.flatMap((doc) =>
          readRecipe(doc.data()?.recipe).map((line) => line.ingredientId),
        ),
      ),
    ];
    const stockSnapshots = await Promise.all(
      ingredientIds.map((id) => db.collection("ingredients").doc(id).get()),
    );
    const stocks = new Map<string, number>();
    for (const snapshot of stockSnapshots) {
      if (!snapshot.exists) continue;
      const stock = snapshot.data()?.stock;
      stocks.set(
        snapshot.id,
        typeof stock === "number" && Number.isFinite(stock) ? stock : 0,
      );
    }

    const updates: string[] = [];
    await Promise.all(
      affected.map(async (doc) => {
        const data = doc.data() ?? {};
        const next = deriveMenuItemStatus(
          readRecipe(data.recipe),
          stocks,
          data.manualStatus,
        );
        if (data.status === next.status) return;
        await doc.ref.update({
          status: next.status,
          statusReason: "ingredients",
          statusUpdatedAt: FieldValue.serverTimestamp(),
        });
        updates.push(`${doc.id}→${next.status}`);
      }),
    );

    logger.info("Estado de menú recalculado por stock", {
      ingredientId: changedId,
      updates,
    });
  },
);

// =============================================================================
// updateOrderStatus: cambios de estado con control de rol y transiciones.
// =============================================================================

export const updateOrderStatus = onCall(async (request: CallableRequest) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }

  const role = request.auth.token.role;
  if (typeof role !== "string") {
    throw new HttpsError("permission-denied", "Tu cuenta no tiene un rol asignado.");
  }

  const payload = request.data as Partial<UpdateStatusPayload> | undefined;
  const orderId = payload?.orderId;
  const target = payload?.status;

  if (typeof orderId !== "string" || orderId.length === 0) {
    throw new HttpsError("invalid-argument", "Falta el identificador del pedido.");
  }
  if (typeof target !== "string") {
    throw new HttpsError("invalid-argument", "Falta el nuevo estado.");
  }

  const orderRef = db.collection("orders").doc(orderId);

  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(orderRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "El pedido no existe.");
    }

    const data = snapshot.data() ?? {};
    const current = data.status as OrderStatus;
    const orderType = data.type as "pickup" | "delivery" | "table" | undefined;
    const items = Array.isArray(data.items) ? data.items : [];

    if (!canTransition(role, current, target as OrderStatus, orderType)) {
      throw new HttpsError(
        "permission-denied",
        `No puedes pasar de "${current}" a "${target}" con el rol ${role}.`,
      );
    }

    const patch: Record<string, unknown> = {
      status: target,
      updatedAt: FieldValue.serverTimestamp(),
      lastChangedBy: request.auth?.uid ?? null,
    };

    if (target === "delivered" || target === "sent") {
      patch.paymentStatus = "paid";
    }
    if (target === "cancelled") {
      patch.paymentStatus = "refunded";
    }

    // Inventario: `pending` no descuenta. Al avanzar a cualquier estado superior
    // se descuenta una sola vez; al cancelar se repone.
    const deducted = data.inventoryDeducted === true;
    const shouldDeduct =
      !deducted &&
      (target === "confirmed" ||
        target === "preparing" ||
        target === "ready" ||
        target === "sent" ||
        target === "delivered");
    if (shouldDeduct) {
      const menuIds = [
        ...new Set(
          items
            .map((line: { menuItemId?: string }) => line.menuItemId)
            .filter((id): id is string => typeof id === "string"),
        ),
      ];
      const menuSnaps = await Promise.all(
        menuIds.map((id) => transaction.get(db.collection("menuItems").doc(id))),
      );
      const menuById = new Map(
        menuSnaps.map((snap) => [snap.id, snap.data() ?? {}]),
      );
      const consumption = new Map<string, number>();
      for (const line of items as Array<{
        menuItemId?: string;
        quantity?: number;
      }>) {
        const menu = menuById.get(line.menuItemId ?? "") ?? {};
        const recipe = Array.isArray(menu.recipe) ? menu.recipe : [];
        const lineQty = typeof line.quantity === "number" ? line.quantity : 0;
        for (const entry of recipe as Array<{
          ingredientId?: string;
          quantity?: number;
        }>) {
          const ingId = entry.ingredientId;
          if (typeof ingId !== "string") continue;
          const qty =
            (typeof entry.quantity === "number" ? entry.quantity : 0) * lineQty;
          consumption.set(ingId, (consumption.get(ingId) ?? 0) + qty);
        }
      }
      const ingIds = [...consumption.keys()];
      const ingSnaps = await Promise.all(
        ingIds.map((id) => transaction.get(db.collection("ingredients").doc(id))),
      );
      for (const snap of ingSnaps) {
        if (!snap.exists) continue;
        const data = snap.data() ?? {};
        const stock = typeof data.stock === "number" ? data.stock : 0;
        const qty = consumption.get(snap.id) ?? 0;
        const next = stock - qty;
        transaction.update(snap.ref, {
          stock: next < 0 ? 0 : next,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      patch.inventoryDeducted = true;
    }
    if (target === "cancelled" && deducted) {
      const menuIds = [
        ...new Set(
          items
            .map((line: { menuItemId?: string }) => line.menuItemId)
            .filter((id): id is string => typeof id === "string"),
        ),
      ];
      const menuSnaps = await Promise.all(
        menuIds.map((id) => transaction.get(db.collection("menuItems").doc(id))),
      );
      const menuById = new Map(
        menuSnaps.map((snap) => [snap.id, snap.data() ?? {}]),
      );
      const consumption = new Map<string, number>();
      for (const line of items as Array<{
        menuItemId?: string;
        quantity?: number;
      }>) {
        const menu = menuById.get(line.menuItemId ?? "") ?? {};
        const recipe = Array.isArray(menu.recipe) ? menu.recipe : [];
        const lineQty = typeof line.quantity === "number" ? line.quantity : 0;
        for (const entry of recipe as Array<{
          ingredientId?: string;
          quantity?: number;
        }>) {
          const ingId = entry.ingredientId;
          if (typeof ingId !== "string") continue;
          const qty =
            (typeof entry.quantity === "number" ? entry.quantity : 0) * lineQty;
          consumption.set(ingId, (consumption.get(ingId) ?? 0) + qty);
        }
      }
      const ingIds = [...consumption.keys()];
      const ingSnaps = await Promise.all(
        ingIds.map((id) => transaction.get(db.collection("ingredients").doc(id))),
      );
      for (const snap of ingSnaps) {
        if (!snap.exists) continue;
        const data = snap.data() ?? {};
        const stock = typeof data.stock === "number" ? data.stock : 0;
        const qty = consumption.get(snap.id) ?? 0;
        transaction.update(snap.ref, {
          stock: stock + qty,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      patch.inventoryDeducted = false;
    }

    transaction.update(orderRef, patch);

    // Liberar la mesa al cerrar el pedido.
    const tableNumber = data.tableNumber;
    if (
      typeof tableNumber === "number" &&
      (target === "delivered" || target === "sent" || target === "cancelled")
    ) {
      const tableQuery = await db
        .collection("tables")
        .where("number", "==", tableNumber)
        .limit(1)
        .get();
      const tableDoc = tableQuery.docs[0];
      if (tableDoc) {
        transaction.update(tableDoc.ref, {
          status: "libre",
          currentOrderId: null,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }

    return { orderId, status: target };
  });
});

// =============================================================================
// onOrderCreated: métricas diarias idempotentes.
// =============================================================================

export const onOrderCreated = onDocumentCreated(
  "orders/{orderId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const data = snapshot.data();
    const createdAt = data.createdAt;
    const date =
      createdAt instanceof Timestamp ? createdAt.toDate() : new Date();
    const key = dayKey(date);
    const statsRef = db.doc(`stats/daily-${key}`);
    const markerRef = db.doc(`_processedEvents/${event.id}`);

    const total = typeof data.total === "number" ? data.total : 0;
    const items = Array.isArray(data.items) ? data.items : [];
    const itemCount = items.reduce(
      (sum: number, item: { quantity?: number }) =>
        sum + (typeof item.quantity === "number" ? item.quantity : 0),
      0,
    );
    const type = typeof data.type === "string" ? data.type : "pickup";
    const paymentMethod =
      typeof data.paymentMethod === "string" ? data.paymentMethod : "cash";

    await db.runTransaction(async (transaction) => {
      const marker = await transaction.get(markerRef);
      if (marker.exists) return;

      const stats = await transaction.get(statsRef);
      const current = stats.data() ?? {};

      transaction.set(
        statsRef,
        {
          day: key,
          orders: Number(current.orders ?? 0) + 1,
          items: Number(current.items ?? 0) + itemCount,
          grossSales: Number(current.grossSales ?? 0) + total,
          byType: {
            ...(current.byType ?? {}),
            [type]: Number(current.byType?.[type] ?? 0) + 1,
          },
          byPaymentMethod: {
            ...(current.byPaymentMethod ?? {}),
            [paymentMethod]:
              Number(current.byPaymentMethod?.[paymentMethod] ?? 0) + total,
          },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      transaction.set(markerRef, {
        collection: "orders",
        documentId: event.params.orderId,
        processedAt: FieldValue.serverTimestamp(),
      });
    });

    logger.info("Métricas diarias actualizadas", {
      day: key,
      orderId: event.params.orderId,
    });
  },
);

// =============================================================================
// dailySalesReport: consolidado del día anterior en reports/{day}.
// =============================================================================

export const dailySalesReport = onSchedule(
  { schedule: "every day 03:00", timeZone: "America/Bogota" },
  async () => {
    const end = new Date();
    end.setUTCHours(0, 0, 0, 0);
    const start = new Date(end);
    start.setUTCDate(start.getUTCDate() - 1);

    const snapshot = await db
      .collection("orders")
      .where("paymentStatus", "==", "paid")
      .where("createdAt", ">=", Timestamp.fromDate(start))
      .where("createdAt", "<", Timestamp.fromDate(end))
      .get();

    let total = 0;
    let itemCount = 0;
    const byPaymentMethod: Record<string, number> = {};
    const byProduct: Record<string, { quantity: number; total: number }> = {};

    snapshot.forEach((doc) => {
      const data = doc.data();
      const orderTotal = typeof data.total === "number" ? data.total : 0;
      total += orderTotal;

      const method =
        typeof data.paymentMethod === "string" ? data.paymentMethod : "cash";
      byPaymentMethod[method] = (byPaymentMethod[method] ?? 0) + orderTotal;

      const items = Array.isArray(data.items) ? data.items : [];
      for (const item of items as Array<{
        name?: string;
        price?: number;
        quantity?: number;
      }>) {
        const quantity =
          typeof item.quantity === "number" ? item.quantity : 0;
        const price = typeof item.price === "number" ? item.price : 0;
        const name = String(item.name ?? "Producto");
        itemCount += quantity;
        const entry = byProduct[name] ?? { quantity: 0, total: 0 };
        byProduct[name] = {
          quantity: entry.quantity + quantity,
          total: entry.total + price * quantity,
        };
      }
    });

    const topProducts = Object.entries(byProduct)
      .sort((a, b) => b[1].quantity - a[1].quantity)
      .slice(0, 10)
      .map(([name, value]) => ({ name, ...value }));

    const key = dayKey(start);

    await db.doc(`reports/daily-${key}`).set(
      {
        day: key,
        orders: snapshot.size,
        items: itemCount,
        total,
        averageTicket: snapshot.size === 0 ? 0 : total / snapshot.size,
        byPaymentMethod,
        topProducts,
        generatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    logger.info("Reporte diario generado", { day: key, total });
  },
);
