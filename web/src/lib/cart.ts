import type { CartLine, CartTotals, MenuItem } from "./types";

export const TAX_RATE = 0;

export function addLine(
  lines: CartLine[],
  item: Pick<MenuItem, "id" | "name" | "price" | "emoji">,
  quantity = 1,
): CartLine[] {
  if (quantity <= 0) return lines;
  const existing = lines.find((line) => line.menuItemId === item.id);
  if (existing) {
    return lines.map((line) =>
      line.menuItemId === item.id
        ? { ...line, quantity: Math.min(99, line.quantity + quantity) }
        : line,
    );
  }
  return [
    ...lines,
    {
      menuItemId: item.id,
      name: item.name,
      price: item.price,
      quantity: Math.min(99, quantity),
      emoji: item.emoji,
    },
  ];
}

export function updateQuantity(
  lines: CartLine[],
  menuItemId: string,
  quantity: number,
): CartLine[] {
  if (quantity <= 0) return removeLine(lines, menuItemId);
  return lines.map((line) =>
    line.menuItemId === menuItemId
      ? { ...line, quantity: Math.min(99, Math.floor(quantity)) }
      : line,
  );
}

export function removeLine(lines: CartLine[], menuItemId: string): CartLine[] {
  return lines.filter((line) => line.menuItemId !== menuItemId);
}

export function cartCount(lines: CartLine[]): number {
  return lines.reduce((total, line) => total + line.quantity, 0);
}

export function cartTotals(lines: CartLine[], taxRate = TAX_RATE): CartTotals {
  const subtotal = lines.reduce(
    (total, line) => total + line.price * line.quantity,
    0,
  );
  const tax = Math.round(subtotal * taxRate);
  return {
    subtotal,
    tax,
    total: subtotal + tax,
    count: cartCount(lines),
  };
}

export function isValidCartLine(value: unknown): value is CartLine {
  if (!value || typeof value !== "object") return false;
  const line = value as Record<string, unknown>;
  return (
    typeof line.menuItemId === "string" &&
    line.menuItemId.length > 0 &&
    typeof line.name === "string" &&
    typeof line.price === "number" &&
    Number.isFinite(line.price) &&
    line.price >= 0 &&
    typeof line.quantity === "number" &&
    Number.isInteger(line.quantity) &&
    line.quantity > 0 &&
    line.quantity <= 99
  );
}
