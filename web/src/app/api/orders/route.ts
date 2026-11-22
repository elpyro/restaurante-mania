import { NextResponse } from "next/server";
import { createOrder, OrderValidationError } from "@/lib/orders";

export const runtime = "nodejs";

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json(
      { errors: ["El cuerpo del pedido debe ser JSON válido."] },
      { status: 400 },
    );
  }

  try {
    const order = await createOrder(body);
    return NextResponse.json({ order }, { status: 201 });
  } catch (error) {
    if (error instanceof OrderValidationError) {
      return NextResponse.json({ errors: error.errors }, { status: 400 });
    }
    console.error("[api/orders] Error creando pedido:", error);
    return NextResponse.json(
      { errors: ["No pudimos crear el pedido. Intenta de nuevo."] },
      { status: 500 },
    );
  }
}
