import { NextResponse } from "next/server";
import { syncMenuStatusesFromStock } from "@/lib/menu";
import { getOrderById, OrderValidationError, updateOrder } from "@/lib/orders";
import { resolveTenantFromRequest } from "@/lib/tenants";
import type { OrderStatus, PaymentStatus } from "@/lib/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const tenantId = resolveTenantFromRequest(request);
  const { id } = await params;
  const order = await getOrderById(id, tenantId);
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
  const tenantId = resolveTenantFromRequest(request);
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
  const patch: {
    status?: OrderStatus;
    paymentStatus?: PaymentStatus;
    inventoryDeducted?: boolean;
    paidAt?: string;
    paidBy?: string;
    paidByName?: string;
    lastChangedBy?: string;
    updatedBy?: string;
    updatedByName?: string;
  } = {};
  if (typeof raw.status === "string") patch.status = raw.status as OrderStatus;
  if (typeof raw.paymentStatus === "string") {
    patch.paymentStatus = raw.paymentStatus as PaymentStatus;
  }
  if (typeof raw.inventoryDeducted === "boolean") {
    patch.inventoryDeducted = raw.inventoryDeducted;
  }
  if (typeof raw.paidAt === "string") patch.paidAt = raw.paidAt;
  if (typeof raw.paidBy === "string") patch.paidBy = raw.paidBy;
  if (typeof raw.paidByName === "string") patch.paidByName = raw.paidByName;
  if (typeof raw.lastChangedBy === "string") {
    patch.lastChangedBy = raw.lastChangedBy;
  }
  if (typeof raw.updatedBy === "string") patch.updatedBy = raw.updatedBy;
  if (typeof raw.updatedByName === "string") {
    patch.updatedByName = raw.updatedByName;
  }
  if (
    !patch.status &&
    !patch.paymentStatus &&
    patch.inventoryDeducted === undefined &&
    !patch.paidAt &&
    !patch.paidBy &&
    !patch.paidByName &&
    !patch.lastChangedBy &&
    !patch.updatedBy &&
    !patch.updatedByName
  ) {
    return NextResponse.json(
      { error: "No hay cambios para aplicar." },
      { status: 400 },
    );
  }

  try {
    const order = await updateOrder(id, patch, tenantId);
    if (!order) {
      return NextResponse.json(
        { error: "Pedido no encontrado." },
        { status: 404 },
      );
    }
    let updatedMenuItems: string[] = [];
    try {
      updatedMenuItems = await syncMenuStatusesFromStock(tenantId);
    } catch (error) {
      console.error("[api/orders] No se pudo reconciliar el menú:", error);
    }
    return NextResponse.json(
      { order, updatedMenuItems },
      { headers: { "Cache-Control": "no-store" } },
    );
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
