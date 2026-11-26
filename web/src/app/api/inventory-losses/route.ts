import { NextResponse } from "next/server";
import {
  AdminUnavailableError,
  verifyAdminIdToken,
} from "@/lib/firebase/admin";
import { getDemoState } from "@/lib/demo-store";
import {
  isFirestoreConfigured,
  listDocuments,
  setDocument,
  tenantPath,
} from "@/lib/firebase/rest";
import { resolveTenantFromRequest } from "@/lib/tenants";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const NO_STORE = { "Cache-Control": "no-store" } as const;
const STAFF_ROLES = new Set(["admin", "cook"]);
const REASONS = new Set(["caducado", "perdida", "dano", "otro"]);

interface LossLinePayload {
  ingredientId: string;
  name: string;
  quantity: number;
  unit: string;
}

function errorResponse(message: string, status: number) {
  return NextResponse.json({ error: message }, { status, headers: NO_STORE });
}

async function authorize(request: Request, tenantId: string) {
  const authorization = request.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(\S+)$/i.exec(authorization);
  if (!match) {
    return { error: errorResponse("Se requiere Authorization: Bearer <idToken>.", 401) };
  }

  let identity;
  try {
    identity = await verifyAdminIdToken(match[1]!, tenantId);
  } catch (error) {
    if (error instanceof AdminUnavailableError) {
      return {
        error: errorResponse("La verificación de identidad no está disponible.", 503),
      };
    }
    return { error: errorResponse("Token inválido o expirado.", 401) };
  }
  if (!STAFF_ROLES.has(String(identity.role))) {
    return {
      error: errorResponse("Se requiere rol de administrador o cocinero.", 403),
    };
  }
  return { identity };
}

export async function GET(request: Request) {
  const tenantId = resolveTenantFromRequest(request);
  const auth = await authorize(request, tenantId);
  if (auth.error) return auth.error;
  if (!isFirestoreConfigured()) {
    const losses = [...getDemoState(tenantId).losses].sort((a, b) =>
      String(b.createdAt ?? "").localeCompare(String(a.createdAt ?? "")),
    );
    return NextResponse.json({ tenantId, losses }, { headers: NO_STORE });
  }

  try {
    const losses = await listDocuments<Record<string, unknown>>(
      tenantPath(tenantId, "inventoryLosses"),
      (doc) => ({ id: doc.id, ...doc.data }),
      0,
    );
    losses.sort((a, b) =>
      String(b.createdAt ?? "").localeCompare(String(a.createdAt ?? "")),
    );
    return NextResponse.json({ tenantId, losses }, { headers: NO_STORE });
  } catch (error) {
    console.warn("[api/inventory-losses] No se pudieron listar las pérdidas:", error);
    return errorResponse("No se pudieron cargar las pérdidas.", 503);
  }
}

export async function POST(request: Request) {
  const tenantId = resolveTenantFromRequest(request);
  const auth = await authorize(request, tenantId);
  if (auth.error) return auth.error;

  const body = await request.json().catch(() => null);
  if (!body || typeof body !== "object") {
    return errorResponse("Cuerpo inválido.", 400);
  }
  const input = body as Record<string, unknown>;

  const id = typeof input.id === "string" ? input.id.trim() : "";
  if (!id || id.length > 120) return errorResponse("Identificador inválido.", 400);
  if (!REASONS.has(String(input.reason))) {
    return errorResponse("Motivo inválido.", 400);
  }
  if (!Array.isArray(input.lines) || input.lines.length === 0 || input.lines.length > 30) {
    return errorResponse("Agrega entre 1 y 30 ingredientes.", 400);
  }

  const lines: LossLinePayload[] = [];
  for (const raw of input.lines) {
    if (!raw || typeof raw !== "object") {
      return errorResponse("Línea de ingrediente inválida.", 400);
    }
    const line = raw as Record<string, unknown>;
    const ingredientId = typeof line.ingredientId === "string" ? line.ingredientId.trim() : "";
    const name = typeof line.name === "string" ? line.name.trim() : "";
    const quantity = Number(line.quantity);
    if (!ingredientId || !name || !Number.isFinite(quantity) || quantity <= 0) {
      return errorResponse("Cada ingrediente necesita nombre y cantidad mayor a cero.", 400);
    }
    lines.push({
      ingredientId,
      name: name.slice(0, 120),
      quantity,
      unit: typeof line.unit === "string" ? line.unit.slice(0, 12) : "",
    });
  }

  const createdAt =
    typeof input.createdAt === "string" && !Number.isNaN(Date.parse(input.createdAt))
      ? input.createdAt
      : new Date().toISOString();
  const notes = typeof input.notes === "string" ? input.notes.slice(0, 500) : "";
  const photoUrl =
    typeof input.photoUrl === "string" && input.photoUrl.trim()
      ? input.photoUrl.trim().slice(0, 2000)
      : null;
  const createdBy =
    input.createdBy && typeof input.createdBy === "object"
      ? (input.createdBy as Record<string, unknown>)
      : {};
  const auditLog = Array.isArray(input.auditLog)
    ? input.auditLog.filter(
        (entry): entry is Record<string, unknown> =>
          Boolean(entry) && typeof entry === "object",
      )
    : [];

  const document = {
    id,
    lines,
    reason: String(input.reason),
    notes,
    photoUrl,
    createdAt,
    updatedAt: new Date().toISOString(),
    createdBy: {
      uid: typeof createdBy.uid === "string" ? createdBy.uid : auth.identity.uid,
      name: typeof createdBy.name === "string" ? createdBy.name.slice(0, 120) : "",
      role: typeof createdBy.role === "string" ? createdBy.role : String(auth.identity.role),
    },
    receivedBy: { uid: auth.identity.uid, role: String(auth.identity.role) },
    auditLog: auditLog.map((entry) => ({
      action: String(entry.action ?? "").slice(0, 120),
      timestamp:
        typeof entry.timestamp === "string" &&
        !Number.isNaN(Date.parse(entry.timestamp))
          ? entry.timestamp
          : new Date().toISOString(),
      actorId: typeof entry.actorId === "string" ? entry.actorId : auth.identity.uid,
      actorName: typeof entry.actorName === "string" ? entry.actorName : "",
      actorRole: typeof entry.actorRole === "string" ? entry.actorRole : "",
    })),
  };

  try {
    if (!isFirestoreConfigured()) {
      const state = getDemoState(tenantId);
      state.losses = [
        document as unknown as Record<string, unknown>,
        ...state.losses.filter((loss) => loss.id !== id),
      ].slice(0, 2000);
    } else {
      await setDocument(tenantPath(tenantId, "inventoryLosses"), id, document);
    }
    return NextResponse.json({ ok: true, tenantId, id }, { headers: NO_STORE });
  } catch (error) {
    console.warn("[api/inventory-losses] No se pudo guardar la pérdida:", error);
    return errorResponse("No se pudo guardar la pérdida.", 503);
  }
}
