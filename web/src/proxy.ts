import { NextResponse, type NextRequest } from "next/server";

import {
  DEFAULT_TENANT_ID,
  LANDING_HEADER,
  MENU_BASE_PATH,
  TENANT_COOKIE,
  TENANT_HEADER,
  TENANT_SLUG_PREFIX,
  normalizeTenantId,
  resolveTenantId,
  withTenant,
} from "@/lib/tenants";

const RESERVED_MENU_SEGMENTS = new Set([
  "menu",
  "cart",
  "checkout",
  "cuenta",
  "order",
]);
const STATIC_EXTENSION = /\.[a-zA-Z0-9]+$/;

/**
 * La portada neutra vive en `/`; las páginas de los restaurantes en `/menu...`.
 * `/inicio` es la ruta interna de la portada de un restaurante y no es pública.
 */
function isSpecialPath(pathname: string): boolean {
  if (pathname === "/api" || pathname.startsWith("/api/")) return true;
  if (pathname.startsWith("/_next/")) return true;
  return (
    pathname === "/favicon.ico" ||
    pathname === "/favicon.svg" ||
    pathname === "/sitemap.xml" ||
    pathname === "/robots.txt" ||
    pathname === "/llms.txt" ||
    pathname.startsWith("/manifest") ||
    STATIC_EXTENSION.test(pathname)
  );
}

function resolveRequestTenant(request: NextRequest): string {
  return resolveTenantId({
    path: request.nextUrl.pathname,
    query: request.nextUrl.searchParams.get("tenant"),
    header: request.headers.get(TENANT_HEADER),
    cookie: request.headers.get("cookie"),
    host:
      request.headers.get("x-forwarded-host") ??
      request.headers.get("host") ??
      request.nextUrl.host,
  });
}

function requestHeadersFor(
  request: NextRequest,
  tenantId: string,
  landing = false,
): Headers {
  const headers = new Headers(request.headers);
  headers.set(TENANT_HEADER, tenantId);
  if (landing) headers.set(LANDING_HEADER, "1");
  else headers.delete(LANDING_HEADER);
  return headers;
}

function withTenantCookie(
  response: NextResponse,
  tenantId: string,
): NextResponse {
  if (tenantId !== DEFAULT_TENANT_ID) {
    response.cookies.set(TENANT_COOKIE, tenantId, {
      path: "/",
      sameSite: "lax",
      maxAge: 60 * 60 * 24 * 30,
    });
  } else {
    response.cookies.delete(TENANT_COOKIE);
  }
  return response;
}

function redirectTo(
  request: NextRequest,
  path: string,
  tenantId: string,
): NextResponse {
  const url = request.nextUrl.clone();
  url.pathname = path;
  url.searchParams.delete("tenant");
  return withTenantCookie(NextResponse.redirect(url, 307), tenantId);
}

/** Convierte `/menu/restaurante-<id>/...` en la ruta interna del App Router. */
function internalMenuTarget(
  pathname: string,
): { path: string; tenantId: string } | null {
  if (
    pathname !== MENU_BASE_PATH &&
    !pathname.startsWith(`${MENU_BASE_PATH}/`)
  ) {
    return null;
  }
  const segments = pathname
    .slice(MENU_BASE_PATH.length)
    .split("/")
    .filter(Boolean);

  if (segments.length === 0 || RESERVED_MENU_SEGMENTS.has(segments[0]!)) {
    return {
      path: segments.length > 0 ? `/${segments.join("/")}` : "/inicio",
      tenantId: DEFAULT_TENANT_ID,
    };
  }

  const raw = segments[0]!.startsWith(TENANT_SLUG_PREFIX)
    ? segments[0]!.slice(TENANT_SLUG_PREFIX.length)
    : segments[0]!;
  const tenantId = normalizeTenantId(raw);
  if (!tenantId) return null;

  const rest = segments.slice(1);
  return {
    path: rest.length > 0 ? `/${rest.join("/")}` : "/inicio",
    tenantId,
  };
}

/**
 * Resuelve el tenant una sola vez por petición. La portada `/` es neutra;
 * `/menu...` se reescribe a las páginas internas conservando la URL visible.
 */
export function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;

  if (pathname === "/") {
    const legacyTenant = normalizeTenantId(
      request.nextUrl.searchParams.get("tenant"),
    );
    if (legacyTenant) {
      return redirectTo(request, withTenant("/", legacyTenant), legacyTenant);
    }
    const response = NextResponse.next({
      request: { headers: requestHeadersFor(request, DEFAULT_TENANT_ID, true) },
    });
    return withTenantCookie(response, DEFAULT_TENANT_ID);
  }

  if (isSpecialPath(pathname)) {
    const tenantId = resolveRequestTenant(request);
    return withTenantCookie(
      NextResponse.next({
        request: { headers: requestHeadersFor(request, tenantId) },
      }),
      tenantId,
    );
  }

  if (pathname === MENU_BASE_PATH) {
    const legacyTenant = normalizeTenantId(
      request.nextUrl.searchParams.get("tenant"),
    );
    if (legacyTenant && legacyTenant !== DEFAULT_TENANT_ID) {
      return redirectTo(request, withTenant("/", legacyTenant), legacyTenant);
    }
  }

  const target = internalMenuTarget(pathname);
  if (target) {
    const url = request.nextUrl.clone();
    url.pathname = target.path;
    url.searchParams.delete("tenant");
    const response = NextResponse.rewrite(url, {
      request: { headers: requestHeadersFor(request, target.tenantId) },
    });
    return withTenantCookie(response, target.tenantId);
  }

  // La ruta interna de la portada de un restaurante no se expone directamente.
  if (pathname === "/inicio" || pathname.startsWith("/inicio/")) {
    return redirectTo(request, MENU_BASE_PATH, DEFAULT_TENANT_ID);
  }

  const tenantId = resolveRequestTenant(request);
  return redirectTo(request, withTenant(pathname, tenantId), tenantId);
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
