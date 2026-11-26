import { NextResponse } from "next/server";
import {
  AdminUnavailableError,
  verifyAdminIdToken,
} from "@/lib/firebase/admin";
import { setMenuItemFeatured, setMenuItemStatus } from "@/lib/menu";
import { resolveTenantFromRequest } from "@/lib/tenants";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const NO_STORE = { "Cache-Control": "no-store" } as const;

/** La disponibilidad y los favoritos los publica solo la app administrativa. */
async function requireAdmin(
  request: Request,
  tenantId: string,
): Promise<NextResponse | null> {
  const authorization = request.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(\S+)$/i.exec(authorization);
  if (!match) {
    return NextResponse.json(
      { error: "Se requiere Authorization: Bearer <idToken>." },
      { status: 401, headers: NO_STORE },
    );
  }
  try {
    const identity = await verifyAdminIdToken(match[1]!, tenantId);
    if (identity.role !== "admin") {
      return NextResponse.json(
        { error: "Se requiere rol de administrador." },
        { status: 403, headers: NO_STORE },
      );
    }
  } catch (error) {
    if (error instanceof AdminUnavailableError) {
      return NextResponse.json(
        { error: "La verificación de identidad no está disponible." },
        { status: 503, headers: NO_STORE },
      );
    }
    return NextResponse.json(
      { error: "Token inválido o expirado." },
      { status: 401, headers: NO_STORE },
    );
  }
  return null;
}

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const tenantId = resolveTenantFromRequest(request);
  const unauthorized = await requireAdmin(request, tenantId);
  if (unauthorized) return unauthorized;
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
  const hasStatus = "status" in payload;
  const hasFeatured = "featured" in payload;
  const status = payload.status;
  if (
    hasStatus &&
    status !== "available" &&
    status !== "unavailable"
  ) {
    return NextResponse.json(
      { error: "Estado inválido. Use 'available' o 'unavailable'." },
      { status: 400 },
    );
  }
  if (hasFeatured && typeof payload.featured !== "boolean") {
    return NextResponse.json(
      { error: "featured debe ser verdadero o falso." },
      { status: 400 },
    );
  }
  if (!hasStatus && !hasFeatured) {
    return NextResponse.json(
      { error: "Envía status o featured." },
      { status: 400 },
    );
  }

  try {
    let item: Record<string, unknown> | null = null;
    if (hasStatus) {
      const reason =
        payload.reason === "ingredients" ? "ingredients" : "manual";
      item = await setMenuItemStatus(
        id,
        status as "available" | "unavailable",
        typeof payload.manual === "boolean" ? payload.manual : undefined,
        reason,
        tenantId,
      );
    }
    if (hasFeatured && typeof payload.featured === "boolean") {
      const featured = await setMenuItemFeatured(id, payload.featured, tenantId);
      if (!featured) return NextResponse.json({ error: "Plato no encontrado." }, { status: 404 });
      item = { ...(item ?? { id }), ...featured };
    }
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
    console.error("[api/menu] No se pudo actualizar el plato:", error);
    return NextResponse.json(
      { error: "No se pudo actualizar el plato." },
      { status: 500 },
    );
  }
}
