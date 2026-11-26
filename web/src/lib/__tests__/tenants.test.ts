import { describe, expect, it } from "vitest";

import {
  DEFAULT_TENANT_ID,
  isDemoTenant,
  normalizeTenantId,
  resolveTenantFromRequest,
  resolveTenantId,
  tenantFromHost,
  tenantStorageKey,
} from "../tenants";

function request(url: string, headers: Record<string, string> = {}): Request {
  return new Request(url, { headers });
}

describe("resolución de tenant", () => {
  it("usa manía por defecto cuando no hay ninguna señal", () => {
    expect(resolveTenantId()).toBe(DEFAULT_TENANT_ID);
    expect(isDemoTenant(DEFAULT_TENANT_ID)).toBe(false);
    expect(isDemoTenant("fuego")).toBe(true);
  });

  it("respeta la prioridad query > header > cookie > subdominio", () => {
    expect(
      resolveTenantId({
        query: "verde",
        header: "fuego",
        cookie: "rm_tenant_id=fuego",
        host: "fugo.localhost:3000",
      }),
    ).toBe("verde");
    expect(
      resolveTenantId({
        header: "fuego",
        cookie: "rm_tenant_id=verde",
        host: "verde.localhost:3000",
      }),
    ).toBe("fuego");
    expect(
      resolveTenantId({
        cookie: "otras=1; rm_tenant_id=verde",
        host: "fuego.localhost:3000",
      }),
    ).toBe("verde");
    expect(resolveTenantId({ host: "fuego.localhost:3000" })).toBe("fuego");
  });

  it("ignora tenants desconocidos y hosts sin subdominio", () => {
    expect(normalizeTenantId("FUEGO")).toBe("fuego");
    expect(normalizeTenantId("inexistente")).toBeNull();
    expect(resolveTenantId({ query: "inexistente", header: "fuego" })).toBe("fuego");
    expect(tenantFromHost("localhost:3000")).toBeNull();
    expect(tenantFromHost("127.0.0.1")).toBeNull();
    expect(tenantFromHost("proyecto-restaurante.com")).toBeNull();
  });

  it("lee el tenant de la request en headers, cookie y query", () => {
    expect(resolveTenantFromRequest(request("http://localhost/api/orders"))).toBe("mania");
    expect(
      resolveTenantFromRequest(
        request("http://localhost/api/orders?tenant=verde", {
          "x-tenant-id": "fuego",
        }),
      ),
    ).toBe("verde");
    expect(
      resolveTenantFromRequest(
        request("http://localhost/api/orders", {
          "x-tenant-id": "fuego",
          cookie: "rm_tenant_id=verde",
        }),
      ),
    ).toBe("fuego");
    expect(
      resolveTenantFromRequest(
        request("http://localhost/api/orders", {
          "x-forwarded-host": "verde.ejemplo.com",
        }),
      ),
    ).toBe("verde");
  });
});

describe("claves de almacenamiento por tenant", () => {
  it("conserva las claves legacy de manía", () => {
    expect(tenantStorageKey("mania", "rm_cart_v1")).toBe("rm_cart_v1");
    expect(tenantStorageKey("mania", "rm_orders_v1")).toBe("rm_orders_v1");
  });

  it("prefija las claves de los tenants demo", () => {
    expect(tenantStorageKey("fuego", "rm_cart_v1")).toBe("rm_fuego_cart_v1");
    expect(tenantStorageKey("verde", "rm_customer_profile_v1")).toBe(
      "rm_verde_customer_profile_v1",
    );
    expect(tenantStorageKey("fuego", "custom")).toBe("rm_fuego_custom");
  });
});
