import { NextResponse, type NextRequest } from "next/server";

import {
  DEFAULT_TENANT_ID,
  TENANT_COOKIE,
  TENANT_HEADER,
  resolveTenantId,
} from "@/lib/tenants";

/**
 * Resuelve el tenant una sola vez por petición y lo propaga a RSC, metadatos
 * y route handlers mediante un header de request y una cookie persistente.
 * Sin parámetros, el tenant es `mania` (comportamiento actual).
 */
export function proxy(request: NextRequest) {
  const tenantId = resolveTenantId({
    query: request.nextUrl.searchParams.get("tenant"),
    header: request.headers.get(TENANT_HEADER),
    cookie: request.headers.get("cookie"),
    host:
      request.headers.get("x-forwarded-host") ??
      request.headers.get("host") ??
      request.nextUrl.host,
  });

  const requestHeaders = new Headers(request.headers);
  requestHeaders.set(TENANT_HEADER, tenantId);

  const response = NextResponse.next({ request: { headers: requestHeaders } });
  if (tenantId !== DEFAULT_TENANT_ID) {
    response.cookies.set(TENANT_COOKIE, tenantId, {
      path: "/",
      sameSite: "lax",
      maxAge: 60 * 60 * 24 * 30,
    });
  } else {
    // Si el tenant resuelve a mania (default), limpiar cookie obsoleta para
    // que no arrastre al usuario a un tenant demo anterior (ej. verde).
    response.cookies.delete(TENANT_COOKIE);
  }
  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico).*)",
  ],
};
