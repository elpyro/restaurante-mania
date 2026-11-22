"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import {
  addLine,
  cartCount,
  cartTotals,
  isValidCartLine,
  removeLine,
  updateQuantity,
} from "@/lib/cart";
import type { CartLine, CartTotals, MenuItem } from "@/lib/types";

const STORAGE_KEY = "rm_cart_v1";

interface CartContextValue {
  lines: CartLine[];
  count: number;
  totals: CartTotals;
  ready: boolean;
  add: (
    item: Pick<MenuItem, "id" | "name" | "price" | "emoji">,
    quantity?: number,
  ) => void;
  setQuantity: (menuItemId: string, quantity: number) => void;
  remove: (menuItemId: string) => void;
  clear: () => void;
}

const CartContext = createContext<CartContextValue | null>(null);

function readStorage(): CartLine[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed: unknown = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.filter(isValidCartLine) : [];
  } catch {
    return [];
  }
}

export function CartProvider({ children }: { children: ReactNode }) {
  const [lines, setLines] = useState<CartLine[]>([]);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    setLines(readStorage());
    setReady(true);
  }, []);

  useEffect(() => {
    if (!ready) return;
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(lines));
    } catch {
      /* almacenamiento lleno o bloqueado */
    }
  }, [lines, ready]);

  const add = useCallback(
    (item: Pick<MenuItem, "id" | "name" | "price" | "emoji">, quantity = 1) => {
      setLines((current) => addLine(current, item, quantity));
    },
    [],
  );

  const setQuantity = useCallback((menuItemId: string, quantity: number) => {
    setLines((current) => updateQuantity(current, menuItemId, quantity));
  }, []);

  const remove = useCallback((menuItemId: string) => {
    setLines((current) => removeLine(current, menuItemId));
  }, []);

  const clear = useCallback(() => setLines([]), []);

  const totals = useMemo(() => cartTotals(lines), [lines]);

  const value = useMemo<CartContextValue>(
    () => ({
      lines,
      count: cartCount(lines),
      totals,
      ready,
      add,
      setQuantity,
      remove,
      clear,
    }),
    [lines, totals, ready, add, setQuantity, remove, clear],
  );

  return <CartContext.Provider value={value}>{children}</CartContext.Provider>;
}

export function useCart(): CartContextValue {
  const context = useContext(CartContext);
  if (!context) throw new Error("useCart debe usarse dentro de CartProvider");
  return context;
}
