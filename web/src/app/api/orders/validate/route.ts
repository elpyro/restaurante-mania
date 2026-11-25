import { NextResponse } from "next/server";
import { getMenu } from "@/lib/menu";
import { getRestaurantConfig } from "@/lib/restaurant-config";
import {
  getInsufficientItems,
  restaurantOrderPolicy,
  validateOrderInput,
  validateOrderItems,
  type OrderInputItem,
} from "@/lib/orders";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json(
      { ok: false, errors: ["El cuerpo del pedido debe ser JSON válido."] },
      { status: 400 },
    );
  }

  const payload = (body ?? {}) as Record<string, unknown>;
  const stockOnly = payload.stockOnly === true;
  let items: OrderInputItem[];

  if (stockOnly) {
    const validation = validateOrderItems(payload.items);
    if (!validation.ok) {
      return NextResponse.json(
        { ok: false, errors: validation.errors, insufficientItems: [] },
        { status: 400 },
      );
    }
    items = validation.items;
  } else {
    const { config } = await getRestaurantConfig();
    const validation = validateOrderInput(body, restaurantOrderPolicy(config));
    if (!validation.ok) {
      return NextResponse.json(
        { ok: false, errors: validation.errors, insufficientItems: [] },
        { status: 400 },
      );
    }
    items = validation.value.items;
  }

  const { items: menuItems } = await getMenu();
  const menuById = new Map(menuItems.map((item) => [item.id, item]));
  const unavailable = items
    .map((line) => {
      const item = menuById.get(line.menuItemId);
      if (!item) return `${line.menuItemId} no existe`;
      if (item.status === "unavailable") return `${item.name} no está disponible`;
      return null;
    })
    .filter((v): v is string => Boolean(v));

  if (unavailable.length > 0) {
    return NextResponse.json(
      { ok: false, errors: unavailable, insufficientItems: [] },
      { status: 400 },
    );
  }

  try {
    const insufficientItems = await getInsufficientItems(items, menuById);
    if (insufficientItems.length > 0) {
      return NextResponse.json(
        {
          ok: false,
          errors: ["Ingredientes insuficientes para algunos platos."],
          insufficientItems,
        },
        { status: 409 },
      );
    }
    return NextResponse.json({ ok: true, errors: [], insufficientItems: [] });
  } catch (error) {
    console.error("[api/orders/validate]", error);
    return NextResponse.json(
      { ok: false, errors: ["No pudimos verificar el stock. Intenta de nuevo."] },
      { status: 500 },
    );
  }
}
