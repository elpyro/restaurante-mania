"use client";

import {
  DEFAULT_TENANT_ID,
  isKnownTenant,
  normalizeTenantId,
  tenantStorageKey,
} from "./tenants";

export { tenantStorageKey };

type TenantWindow = Window & { __RM_TENANT_ID__?: string };

function cookieTenant(): string | null {
  if (typeof document === "undefined") return null;
  for (const part of document.cookie.split(";")) {
    const [name, raw] = part.trim().split("=");
    if (name === "rm_tenant_id") {
      try {
        return normalizeTenantId(decodeURIComponent(raw ?? ""));
      } catch {
        return null;
      }
    }
  }
  return null;
}

/** Tenant efectivo en el navegador, con el mismo orden de prioridad que el server. */
export function getClientTenantId(): string {
  if (typeof window === "undefined") return DEFAULT_TENANT_ID;
  const injected = normalizeTenantId((window as TenantWindow).__RM_TENANT_ID__);
  if (injected) return injected;
  const query = new URL(window.location.href).searchParams.get("tenant");
  const fromQuery = normalizeTenantId(query);
  if (fromQuery) return fromQuery;
  return cookieTenant() ?? DEFAULT_TENANT_ID;
}

export function isClientDemoTenant(): boolean {
  const id = getClientTenantId();
  return isKnownTenant(id) && id !== DEFAULT_TENANT_ID;
}

/** Headers para que los fetches del cliente lleguen al route handler correcto. */
export function tenantFetchHeaders(): Record<string, string> {
  return { "X-Tenant-Id": getClientTenantId() };
}
