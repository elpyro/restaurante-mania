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
export const LANDING_HEADER = "x-rm-landing";

/** Base pública de las páginas de cada restaurante. */
export const MENU_BASE_PATH = "/menu";
/** Prefijo visible del slug: `restaurante-taquitos-mexicanos`. */
export const TENANT_SLUG_PREFIX = "restaurante-";

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

/** Instancias fijas: mantienen su comportamiento histórico sin plantilla. */
export const FIXED_TENANT_IDS: readonly string[] = ["mania", "fuego", "verde"];

export function isFixedTenant(tenantId: string): boolean {
  return FIXED_TENANT_IDS.includes(tenantId);
}

/**
 * Restaurantes creados por el usuario. Arrancan con la plantilla genérica
 * mientras no tengan configuración/catálogo propio en Firestore.
 */
export function isTemplateTenant(tenantId: string): boolean {
  return isValidTenantId(tenantId) && !isFixedTenant(tenantId);
}

/**
 * Formato de los IDs creados desde la APK. Se aceptan también los tres tenants
 * fijos porque cumplen el mismo patrón.
 */
export const TENANT_ID_PATTERN = /^[a-z0-9][a-z0-9_-]{0,63}$/;

/** Definiciones descubiertas en Firestore (restaurantes creados por el usuario). */
const DYNAMIC_TENANTS: Record<string, TenantDefinition> = {};

export function isValidTenantId(value: unknown): value is string {
  return typeof value === "string" && TENANT_ID_PATTERN.test(value);
}

/** Registra la definición visible de una instancia creada en caliente. */
export function registerTenantDefinition(
  definition: Partial<TenantDefinition> & { id: string },
): void {
  const id = definition.id.trim().toLowerCase();
  if (!isValidTenantId(id) || Object.hasOwn(TENANTS, id)) return;
  const prefix =
    id.replace(/[^a-z0-9]/g, "").slice(0, 3).toUpperCase() || "RM";
  DYNAMIC_TENANTS[id] = {
    id,
    label: definition.label?.trim() || id,
    description: definition.description ?? "",
    preset: definition.preset ?? "custom",
    city: definition.city ?? "",
    address: definition.address ?? "",
    phone: definition.phone ?? "",
    whatsapp: definition.whatsapp ?? "",
    hours: definition.hours ?? "",
    currency: definition.currency ?? "COP",
    orderPrefix: definition.orderPrefix || prefix,
  };
}

export function normalizeTenantId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const candidate = value.trim().toLowerCase();
  if (!candidate) return null;
  // Antes solo se aceptaban los tres tenants fijos. Ahora cualquier ID con
  // el formato seguro es válido: la configuración se lee de Firestore.
  return isValidTenantId(candidate) ? candidate : null;
}

/** Solo los tenants con definición propia (fijos o ya descubiertos). */
export function isKnownTenant(tenantId: string): boolean {
  return (
    Object.hasOwn(TENANTS, tenantId) || Object.hasOwn(DYNAMIC_TENANTS, tenantId)
  );
}

/** Compatibilidad: identifica tenants distintos del predeterminado. */
export function isDemoTenant(tenantId: string): boolean {
  return tenantId !== DEFAULT_TENANT_ID;
}

export function tenantDefinition(tenantId: string): TenantDefinition {
  const fixed = TENANTS[tenantId];
  if (fixed) return fixed;
  const dynamic = DYNAMIC_TENANTS[tenantId];
  if (dynamic) return dynamic;
  // Un restaurante nuevo puede resolverse antes de que se lea su config:
  // derivamos una definición estable desde el ID para no caer en «Manía».
  registerTenantDefinition({ id: tenantId });
  return DYNAMIC_TENANTS[tenantId]!;
}

export function tenantLabel(tenantId: string): string {
  return tenantDefinition(tenantId).label;
}

/** Slug visible de un tenant: `taquitos-mexicanos` → `restaurante-taquitos-mexicanos`. */
export function tenantSlug(tenantId: string): string {
  const id = normalizeTenantId(tenantId) ?? DEFAULT_TENANT_ID;
  return id.startsWith(TENANT_SLUG_PREFIX) ? id : `${TENANT_SLUG_PREFIX}${id}`;
}

const RESERVED_MENU_SEGMENTS = new Set([
  "menu",
  "cart",
  "checkout",
  "cuenta",
  "order",
]);

/**
 * Extrae el tenant de una ruta pública. `/menu` y `/menu/menu` son de Manía;
 * `/menu/restaurante-<id>/...` resuelve al tenant `<id>`.
 */
export function tenantFromPath(
  pathname: string | null | undefined,
): string | null {
  if (!pathname) return null;
  const [root, slug] = pathname.split("/").filter(Boolean);
  if (root !== MENU_BASE_PATH.slice(1)) return null;
  if (!slug || RESERVED_MENU_SEGMENTS.has(slug)) return DEFAULT_TENANT_ID;
  const raw = slug.startsWith(TENANT_SLUG_PREFIX)
    ? slug.slice(TENANT_SLUG_PREFIX.length)
    : slug;
  return normalizeTenantId(raw);
}

/** `fuego.localhost:3000` → `fuego`. El host raíz no especifica tenant. */
export function tenantFromHost(host: string | null | undefined): string | null {
  if (!host) return null;
  const hostname = host.split(":")[0]?.toLowerCase() ?? "";
  if (!hostname || hostname === "localhost" || hostname === "127.0.0.1") {
    return null;
  }
  const parts = hostname.split(".");
  // Solo subdominio de primer nivel: fuego.ejemplo.com, fuego.localhost.
  // Un dominio raíz (ejemplo.com) NO es un tenant, aunque su etiqueta cumpla
  // el formato de ID (antes lo ocultaba la lista fija de tenants).
  const hasSubdomain =
    parts.length >= 3 || (parts.length === 2 && parts[1] === "localhost");
  if (!hasSubdomain) return null;
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
  path?: string | null;
  header?: string | null;
  query?: string | null;
  cookie?: string | null;
  host?: string | null;
}

/**
 * Prioridad: ruta `/menu/<restaurante>` > query `?tenant=` > header
 * `X-Tenant-Id` > cookie > subdominio. El fallback es siempre `mania`.
 */
export function resolveTenantId(input: TenantResolutionInput = {}): string {
  return (
    tenantFromPath(input.path) ??
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
    path: url.pathname,
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

/**
 * Construye una ruta pública legible: `/menu` para Manía y
 * `/menu/restaurante-<id>` para cualquier otro restaurante.
 */
export function withTenant(path: string, tenantId: string): string {
  const id = normalizeTenantId(tenantId) ?? DEFAULT_TENANT_ID;
  const base =
    id === DEFAULT_TENANT_ID
      ? MENU_BASE_PATH
      : `${MENU_BASE_PATH}/${tenantSlug(id)}`;
  if (!path || path === "/") return base;
  const suffix = path.startsWith("/") ? path : `/${path}`;
  return `${base}${suffix}`;
}
