import { describe, expect, it } from "vitest";
import { validateOrderInput } from "../orders";

const base = {
  customerName: "Ana Pérez",
  customerPhone: "300 123 4567",
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
});
