import type { CartLine, CartTotals, MenuItem } from "./types";

export const TAX_RATE = 0;

function clampQty(quantity: number, maxServings?: number | null): number {
  const hardMax =
    typeof maxServings === "number" && Number.isFinite(maxServings)
      ? Math.max(0, Math.floor(maxServings))
      : 99;
  return Math.min(99, hardMax, Math.max(0, Math.floor(quantity)));
}

export function addLine(
  lines: CartLine[],
  item: Pick<MenuItem, "id" | "name" | "price" | "emoji" | "imageUrl"> & {
    maxServings?: number | null;
  },
  quantity = 1,
): CartLine[] {
  if (quantity <= 0) return lines;
  const existing = lines.find((line) => line.menuItemId === item.id);
  const maxServings = item.maxServings ?? existing?.maxServings ?? null;
  if (existing) {
    const nextQty = clampQty(existing.quantity + quantity, maxServings);
    if (nextQty === existing.quantity) return lines;
    return lines.map((line) =>
      line.menuItemId === item.id
        ? { ...line, quantity: nextQty, maxServings }
        : line,
    );
  }
  const nextQty = clampQty(quantity, maxServings);
  if (nextQty <= 0) return lines;
  return [
    ...lines,
    {
      menuItemId: item.id,
      name: item.name,
      price: item.price,
      quantity: nextQty,
      emoji: item.emoji,
      imageUrl: item.imageUrl,
      maxServings,
    },
  ];
}

export function updateQuantity(
  lines: CartLine[],
  menuItemId: string,
  quantity: number,
  maxServings?: number | null,
): CartLine[] {
  if (quantity <= 0) return removeLine(lines, menuItemId);
  return lines.map((line) => {
    if (line.menuItemId !== menuItemId) return line;
    const limit = maxServings ?? line.maxServings ?? null;
    return { ...line, quantity: clampQty(quantity, limit), maxServings: limit };
  });
}

export function removeLine(lines: CartLine[], menuItemId: string): CartLine[] {
  return lines.filter((line) => line.menuItemId !== menuItemId);
}

export interface StockAdjustment {
  menuItemId: string;
  available: number;
}

/** Recorta o quita las cantidades que no se pueden preparar con el stock actual. */
export function adjustLinesForStock(
  lines: CartLine[],
  adjustments: StockAdjustment[],
): CartLine[] {
  if (adjustments.length === 0) return lines;
  const byId = new Map(adjustments.map((entry) => [entry.menuItemId, entry.available]));
  let changed = false;
  const adjusted = lines.flatMap((line) => {
    if (!byId.has(line.menuItemId)) return [line];
    const available = Math.max(0, Math.floor(byId.get(line.menuItemId) ?? 0));
    if (available >= line.quantity) return [line];
    changed = true;
    return available > 0 ? [{ ...line, quantity: available }] : [];
  });
  return changed ? adjusted : lines;
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
