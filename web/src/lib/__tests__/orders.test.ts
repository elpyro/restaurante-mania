import { afterEach, describe, expect, it, vi } from "vitest";

const rest = vi.hoisted(() => ({
  createDocument: vi.fn(),
  getDocument: vi.fn(),
  isFirestoreConfigured: vi.fn(() => false),
  listDocuments: vi.fn(),
  setDocument: vi.fn(),
}));

vi.mock("../firebase/rest", () => rest);

import { demoIngredientStocks } from "../seed";
import { ORDER_STATUS_LABELS } from "../types";
import { createOrder, updateOrder, validateOrderInput, validateOrderItems } from "../orders";

const base = {
  customerName: "Ana Pérez",
  customerPhone: "300 123 4567",
  deliveryAddress: "",
  type: "pickup",
  tableNumber: null,
  paymentMethod: "cash",
  notes: "",
  items: [{ menuItemId: "item-empanadas", quantity: 2 }],
};

describe("validación de pedidos", () => {
  it("acepta un pedido válido", () => {
    const result = validateOrderInput(base);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.customerName).toBe("Ana Pérez");
      expect(result.value.items).toHaveLength(1);
    }
  });

  it("rechaza nombre corto y teléfono inválido", () => {
    const result = validateOrderInput({ ...base, customerName: "A", customerPhone: "12" });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.errors.length).toBeGreaterThanOrEqual(2);
    }
  });

  it("exige mesa cuando el tipo es table", () => {
    const result = validateOrderInput({ ...base, type: "table", tableNumber: 0 });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.errors.join(" ")).toContain("mesa");
    }
  });

  it("acepta mesa válida", () => {
    const result = validateOrderInput({ ...base, type: "table", tableNumber: 4 });
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.value.tableNumber).toBe(4);
  });

  it("rechaza carrito vacío y cantidades fuera de rango", () => {
    const empty = validateOrderInput({ ...base, items: [] });
    expect(empty.ok).toBe(false);
    const invalid = validateOrderInput({
      ...base,
      items: [{ menuItemId: "item-empanadas", quantity: 99 }],
    });
    expect(invalid.ok).toBe(false);
  });

  it("rechaza métodos de pago y tipos desconocidos", () => {
    const result = validateOrderInput({
      ...base,
      type: "drone",
      paymentMethod: "bitcoin",
    });
    expect(result.ok).toBe(false);
  });

  it("rechaza cuerpos que no son objetos", () => {
    expect(validateOrderInput(null).ok).toBe(false);
    expect(validateOrderInput("pedido").ok).toBe(false);
  });

  it("valida el carrito para la comprobación temprana de stock", () => {
    const result = validateOrderItems([
      { menuItemId: "item-empanadas", quantity: 2 },
    ]);
    expect(result.ok).toBe(true);
    expect(validateOrderItems([]).ok).toBe(false);
    expect(
      validateOrderItems([{ menuItemId: "item-empanadas", quantity: 0 }]).ok,
    ).toBe(false);
  });
});

