import { NextResponse } from "next/server";
import { getOrderById } from "@/lib/orders";

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
  return NextResponse.json({ order });
}
