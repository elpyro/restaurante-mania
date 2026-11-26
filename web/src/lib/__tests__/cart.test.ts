import { describe, expect, it } from "vitest";
import {
  addLine,
  adjustLinesForStock,
  cartCount,
  cartTotals,
  isValidCartLine,
  removeLine,
  updateQuantity,
} from "../cart";

const empanada = {
  id: "item-empanadas",
  name: "Empanadas de carne",
  price: 14500,
  emoji: "🥟",
};

const ajiaco = {
  id: "item-ajiaco",
  name: "Ajiaco",
  price: 32900,
  emoji: "🍲",
};

describe("carrito", () => {
  it("agrega una línea nueva", () => {
    const lines = addLine([], empanada);
    expect(lines).toHaveLength(1);
    expect(lines[0].quantity).toBe(1);
    expect(lines[0].name).toBe("Empanadas de carne");
  });

  it("acumula cantidades del mismo producto", () => {
    const lines = addLine(addLine([], empanada), empanada, 2);
    expect(lines).toHaveLength(1);
    expect(lines[0].quantity).toBe(3);
  });

  it("no supera 99 unidades", () => {
    const lines = addLine([], empanada, 98);
    expect(addLine(lines, empanada, 10)[0].quantity).toBe(99);
  });

  it("actualiza y elimina líneas", () => {
    const lines = addLine(addLine([], empanada), ajiaco);
    const updated = updateQuantity(lines, empanada.id, 4);
    expect(updated.find((line) => line.menuItemId === empanada.id)?.quantity).toBe(4);
    expect(removeLine(updated, empanada.id)).toHaveLength(1);
  });

  it("cantidad cero elimina la línea", () => {
    const lines = addLine([], empanada);
    expect(updateQuantity(lines, empanada.id, 0)).toHaveLength(0);
  });

  it("calcula totales y unidades", () => {
    const lines = addLine(addLine([], empanada, 2), ajiaco);
    const totals = cartTotals(lines);
    expect(totals.subtotal).toBe(14500 * 2 + 32900);
    expect(totals.total).toBe(totals.subtotal + totals.tax);
    expect(totals.count).toBe(3);
    expect(cartCount(lines)).toBe(3);
  });

  it("recorta cantidades extras y quita las líneas sin stock", () => {
    const lines = addLine(addLine([], empanada, 4), ajiaco, 3);
    const adjusted = adjustLinesForStock(lines, [
      { menuItemId: empanada.id, available: 2 },
      { menuItemId: ajiaco.id, available: 0 },
    ]);
    expect(adjusted).toHaveLength(1);
    expect(adjusted[0].quantity).toBe(2);
  });

  it("no modifica el carrito si las cantidades ya son válidas", () => {
    const lines = addLine([], empanada, 1);
    expect(
      adjustLinesForStock(lines, [{ menuItemId: empanada.id, available: 3 }]),
    ).toBe(lines);
  });

  it("valida líneas corruptas de localStorage", () => {
    expect(isValidCartLine({ menuItemId: "x", name: "X", price: 1, quantity: 2 })).toBe(true);
    expect(isValidCartLine({ menuItemId: "", name: "X", price: 1, quantity: 2 })).toBe(false);
    expect(isValidCartLine({ menuItemId: "x", name: "X", price: 1, quantity: 0 })).toBe(false);
    expect(isValidCartLine(null)).toBe(false);
  });
});