describe("estado final y descuento de inventario", () => {
  it("muestra el estado final como Enviado", () => {
    expect(ORDER_STATUS_LABELS.sent).toBe("Enviado");
    expect(ORDER_STATUS_LABELS.delivered).toBe("Enviado");
  });

  it("no descuenta ingredientes al crear el pedido en pending", async () => {
    const before = demoIngredientStocks["maiz-blanco"];
    const order = await createOrder({
      ...base,
      items: [{ menuItemId: "item-arepa-queso", quantity: 1 }],
    });

    expect(order.status).toBe("pending");
    expect(order.inventoryDeducted).toBe(false);
    expect(demoIngredientStocks["maiz-blanco"]).toBe(before);
  });

  it("descuenta una sola vez al avanzar a un estado superior", async () => {
    const before = demoIngredientStocks["maiz-blanco"];
    const order = await createOrder({
      ...base,
      items: [{ menuItemId: "item-arepa-queso", quantity: 1 }],
    });

    const confirmed = await updateOrder(order.id, { status: "confirmed" });
    expect(confirmed?.inventoryDeducted).toBe(true);
    expect(demoIngredientStocks["maiz-blanco"]).toBe(before - 100);

    const preparing = await updateOrder(order.id, { status: "preparing" });
    expect(preparing?.inventoryDeducted).toBe(true);
    expect(demoIngredientStocks["maiz-blanco"]).toBe(before - 100);
  });

  it("descuenta aunque la app envíe inventoryDeducted: true con el estado", async () => {
    const before = demoIngredientStocks["maiz-blanco"];
    const order = await createOrder({
      ...base,
      items: [{ menuItemId: "item-arepa-queso", quantity: 1 }],
    });

    const confirmed = await updateOrder(order.id, {
      status: "confirmed",
      inventoryDeducted: true,
    });

    expect(confirmed?.inventoryDeducted).toBe(true);
    expect(demoIngredientStocks["maiz-blanco"]).toBe(before - 100);

    const preparing = await updateOrder(order.id, {
      status: "preparing",
      inventoryDeducted: true,
    });
    expect(demoIngredientStocks["maiz-blanco"]).toBe(before - 100);
  });

  it("repone los ingredientes y limpia el flag al cancelar", async () => {
    const before = demoIngredientStocks["maiz-blanco"];
    const order = await createOrder({
      ...base,
      items: [{ menuItemId: "item-arepa-queso", quantity: 1 }],
    });
    await updateOrder(order.id, { status: "confirmed" });
    expect(demoIngredientStocks["maiz-blanco"]).toBe(before - 100);

    const cancelled = await updateOrder(order.id, { status: "cancelled" });

    expect(cancelled?.inventoryDeducted).toBe(false);
    expect(demoIngredientStocks["maiz-blanco"]).toBe(before);
  });

  it("persiste el flag de inventario al actualizar un pedido", async () => {
    const created = await createOrder({
      ...base,
      items: [{ menuItemId: "item-arepa-queso", quantity: 1 }],
    });
    const updated = await updateOrder(created.id, { inventoryDeducted: true });

    expect(updated?.inventoryDeducted).toBe(true);
  });

  it("guarda momento y autor del cobro sin perderlos en cambios posteriores", async () => {
    const created = await createOrder(base);
    const paid = await updateOrder(created.id, {
      paymentStatus: "paid",
      paidAt: "2026-11-24T13:45:00.000Z",
      paidBy: "u-cashier",
      paidByName: "Andrés Mejía",
    });

    expect(paid?.paidAt).toBe("2026-11-24T13:45:00.000Z");
    expect(paid?.paidBy).toBe("u-cashier");
    expect(paid?.paidByName).toBe("Andrés Mejía");

    const later = await updateOrder(created.id, { status: "delivered" });
    expect(later?.paidAt).toBe(paid?.paidAt);
    expect(later?.paidByName).toBe("Andrés Mejía");
  });

  it("llena la metadata cuando la web pública marca un pedido pagado", async () => {
    const created = await createOrder(base);
    const paid = await updateOrder(created.id, { paymentStatus: "paid" });

    expect(paid?.paidAt).toBeTruthy();
    expect(paid?.paidByName).toBe("Web pública");
  });
});

describe("reconciliación con Firestore al actualizar un pedido", () => {
  afterEach(() => {
    rest.isFirestoreConfigured.mockReturnValue(false);
    rest.getDocument.mockReset();
    rest.listDocuments.mockReset();
    rest.setDocument.mockReset();
  });

  it(
    "usa el flag remoto para reponer y lee el stock sin cache al cancelar",
    async () => {
      const before = demoIngredientStocks["maiz-blanco"];

      // El pedido se crea en modo demo: queda en la caché en memoria con
      // `inventoryDeducted: false`, aunque después otro proceso del servidor
      // haya descontado y persistido `true` en Firestore.
      const order = await createOrder({
        ...base,
        items: [{ menuItemId: "item-arepa-queso", quantity: 1 }],
      });

      rest.isFirestoreConfigured.mockReturnValue(true);
      rest.getDocument.mockImplementation(
        async (collection: string, id: string) =>
          collection === "orders" && id === order.id
            ? {
                ...order,
                id: order.id,
                status: "preparing",
                inventoryDeducted: true,
              }
            : null,
      );
      rest.listDocuments.mockImplementation(async (collection: string) => {
        if (collection === "ingredients") {
          // Stock ya descontado en Firestore (before - 100).
          return [{ id: "maiz-blanco", stock: before - 100 }];
        }
        // Catálogo vacío: `loadMenu()` cae a `seedMenu()` sin warning, con
        // las recetas disponibles para calcular la reposición.
        return [];
      });
      rest.setDocument.mockResolvedValue(undefined);

      const cancelled = await updateOrder(order.id, { status: "cancelled" });

      expect(cancelled?.inventoryDeducted).toBe(false);
      // Reposición exacta sobre el stock remoto descontado, no sobre el
      // valor cacheado de 60 s ni sobre la copia local del pedido.
      expect(rest.setDocument).toHaveBeenCalledWith(
        "ingredients",
        "maiz-blanco",
        expect.objectContaining({ stock: before }),
      );
      expect(rest.setDocument).toHaveBeenCalledWith(
        "orders",
        order.id,
        expect.objectContaining({ status: "cancelled", inventoryDeducted: false }),
      );

      // Ninguna lectura de insumos debe usar el `revalidate = 60` por defecto.
      const ingredientCalls = rest.listDocuments.mock.calls.filter(
        (call) => call[0] === "ingredients",
      );
      expect(ingredientCalls.length).toBeGreaterThan(0);
      expect(ingredientCalls.every((call) => call[2] === 0)).toBe(true);
    },
  );
});
