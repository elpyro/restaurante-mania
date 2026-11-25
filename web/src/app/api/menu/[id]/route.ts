import { NextResponse } from "next/server";
import { setMenuItemStatus } from "@/lib/menu";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

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
  const payload = body as Record<string, unknown>;
  const status = payload.status;
  if (status !== "available" && status !== "unavailable") {
    return NextResponse.json(
      { error: "Estado inválido. Use 'available' o 'unavailable'." },
      { status: 400 },
    );
  }

  try {
    const reason =
      payload.reason === "ingredients" ? "ingredients" : "manual";
    const item = await setMenuItemStatus(
      id,
      status,
      typeof payload.manual === "boolean" ? payload.manual : undefined,
      reason,
    );
    if (!item) {
      return NextResponse.json(
        { error: "Plato no encontrado." },
        { status: 404 },
      );
    }
    return NextResponse.json(
      { item },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch (error) {
    console.error("[api/menu] No se pudo actualizar el estado:", error);
    return NextResponse.json(
      { error: "No se pudo actualizar el plato." },
      { status: 500 },
    );
  }
}
