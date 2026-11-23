import { NextResponse } from "next/server";
import { getMenu } from "@/lib/menu";
import { getInsufficientItems, validateOrderInput } from "@/lib/orders";

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

  const validation = validateOrderInput(body);
  if (!validation.ok) {
    return NextResponse.json(
      { ok: false, errors: validation.errors, insufficientItems: [] },
      { status: 400 },
    );
  }

  const { items: menuItems } = await getMenu();
  const menuById = new Map(menuItems.map((item) => [item.id, item]));
  const unavailable = validation.value.items
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
    const insufficientItems = await getInsufficientItems(
      validation.value.items,
      menuById,
    );
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
