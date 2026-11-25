import { NextResponse } from "next/server";
import {
  createDocument,
  deleteDocument,
  getDocument,
  isFirestoreConfigured,
  setDocument,
} from "@/lib/firebase/rest";
import { syncMenuStatusesFromStock } from "@/lib/menu";

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
      "ingredients",
      documentId,
      0,
    );
    const now = new Date().toISOString();
    if (!existing) {
      await createDocument("ingredients", {
        id: documentId,
        name: typeof input.name === "string" ? input.name : documentId,
        unit: typeof input.unit === "string" ? input.unit : "g",
        stock,
        minStock: minStock ?? 0,
        updatedAt: now,
      });
    } else {
      const patch: Record<string, unknown> = { stock, updatedAt: now };
      if (minStock !== null) patch.minStock = minStock;
      await setDocument("ingredients", documentId, patch);
    }
    let updatedMenuItems: string[] = [];
    try {
      updatedMenuItems = await syncMenuStatusesFromStock();
    } catch (error) {
      console.error("[api/ingredients] No se pudo reconciliar el menú:", error);
    }
    return NextResponse.json({
      ok: true,
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
  _request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
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
    await deleteDocument("ingredients", documentId);
    let updatedMenuItems: string[] = [];
    try {
      updatedMenuItems = await syncMenuStatusesFromStock();
    } catch (error) {
      console.error("[api/ingredients] No se pudo reconciliar el menú:", error);
    }
    return NextResponse.json({ ok: true, id: documentId, updatedMenuItems });
  } catch (error) {
    console.error("[api/ingredients] DELETE", error);
    return NextResponse.json(
      { error: "No se pudo borrar el insumo." },
      { status: 500 },
    );
  }
}
