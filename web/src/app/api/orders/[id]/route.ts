import { NextResponse } from "next/server";
import { getOrderById, OrderValidationError, updateOrder } from "@/lib/orders";
import type { OrderStatus, PaymentStatus } from "@/lib/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const order = await getOrderById(id);
  if (!order) {
    return NextResponse.json(
      { error: "Pedido no encontrado o no accesible." },
      { status: 404 },
    );
  }
  return NextResponse.json({ order }, { headers: { "Cache-Control": "no-store" } });
}

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "JSON inválido." }, { status: 400 });
  }
  if (!body || typeof body !== "object") {
    return NextResponse.json({ error: "Cuerpo inválido." }, { status: 400 });
  }
  const raw = body as Record<string, unknown>;
  const patch: { status?: OrderStatus; paymentStatus?: PaymentStatus } = {};
  if (typeof raw.status === "string") patch.status = raw.status as OrderStatus;
  if (typeof raw.paymentStatus === "string") {
    patch.paymentStatus = raw.paymentStatus as PaymentStatus;
  }
  if (!patch.status && !patch.paymentStatus) {
    return NextResponse.json(
      { error: "No hay cambios para aplicar." },
      { status: 400 },
    );
  }

  try {
    const order = await updateOrder(id, patch);
    if (!order) {
      return NextResponse.json(
        { error: "Pedido no encontrado." },
        { status: 404 },
      );
    }
    return NextResponse.json({ order }, { headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    if (error instanceof OrderValidationError) {
      return NextResponse.json({ errors: error.errors }, { status: 400 });
    }
    return NextResponse.json(
      { error: "No se pudo actualizar el pedido." },
      { status: 500 },
    );
  }
}
