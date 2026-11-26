import { NextResponse } from "next/server";
import {
  deleteDocument,
  getDocument,
  isFirestoreConfigured,
  setDocument,
  tenantPath,
} from "@/lib/firebase/rest";
import { syncMenuStatusesFromStock } from "@/lib/menu";
import { resolveTenantFromRequest } from "@/lib/tenants";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function numberField(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    return null;
  }
  return value;
}

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const tenantId = resolveTenantFromRequest(request);
  const { id } = await params;
  const documentId = id.trim();
  if (!documentId) {
    return NextResponse.json({ error: "ID inválido." }, { status: 400 });
  }
  if (!isFirestoreConfigured()) {
    return NextResponse.json(
      { ok: false, error: "Firestore no configurado" },
      { status: 503 },
    );
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "JSON inválido." }, { status: 400 });
  }
  const input = (body ?? {}) as Record<string, unknown>;
  const stock = numberField(input.stock);
  const minStock =
    input.minStock === undefined ? null : numberField(input.minStock);
  if (stock === null || (input.minStock !== undefined && minStock === null)) {
    return NextResponse.json(
      { error: "stock y minStock deben ser números no negativos." },
      { status: 400 },
    );
  }

  try {
    const existing = await getDocument<Record<string, unknown>>(
      tenantPath(tenantId, "ingredients"),
      documentId,
      0,
    );
    const now = new Date().toISOString();
    if (!existing) {
      // El ID de la URL es el ID canónico del insumo. `createDocument`
      // generaría un ID aleatorio y las recetas dejarían de encontrarlo.
      await setDocument(tenantPath(tenantId, "ingredients"), documentId, {
        name: typeof input.name === "string" ? input.name : documentId,
        unit: typeof input.unit === "string" ? input.unit : "g",
        stock,
        minStock: minStock ?? 0,
        updatedAt: now,
      });
    } else {
      const patch: Record<string, unknown> = { stock, updatedAt: now };
      if (minStock !== null) patch.minStock = minStock;
      await setDocument(
        tenantPath(tenantId, "ingredients"),
        documentId,
        patch,
      );
    }
    let updatedMenuItems: string[] = [];
    try {
      updatedMenuItems = await syncMenuStatusesFromStock(tenantId);
    } catch (error) {
      console.error("[api/ingredients] No se pudo reconciliar el menú:", error);
    }
    return NextResponse.json({
      ok: true,
      tenantId,
      id: documentId,
      stock,
      updatedMenuItems,
    });
  } catch (error) {
    console.error("[api/ingredients] PATCH", error);
    return NextResponse.json(
      { error: "No se pudo guardar el insumo." },
      { status: 500 },
    );
  }
}

export async function DELETE(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const tenantId = resolveTenantFromRequest(request);
  const { id } = await params;
  const documentId = id.trim();
  if (!documentId) {
    return NextResponse.json({ error: "ID inválido." }, { status: 400 });
  }
  if (!isFirestoreConfigured()) {
    return NextResponse.json(
      { ok: false, error: "Firestore no configurado" },
      { status: 503 },
    );
  }
  try {
    await deleteDocument(tenantPath(tenantId, "ingredients"), documentId);
    let updatedMenuItems: string[] = [];
    try {
      updatedMenuItems = await syncMenuStatusesFromStock(tenantId);
    } catch (error) {
      console.error("[api/ingredients] No se pudo reconciliar el menú:", error);
    }
    return NextResponse.json({
      ok: true,
      tenantId,
      id: documentId,
      updatedMenuItems,
    });
  } catch (error) {
    console.error("[api/ingredients] DELETE", error);
    return NextResponse.json(
      { error: "No se pudo borrar el insumo." },
      { status: 500 },
    );
  }
}
