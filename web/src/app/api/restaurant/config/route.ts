import { NextResponse } from "next/server";
import {
  AdminUnavailableError,
  verifyAdminIdToken,
} from "@/lib/firebase/admin";
import { setDocument } from "@/lib/firebase/rest";
import {
  ConfigValidationError,
  getRestaurantConfig,
  sanitizeConfigPatch,
  toPublicRestaurantConfig,
} from "@/lib/restaurant-config";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const NO_STORE = { "Cache-Control": "no-store" } as const;

function errorResponse(message: string, status: number) {
  return NextResponse.json({ error: message }, { status, headers: NO_STORE });
}

export async function GET() {
  const snapshot = await getRestaurantConfig();
  return NextResponse.json(
    {
      configured: snapshot.configured,
      config: toPublicRestaurantConfig(snapshot.config),
      source: snapshot.source,
    },
    { headers: NO_STORE },
  );
}

export async function PATCH(request: Request) {
  const authorization = request.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(\S+)$/i.exec(authorization);
  if (!match) {
    return errorResponse("Se requiere Authorization: Bearer <idToken>.", 401);
  }

  let role: unknown;
  try {
    const identity = await verifyAdminIdToken(match[1]!);
    role = identity.role;
  } catch (error) {
    if (error instanceof AdminUnavailableError) {
      return errorResponse("La verificación de identidad no está disponible.", 503);
    }
    return errorResponse("Token inválido o expirado.", 401);
  }
  if (role !== "admin") {
    return errorResponse("Se requiere rol de administrador.", 403);
  }

  try {
    const body = await request.json().catch(() => null);
    const patch = sanitizeConfigPatch(body);
    const { config: current } = await getRestaurantConfig();
    // Los mapas anidados se fusionan: enviar solo el preset no debe borrar el
    // banner/logo, y enviar un pago no debe borrar las etiquetas respectivas.
    const nextConfig = {
      ...current,
      ...patch,
      appearance: {
        ...current.appearance,
        ...patch.appearance,
        socialLinks: {
          ...current.appearance.socialLinks,
          ...patch.appearance?.socialLinks,
        },
      },
      deliveryOptions: {
        ...current.deliveryOptions,
        ...patch.deliveryOptions,
      },
      paymentMethodLabels: {
        ...current.paymentMethodLabels,
        ...patch.paymentMethodLabels,
      },
      aiSearch: {
        ...current.aiSearch,
        ...patch.aiSearch,
      },
      updatedAt: new Date().toISOString(),
    };

    await setDocument("restaurant", "config", nextConfig);

    return NextResponse.json(
      {
        configured: true,
        config: toPublicRestaurantConfig(nextConfig),
        source: "firestore",
      },
      { headers: NO_STORE },
    );
  } catch (error) {
    if (error instanceof ConfigValidationError) {
      return errorResponse(error.message, 400);
    }
    console.warn("[api/restaurant/config] No se pudo guardar la configuración:", error);
    return errorResponse("No se pudo guardar la configuración.", 503);
  }
}
