import { NextResponse } from "next/server";
import { createOrder, listOrders, OrderValidationError } from "@/lib/orders";
import { resolveTenantFromRequest } from "@/lib/tenants";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const tenantId = resolveTenantFromRequest(request);
  const orders = await listOrders(tenantId);
  return NextResponse.json(
    { tenantId, orders },
    { headers: { "Cache-Control": "no-store" } },
  );
}

export async function POST(request: Request) {
  const tenantId = resolveTenantFromRequest(request);
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
    const order = await createOrder(body, tenantId);
    return NextResponse.json({ order }, { status: 201 });
  } catch (error) {
    if (error instanceof OrderValidationError) {
      return NextResponse.json(
        { errors: error.errors, insufficientItems: error.insufficientItems },
        { status: 400 },
      );
    }
    console.error("[api/orders] Error creando pedido:", error);
    return NextResponse.json(
      { error: "No se pudo crear el pedido." },
      { status: 500 },
    );
  }
}
