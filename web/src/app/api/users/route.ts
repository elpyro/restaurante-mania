import { NextResponse } from "next/server";
import {
  AdminUnavailableError,
  verifyAdminIdToken,
} from "@/lib/firebase/admin";
import {
  deleteDocument,
  getDocument,
  isFirestoreConfigured,
  listDocuments,
  setDocument,
  tenantPath,
} from "@/lib/firebase/rest";
import { resolveTenantFromRequest } from "@/lib/tenants";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const NO_STORE = { "Cache-Control": "no-store" } as const;
const ROLES = new Set(["admin", "cashier", "waiter", "cook"]);
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

interface StoredUser {
  uid?: unknown;
  name?: unknown;
  email?: unknown;
  role?: unknown;
  status?: unknown;
  createdAt?: unknown;
}

interface ApiUser {
  id: string;
  uid: string;
  name: string;
  email: string;
  role: string;
  status: string;
  createdAt: string;
}

function errorResponse(message: string, status: number) {
  return NextResponse.json({ error: message }, { status, headers: NO_STORE });
}

function validId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const id = value.trim();
  if (!id || id.length > 120 || id.includes("/") || id.includes("..")) {
    return null;
  }
  return id;
}

/** La alta, edición y baja de cuentas es una operación solo de administrador. */
async function authorize(request: Request, tenantId: string) {
  const authorization = request.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(\S+)$/i.exec(authorization);
  if (!match) {
    return {
      error: errorResponse("Se requiere Authorization: Bearer <idToken>.", 401),
    };
  }
  try {
    const identity = await verifyAdminIdToken(match[1]!, tenantId);
    if (identity.role !== "admin") {
      return {
        error: errorResponse("Se requiere rol de administrador.", 403),
      };
    }
    return { identity };
  } catch (error) {
    if (error instanceof AdminUnavailableError) {
      return {
        error: errorResponse("La verificación de identidad no está disponible.", 503),
      };
    }
    return { error: errorResponse("Token inválido o expirado.", 401) };
  }
}

function asString(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

export async function GET(request: Request) {
  const tenantId = resolveTenantFromRequest(request);
  const auth = await authorize(request, tenantId);
  if (auth.error) return auth.error;
  if (!isFirestoreConfigured()) {
    return NextResponse.json({ tenantId, users: [], configured: false }, { headers: NO_STORE });
  }
  try {
    const users = await listDocuments<ApiUser>(
      tenantPath(tenantId, "users"),
      ({ id, data }) => ({
        id,
        uid: asString(data.uid) ?? id,
        name: asString(data.name) ?? "",
        email: asString(data.email) ?? "",
        role: asString(data.role) ?? "admin",
        status: asString(data.status) ?? "active",
        createdAt: asString(data.createdAt) ?? "",
      }),
      0,
    );
    users.sort((a, b) => {
      if (a.createdAt === b.createdAt) return a.id.localeCompare(b.id);
      return b.createdAt.localeCompare(a.createdAt);
    });
    return NextResponse.json({ tenantId, users, configured: true }, { headers: NO_STORE });
  } catch (error) {
    console.warn("[api/users] No se pudieron listar los usuarios:", error);
    return errorResponse("No se pudieron cargar los usuarios.", 503);
  }
}

/** Alta o actualización: `setDocument` crea el documento si no existe. */
export async function POST(request: Request) {
  const tenantId = resolveTenantFromRequest(request);
  const auth = await authorize(request, tenantId);
  if (auth.error) return auth.error;
  if (!isFirestoreConfigured()) {
    return errorResponse("Firestore no está configurado.", 503);
  }

  const body = await request.json().catch(() => null);
  if (!body || typeof body !== "object") {
    return errorResponse("Cuerpo inválido.", 400);
  }
  const input = body as Record<string, unknown>;
  const id = validId(input.id);
  const name = typeof input.name === "string" ? input.name.trim().slice(0, 120) : "";
  const email =
    typeof input.email === "string"
      ? input.email.trim().toLowerCase().slice(0, 160)
      : "";
  const role = typeof input.role === "string" ? input.role.trim().toLowerCase() : "";

  if (!id) return errorResponse("Identificador inválido.", 400);
  if (name.length < 2) return errorResponse("El nombre debe tener al menos 2 caracteres.", 400);
  if (!EMAIL_PATTERN.test(email)) return errorResponse("Correo inválido.", 400);
  if (!ROLES.has(role)) {
    return errorResponse("Rol inválido. Usa admin, cashier, waiter o cook.", 400);
  }

  try {
    const collection = tenantPath(tenantId, "users");
    const existing = await getDocument<StoredUser>(collection, id, 0);
    const createdAt = asString(existing?.createdAt) ?? new Date().toISOString();
    await setDocument(collection, id, {
      uid: id,
      name,
      email,
      role,
      status: "active",
      createdAt,
      updatedAt: new Date().toISOString(),
    });
    return NextResponse.json(
      { tenantId, user: { id, uid: id, name, email, role, status: "active", createdAt } },
      { headers: NO_STORE },
    );
  } catch (error) {
    console.warn("[api/users] No se pudo guardar el usuario:", error);
    return errorResponse("No se pudo guardar el usuario.", 503);
  }
}

export async function DELETE(request: Request) {
  const tenantId = resolveTenantFromRequest(request);
  const auth = await authorize(request, tenantId);
  if (auth.error) return auth.error;
  if (!isFirestoreConfigured()) {
    return errorResponse("Firestore no está configurado.", 503);
  }

  const id = validId(new URL(request.url).searchParams.get("id"));
  if (!id) return errorResponse("Identificador inválido.", 400);

  try {
    await deleteDocument(tenantPath(tenantId, "users"), id);
    return NextResponse.json({ tenantId, deleted: id }, { headers: NO_STORE });
  } catch (error) {
    console.warn("[api/users] No se pudo eliminar el usuario:", error);
    return errorResponse("No se pudo eliminar el usuario.", 503);
  }
}
