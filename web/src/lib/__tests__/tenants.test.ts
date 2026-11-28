import { describe, expect, it } from "vitest";

import {
  DEFAULT_TENANT_ID,
  isDemoTenant,
  normalizeTenantId,
  registerTenantDefinition,
  resolveTenantFromRequest,
  resolveTenantId,
  tenantDefinition,
  tenantFromHost,
  tenantFromPath,
  tenantStorageKey,
  withTenant,
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

  it("respeta la prioridad query > header > cookie > subdominio sin ruta", () => {
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

  it("acepta IDs dinámicos con el formato seguro y rechaza los inválidos", () => {
    expect(normalizeTenantId("FUEGO")).toBe("fuego");
    expect(normalizeTenantId("casa-nueva")).toBe("casa-nueva");
    expect(normalizeTenantId("Mi Tienda!")).toBeNull();
    expect(normalizeTenantId("-fuego")).toBeNull();
    expect(normalizeTenantId("")).toBeNull();
    expect(resolveTenantId({ query: "casa-nueva", header: "fuego" })).toBe(
      "casa-nueva",
    );
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

describe("rutas públicas por restaurante", () => {
  it("construye /menu para Manía y /menu/restaurante-<id> para los demás", () => {
    expect(withTenant("/", "mania")).toBe("/menu");
    expect(withTenant("/menu", "mania")).toBe("/menu/menu");
    expect(withTenant("/cart", "taquitos-mexicanos")).toBe(
      "/menu/restaurante-taquitos-mexicanos/cart",
    );
    expect(withTenant("/", "fuego")).toBe("/menu/restaurante-fuego");
    expect(withTenant("/menu/arepa", "quesillo")).toBe(
      "/menu/restaurante-quesillo/menu/arepa",
    );
    expect(withTenant("/menu#postres", "quesillo")).toBe(
      "/menu/restaurante-quesillo/menu#postres",
    );
    expect(withTenant("/order/123", "quesillo")).toBe(
      "/menu/restaurante-quesillo/order/123",
    );
  });

  it("resuelve el tenant desde la ruta pública", () => {
    expect(tenantFromPath("/menu")).toBe("mania");
    expect(tenantFromPath("/menu/menu")).toBe("mania");
    expect(tenantFromPath("/menu/cart")).toBe("mania");
    expect(tenantFromPath("/menu/restaurante-taquitos-mexicanos")).toBe(
      "taquitos-mexicanos",
    );
    expect(tenantFromPath("/menu/restaurante-fuego/menu")).toBe("fuego");
    expect(tenantFromPath("/api/menu")).toBeNull();
  });

  it("da prioridad a la ruta sobre query, header y cookie", () => {
    expect(
      resolveTenantId({
        path: "/menu/restaurante-fuego/menu",
        query: "verde",
        header: "fuego",
        cookie: "rm_tenant_id=verde",
      }),
    ).toBe("fuego");
    expect(
      resolveTenantFromRequest(
        request("http://localhost/menu/restaurante-fuego/menu"),
      ),
    ).toBe("fuego");
  });
});

describe("definiciones dinámicas", () => {
  it("deriva una definición estable de un ID nuevo", () => {
    const definition = tenantDefinition("casa-nueva");
    expect(definition.id).toBe("casa-nueva");
    expect(definition.preset).toBe("custom");
    expect(definition.orderPrefix).toBe("CAS");
  });

  it("usa el nombre registrado cuando está disponible", () => {
    registerTenantDefinition({
      id: "otra-casa",
      label: "Otra Casa",
      orderPrefix: "OC",
    });
    expect(tenantDefinition("otra-casa").label).toBe("Otra Casa");
    expect(tenantDefinition("otra-casa").orderPrefix).toBe("OC");
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
