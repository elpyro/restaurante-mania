/**
 * Registro de tenants del sistema.
 *
 * `mania` es el tenant por defecto. Los tres tenants operativos (mania, fuego
 * y verde) viven en Firestore bajo `tenants/{tenantId}` y comparten el mismo
 * proyecto. El estado local en memoria/disco solo se usa como fallback cuando
 * Firestore no está configurado (tests y desarrollo sin credenciales).
 */

export const DEFAULT_TENANT_ID = "mania";
export const TENANT_HEADER = "x-tenant-id";
export const TENANT_COOKIE = "rm_tenant_id";

export interface TenantDefinition {
  id: string;
  label: string;
  description: string;
  preset: "mania" | "fuego" | "verde" | "noche" | "custom";
  city: string;
  address: string;
  phone: string;
  whatsapp: string;
  hours: string;
  currency: string;
  /** Prefijo de los códigos de pedido, para identificar el dueño. */
  orderPrefix: string;
}

export const TENANTS: Record<string, TenantDefinition> = {
  mania: {
    id: "mania",
    label: "Restaurante Manía",
    description: "Datos reales del restaurante. Sin cambios en esta fase.",
    preset: "mania",
    city: "",
    address: "",
    phone: "",
    whatsapp: "",
    hours: "",
    currency: "COP",
    orderPrefix: "RM",
  },
  fuego: {
    id: "fuego",
    label: "Fuego · Parrilla & Brasa",
    description: "Instancia demo con carta de brasa y stock propio.",
    preset: "fuego",
    city: "Medellín",
    address: "Calle 30 # 20-45, Medellín",
    phone: "301 222 3344",
    whatsapp: "573012223344",
    hours: "Mar–Dom 12:00–22:00",
    currency: "COP",
    orderPrefix: "FUE",
  },
  verde: {
    id: "verde",
    label: "Verde · Cocina fresca",
    description: "Instancia demo con carta fresca y horarios propios.",
    preset: "verde",
    city: "Bogotá",
    address: "Cra. 7 # 71-21, Bogotá",
    phone: "310 555 7788",
    whatsapp: "573105557788",
    hours: "Lun–Sáb 11:30–20:30",
    currency: "COP",
    orderPrefix: "VRD",
  },
};

export const TENANT_IDS = Object.keys(TENANTS);

export function normalizeTenantId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const candidate = value.trim().toLowerCase();
  if (!candidate) return null;
  return Object.hasOwn(TENANTS, candidate) ? candidate : null;
}

export function isKnownTenant(tenantId: string): boolean {
  return Object.hasOwn(TENANTS, tenantId);
}

/** Compatibilidad: identifica tenants distintos del predeterminado. */
export function isDemoTenant(tenantId: string): boolean {
  return tenantId !== DEFAULT_TENANT_ID;
}

export function tenantDefinition(tenantId: string): TenantDefinition {
  return TENANTS[tenantId] ?? TENANTS[DEFAULT_TENANT_ID]!;
}

export function tenantLabel(tenantId: string): string {
  return tenantDefinition(tenantId).label;
}

/** `fuego.localhost:3000` → `fuego`. El host raíz no especifica tenant. */
export function tenantFromHost(host: string | null | undefined): string | null {
  if (!host) return null;
  const hostname = host.split(":")[0]?.toLowerCase() ?? "";
  if (!hostname || hostname === "localhost" || hostname === "127.0.0.1") {
    return null;
  }
  const parts = hostname.split(".");
  if (parts.length < 2) return null;
  // Solo subdominio de primer nivel: fuego.ejemplo.com, fuego.localhost.
  return normalizeTenantId(parts[0]);
}

function tenantFromCookie(cookie: string | null | undefined): string | null {
  if (!cookie) return null;
  for (const part of cookie.split(";")) {
    const [name, raw] = part.trim().split("=");
    if (name === TENANT_COOKIE) {
      try {
        return normalizeTenantId(decodeURIComponent(raw ?? ""));
      } catch {
        return null;
      }
    }
  }
  return null;
}

export interface TenantResolutionInput {
  header?: string | null;
  query?: string | null;
  cookie?: string | null;
  host?: string | null;
}

/**
 * Prioridad: query `?tenant=` > header `X-Tenant-Id` > cookie > subdominio.
 * El fallback es siempre `mania`, para que el comportamiento actual no cambie.
 */
export function resolveTenantId(input: TenantResolutionInput = {}): string {
  return (
    normalizeTenantId(input.query) ??
    normalizeTenantId(input.header) ??
    tenantFromCookie(input.cookie) ??
    tenantFromHost(input.host) ??
    DEFAULT_TENANT_ID
  );
}

export function resolveTenantFromRequest(request: Request): string {
  const url = new URL(request.url);
  return resolveTenantId({
    query: url.searchParams.get("tenant"),
    header: request.headers.get(TENANT_HEADER),
    cookie: request.headers.get("cookie"),
    host:
      request.headers.get("x-forwarded-host") ??
      request.headers.get("host") ??
      url.host,
  });
}

/**
 * Transforma claves legacy (`rm_cart_v1`) en claves por tenant
 * (`rm_fuego_cart_v1`). `mania` mantiene la clave original sin prefijo para
 * no perder datos ya guardados en el dispositivo o el navegador.
 */
export function tenantStorageKey(tenantId: string, legacyKey: string): string {
  if (!isDemoTenant(tenantId)) return legacyKey;
  return legacyKey.startsWith("rm_")
    ? `rm_${tenantId}_${legacyKey.slice(3)}`
    : `rm_${tenantId}_${legacyKey}`;
}

/** Script inyectado por el layout para que los componentes cliente sepan el tenant. */
export function tenantClientScript(tenantId: string): string {
  return `window.__RM_TENANT_ID__=${JSON.stringify(tenantId)};`;
}

/** Prefija una ruta interna con `?tenant=` cuando no es el tenant por defecto. */
export function withTenant(path: string, tenantId: string): string {
  if (!tenantId || tenantId === DEFAULT_TENANT_ID) return path;
  const sep = path.includes("?") ? "&" : "?";
  return `${path}${sep}tenant=${encodeURIComponent(tenantId)}`;
}
