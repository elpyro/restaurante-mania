import { headers } from "next/headers";

import { DEFAULT_TENANT_ID, resolveTenantId } from "./tenants";

/**
 * Tenant de una petición RSC. El proxy (`src/proxy.ts`) inyecta
 * `x-tenant-id`, así que las páginas y los metadatos ven el mismo valor que
 * los route handlers.
 */
export async function getServerTenantId(): Promise<string> {
  try {
    const requestHeaders = await headers();
    return resolveTenantId({
      header: requestHeaders.get("x-tenant-id"),
      cookie: requestHeaders.get("cookie"),
      host:
        requestHeaders.get("x-forwarded-host") ??
        requestHeaders.get("host"),
    });
  } catch {
    // Fuera de una request (build, tests) el comportamiento es el histórico.
    return DEFAULT_TENANT_ID;
  }
}
