import { cache } from "react";
import { getDemoState } from "@/lib/demo-store";
import {
  getDocument,
  isFirestoreConfigured,
  tenantPath,
} from "@/lib/firebase/rest";
import { siteConfig } from "@/lib/site";
import {
  DEFAULT_TENANT_ID,
  isDemoTenant,
  isKnownTenant,
  isTemplateTenant,
  registerTenantDefinition,
  tenantDefinition,
} from "@/lib/tenants";
import type { PaymentMethod } from "@/lib/types";

export type AppearancePreset = "mania" | "fuego" | "verde" | "noche" | "tierra" | "oceano" | "uva" | "custom";
export type DeliveryOption = "pickup" | "delivery" | "table";
export type CustomColorKey =
  | "brand"
  | "accent"
  | "surface"
  | "ink"
  | "heroFrom"
  | "heroTo"
  | "footer";
export type CustomColors = Record<CustomColorKey, string>;
export type PaymentMethodLabels = Partial<Record<PaymentMethod, string>>;
export type SocialNetwork = "instagram" | "tiktok" | "facebook";
export type SocialLinks = Partial<Record<SocialNetwork, string | null>>;
export type Weekday = "mon" | "tue" | "wed" | "thu" | "fri" | "sat" | "sun";

/** Días en que el restaurante recibe pedidos, en orden de la semana. */
export const WEEKDAYS: Weekday[] = [
  "mon",
  "tue",
  "wed",
  "thu",
  "fri",
  "sat",
  "sun",
];

export const WEEKDAY_LABELS: Record<Weekday, string> = {
  mon: "Lun",
  tue: "Mar",
  wed: "Mié",
  thu: "Jue",
  fri: "Vie",
  sat: "Sáb",
  sun: "Dom",
};

export const DEFAULT_TIME_ZONE = "America/Bogota";
export const DEFAULT_OPENING_DAYS: Weekday[] = [
  "mon",
  "tue",
  "wed",
  "thu",
  "fri",
  "sat",
];
export const DEFAULT_OPEN_TIME = "11:30";
export const DEFAULT_CLOSE_TIME = "20:30";

/** Textos que los agentes de IA leen desde `/llms.txt` y los metadatos. */
export interface AiSearchConfig {
  description?: string | null;
  keywords?: string | null;
  serviceArea?: string | null;
  highlights?: string | null;
}

export interface AppearanceConfig {
  preset: AppearancePreset;
  /** `null` elimina la imagen; se acepta porque Firestore lo serializa así. */
  bannerUrl?: string | null;
  logoUrl?: string | null;
  customColors?: CustomColors;
  /** Enlaces que se muestran en el pie solo cuando están publicados. */
  socialLinks?: SocialLinks;
  /** Enlace al mapa (Google Maps, Waze, etc.) del pie de página. */
  gpsUrl?: string | null;
  /** Enlace a la ficha/reseñas de Google del restaurante. */
  googlePlaceUrl?: string | null;
}

/** Parche parcial: los mapas anidados se fusionan con la configuración actual. */
export type RestaurantConfigPatch = Partial<
  Omit<
    RestaurantConfig,
    "appearance" | "deliveryOptions" | "paymentMethodLabels" | "aiSearch"
  >
> & {
  appearance?: Partial<AppearanceConfig>;
  deliveryOptions?: Partial<Record<DeliveryOption, boolean>>;
  paymentMethodLabels?: PaymentMethodLabels;
  aiSearch?: Partial<AiSearchConfig>;
};

export interface RestaurantConfig {
  name: string;
  slogan: string;
  heroTitle: string;
  heroDescription: string;
  heroBadge: string;
  appearance: AppearanceConfig;
  phone: string;
  countryCode: string;
  whatsapp: string;
  address: string;
  city: string;
  hours: string;
  /** `false` fuerza el estado «Cerrado» en la portada, sin bloquear pedidos. */
  isOpen: boolean;
  /** Zona IANA usada para calcular el estado de la portada. */
  timeZone: string;
  openingDays: Weekday[];
  /** Horarios en 24 h (`HH:mm`) dentro de [timeZone]. */
  openTime: string;
  closeTime: string;
  ctaTitle: string;
  ctaDescription: string;
  currency: string;
  showOrderTypeOptions: boolean;
  deliveryOptions: Record<DeliveryOption, boolean>;
  paymentMethods: PaymentMethod[];
  paymentMethodLabels: PaymentMethodLabels;
  aiSearch: AiSearchConfig;
  updatedAt?: string;
}

export interface RestaurantConfigSnapshot {
  config: RestaurantConfig;
  configured: boolean;
  source: "firestore" | "env" | "demo";
}

export type PublicRestaurantConfig = Omit<RestaurantConfig, "updatedAt">;

export const APPEARANCE_PRESETS: AppearancePreset[] = [
  "mania",
  "fuego",
  "verde",
  "noche",
  "tierra",
  "oceano",
  "uva",
  "custom",
];

export const DELIVERY_OPTIONS: DeliveryOption[] = [
  "pickup",
  "delivery",
  "table",
];

export const PAYMENT_METHODS: PaymentMethod[] = [
  "cash",
  "card",
  "nequi",
  "daviplata",
];

export const SOCIAL_NETWORKS: SocialNetwork[] = [
  "instagram",
  "tiktok",
  "facebook",
];

export const AI_SEARCH_KEYS = [
  "description",
  "keywords",
  "serviceArea",
  "highlights",
] as const;

export const AI_SEARCH_LIMITS: Record<(typeof AI_SEARCH_KEYS)[number], number> = {
  description: 500,
  keywords: 300,
  serviceArea: 120,
  highlights: 300,
};

export const CUSTOM_COLOR_KEYS: CustomColorKey[] = [
  "brand",
  "accent",
  "surface",
  "ink",
  "heroFrom",
  "heroTo",
  "footer",
];

function isDynamicUsageError(error: unknown): boolean {
  return (
    error instanceof Error &&
    (error as Error & { digest?: unknown }).digest === "DYNAMIC_SERVER_USAGE"
  );
}

/**
 * Valores vigentes mientras no exista `restaurant/config` en Firestore.
 * La identidad y los contactos siguen las variables NEXT_PUBLIC_* históricas.
 */
export const DEFAULT_RESTAURANT_CONFIG: RestaurantConfig = {
  name: siteConfig.name,
  slogan: "Cocina colombiana hecha con calma y servida con cariño.",
  heroTitle: "El sabor de casa, a un clic de distancia.",
  heroDescription:
    "Pide tu bandeja paisa, un ajiaco bien caliente o una limonada de coco. Preparamos todo al momento y lo tienes listo en minutos.",
  heroBadge: `🇨🇴 Cocina colombiana · ${siteConfig.city}`,
  appearance: { preset: "mania", socialLinks: {} },
  phone: "300 123 4567",
  countryCode: "+57",
  whatsapp: siteConfig.whatsapp,
  address: siteConfig.address,
  city: siteConfig.city,
  hours: siteConfig.hours,
  isOpen: true,
  timeZone: DEFAULT_TIME_ZONE,
  openingDays: [...DEFAULT_OPENING_DAYS],
  openTime: DEFAULT_OPEN_TIME,
  closeTime: DEFAULT_CLOSE_TIME,
  ctaTitle: "¿Hambre? Tu mesa o domicilio te espera.",
  ctaDescription:
    "Abrimos todos los días de Lun–Sáb 11:30–20:30. Haz tu pedido en línea o escríbenos por WhatsApp.",
  currency: siteConfig.currency,
  showOrderTypeOptions: true,
  deliveryOptions: { pickup: true, delivery: true, table: true },
  paymentMethods: [...PAYMENT_METHODS],
  paymentMethodLabels: {},
  aiSearch: {},
};

/**
 * Plantilla inicial de cualquier restaurante creado desde la APK o abierto por
 * un `?tenant=` nuevo. No incluye ciudad, país ni platos típicos: el dueño la
 * reemplaza con sus propios datos desde el POS o el panel web.
 */
export const GENERIC_RESTAURANT_CONFIG: RestaurantConfig = {
  name: "Restaurante de ejemplo",
  slogan: "Comida lista para compartir, todos los días.",
  heroTitle: "Tu próxima comida empieza aquí.",
  heroDescription:
    "Explora el menú, elige tu platillo favorito y recíbelo en la mesa o en la puerta. Cada pedido se prepara al momento.",
  heroBadge: "🍽️ Menú para todos",
  appearance: { preset: "tierra", socialLinks: {} },
  phone: "000 000 0000",
  countryCode: "+00",
  whatsapp: "+000000000000",
  address: "Dirección por definir",
  city: "Ciudad por definir",
  hours: "Lun–Sáb 11:30–20:30",
  isOpen: true,
  timeZone: DEFAULT_TIME_ZONE,
  openingDays: [...DEFAULT_OPENING_DAYS],
  openTime: DEFAULT_OPEN_TIME,
  closeTime: DEFAULT_CLOSE_TIME,
  ctaTitle: "¿Listo para pedir?",
  ctaDescription:
    "Elige tus platillos, confirma tu pedido y nosotros nos encargamos del resto.",
  currency: "USD",
  showOrderTypeOptions: true,
  deliveryOptions: { pickup: true, delivery: true, table: true },
  paymentMethods: ["cash", "card"],
  paymentMethodLabels: { cash: "Efectivo", card: "Tarjeta" },
  aiSearch: {
    description:
      "Restaurante con pedidos en línea, menú actualizado y atención cercana.",
    keywords: "restaurante, menú, pedidos en línea, comida",
    serviceArea: "Zona de atención por definir",
    highlights:
      "Platillos preparados al momento, pedidos sencillos, servicio amable",
  },
};

/** Usa el nombre real del tenant cuando ya fue registrado desde Firestore. */
export function genericRestaurantConfig(tenantId: string): RestaurantConfig {
  const config = structuredClone(GENERIC_RESTAURANT_CONFIG);
  if (isKnownTenant(tenantId)) {
    const label = tenantDefinition(tenantId).label.trim();
    if (label) config.name = label;
  }
  return config;
}

const THEME_TOKENS = [
  "surface",
  "surface-raised",
  "surface-muted",
  "ink",
  "ink-soft",
  "ink-muted",
  "ink-400",
  "ink-500",
  "ink-700",
  "ink-900",
  "brand-50",
  "brand-100",
  "brand-200",
  "brand-300",
  "brand-400",
  "brand-500",
  "brand-600",
  "brand-700",
  "brand-800",
  "brand-900",
  "accent",
  "accent-strong",
  "accent-soft",
  "line",
  "hero-from",
  "hero-to",
  "footer",
  "footer-ink",
] as const;

export type ThemeToken = (typeof THEME_TOKENS)[number];
export type ThemePreset = Record<ThemeToken, string>;

export const PRESETS: Record<
  Exclude<AppearancePreset, "custom">,
  ThemePreset
> = {
  mania: {
    surface: "#fffaf5",
    "surface-raised": "#ffffff",
    "surface-muted": "#f6f1ea",
    ink: "#1c1917",
    "ink-soft": "#44403c",
    "ink-muted": "#78716c",
    "ink-400": "#a8a29e",
    "ink-500": "#78716c",
    "ink-700": "#44403c",
    "ink-900": "#1c1917",
    "brand-50": "#fff8ed",
    "brand-100": "#ffefd4",
    "brand-200": "#ffdca8",
    "brand-300": "#ffc271",
    "brand-400": "#ff9d38",
    "brand-500": "#fe7f12",
    "brand-600": "#ef6408",
    "brand-700": "#c64b09",
    "brand-800": "#9d3c10",
    "brand-900": "#7e3310",
    accent: "#059669",
    "accent-strong": "#047857",
    "accent-soft": "#d1fae5",
    line: "#e7e5e4",
    "hero-from": "#fff8ed",
    "hero-to": "#ecfdf5",
    footer: "#1c1917",
    "footer-ink": "#ffffff",
  },
  fuego: {
    surface: "#fff8f5",
    "surface-raised": "#ffffff",
    "surface-muted": "#fdf0ea",
    ink: "#291312",
    "ink-soft": "#5b2b26",
    "ink-muted": "#8b5b54",
    "ink-400": "#b98d86",
    "ink-500": "#8b5b54",
    "ink-700": "#5b2b26",
    "ink-900": "#291312",
    "brand-50": "#fff1f2",
    "brand-100": "#ffe4e6",
    "brand-200": "#fecdd3",
    "brand-300": "#fda4af",
    "brand-400": "#fb7185",
    "brand-500": "#f43f5e",
    "brand-600": "#e11d48",
    "brand-700": "#be123c",
    "brand-800": "#9f1239",
    "brand-900": "#881337",
    accent: "#ea580c",
    "accent-strong": "#c2410c",
    "accent-soft": "#ffedd5",
    line: "#f1dfdc",
    "hero-from": "#fff1f2",
    "hero-to": "#fff7ed",
    footer: "#2a100d",
    "footer-ink": "#fff7ed",
  },
  verde: {
    surface: "#f8fcf7",
    "surface-raised": "#ffffff",
    "surface-muted": "#eef7ed",
    ink: "#10281c",
    "ink-soft": "#315844",
    "ink-muted": "#5c7f6b",
    "ink-400": "#8fab9b",
    "ink-500": "#5c7f6b",
    "ink-700": "#315844",
    "ink-900": "#10281c",
    "brand-50": "#f0fdf4",
    "brand-100": "#dcfce7",
    "brand-200": "#bbf7d0",
    "brand-300": "#86efac",
    "brand-400": "#4ade80",
    "brand-500": "#22c55e",
    "brand-600": "#16a34a",
    "brand-700": "#15803d",
    "brand-800": "#166534",
    "brand-900": "#14532d",
    accent: "#65a30d",
    "accent-strong": "#4d7c0f",
    "accent-soft": "#ecfccb",
    line: "#dcebdc",
    "hero-from": "#f0fdf4",
    "hero-to": "#f7fee7",
    footer: "#102319",
    "footer-ink": "#f0fdf4",
  },
  noche: {
    surface: "#0b1120",
    "surface-raised": "#111827",
    "surface-muted": "#172033",
    ink: "#f8fafc",
    "ink-soft": "#cbd5e1",
    "ink-muted": "#94a3b8",
    "ink-400": "#64748b",
    "ink-500": "#94a3b8",
    "ink-700": "#cbd5e1",
    "ink-900": "#f8fafc",
    "brand-50": "#eef2ff",
    "brand-100": "#e0e7ff",
    "brand-200": "#c7d2fe",
    "brand-300": "#a5b4fc",
    "brand-400": "#818cf8",
    "brand-500": "#6366f1",
    "brand-600": "#818cf8",
    "brand-700": "#a5b4fc",
    "brand-800": "#c7d2fe",
    "brand-900": "#e0e7ff",
    accent: "#22d3ee",
    "accent-strong": "#67e8f9",
    "accent-soft": "#164e63",
    line: "#1e293b",
    "hero-from": "#111827",
    "hero-to": "#0f172a",
    footer: "#070b14",
    "footer-ink": "#e2e8f0",
  },
  tierra: {
    surface: "#fbf7f2",
    "surface-raised": "#ffffff",
    "surface-muted": "#f3ede4",
    ink: "#2b2118",
    "ink-soft": "#5c4a3a",
    "ink-muted": "#8a7663",
    "ink-400": "#b39f8d",
    "ink-500": "#8a7663",
    "ink-700": "#5c4a3a",
    "ink-900": "#2b2118",
    "brand-50": "#fdf8f3",
    "brand-100": "#f7ead9",
    "brand-200": "#edd0b0",
    "brand-300": "#dfae7d",
    "brand-400": "#cd8752",
    "brand-500": "#b86a35",
    "brand-600": "#9a5429",
    "brand-700": "#7d4224",
    "brand-800": "#673724",
    "brand-900": "#552f20",
    accent: "#78716c",
    "accent-strong": "#57534e",
    "accent-soft": "#f5f5f4",
    line: "#e7ddd1",
    "hero-from": "#fdf8f3",
    "hero-to": "#f5f5f4",
    footer: "#2b2118",
    "footer-ink": "#fdf8f3",
  },
  oceano: {
    surface: "#f4fbfb",
    "surface-raised": "#ffffff",
    "surface-muted": "#e8f4f4",
    ink: "#132a2e",
    "ink-soft": "#355c63",
    "ink-muted": "#5f858c",
    "ink-400": "#93b2b8",
    "ink-500": "#5f858c",
    "ink-700": "#355c63",
    "ink-900": "#132a2e",
    "brand-50": "#effefd",
    "brand-100": "#c7fffb",
    "brand-200": "#90fff8",
    "brand-300": "#51f7f0",
    "brand-400": "#1de4e0",
    "brand-500": "#05c7c7",
    "brand-600": "#009ea1",
    "brand-700": "#057d80",
    "brand-800": "#0a6265",
    "brand-900": "#0d5154",
    accent: "#0284c7",
    "accent-strong": "#0369a1",
    "accent-soft": "#e0f2fe",
    line: "#d5e8ea",
    "hero-from": "#effefd",
    "hero-to": "#e0f2fe",
    footer: "#132a2e",
    "footer-ink": "#effefd",
  },
  uva: {
    surface: "#fbf7ff",
    "surface-raised": "#ffffff",
    "surface-muted": "#f3ebfa",
    ink: "#24162f",
    "ink-soft": "#533a66",
    "ink-muted": "#7e6491",
    "ink-400": "#a891b8",
    "ink-500": "#7e6491",
    "ink-700": "#533a66",
    "ink-900": "#24162f",
    "brand-50": "#faf5ff",
    "brand-100": "#f3e8ff",
    "brand-200": "#e9d5ff",
    "brand-300": "#d8b4fe",
    "brand-400": "#c084fc",
    "brand-500": "#a855f7",
    "brand-600": "#9333ea",
    "brand-700": "#7e22ce",
    "brand-800": "#6b21a8",
    "brand-900": "#581c87",
    accent: "#db2777",
    "accent-strong": "#be185d",
    "accent-soft": "#fce7f3",
    line: "#e8dcf0",
    "hero-from": "#faf5ff",
    "hero-to": "#fce7f3",
    footer: "#24162f",
    "footer-ink": "#faf5ff",
  },
};

function clampChannel(value: number): number {
  return Math.max(0, Math.min(255, Math.round(value)));
}

function parseHex(hex: string): [number, number, number] {
  const value = hex.replace("#", "");
  const normalized =
    value.length === 3
      ? value
          .split("")
          .map((char) => char + char)
          .join("")
      : value.padEnd(6, "0").slice(0, 6);
  const number = Number.parseInt(normalized, 16);
  return [(number >> 16) & 255, (number >> 8) & 255, number & 255];
}

export function normalizeHex(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const text = value.trim().toLowerCase();
  if (!/^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/.test(text)) return null;
  const [r, g, b] = parseHex(text);
  return `#${[r, g, b]
    .map((channel) => channel.toString(16).padStart(2, "0"))
    .join("")}`;
}

function mixColor(a: string, b: string, weightOfB: number): string {
  const [ar, ag, ab] = parseHex(a);
  const [br, bg, bb] = parseHex(b);
  const channels = [ar, ag, ab].map((channel, index) =>
    clampChannel(channel * (1 - weightOfB) + [br, bg, bb][index]! * weightOfB),
  );
  return `#${channels
    .map((channel) => channel.toString(16).padStart(2, "0"))
    .join("")}`;
}

function relativeLuminance(hex: string): number {
  const [r, g, b] = parseHex(hex).map((channel) => {
    const value = channel / 255;
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r! + 0.7152 * g! + 0.0722 * b!;
}

export function buildCustomTheme(colors: CustomColors): ThemePreset {
  const base = PRESETS.mania;
  const white = "#ffffff";
  const black = "#000000";
  const brand = colors.brand;
  const accent = colors.accent;
  const surface = colors.surface;
  const ink = colors.ink;
  const footerInk =
    relativeLuminance(colors.footer) > 0.45 ? black : white;

  return {
    ...base,
    surface,
    "surface-raised": mixColor(surface, white, 0.65),
    "surface-muted": mixColor(surface, ink, 0.05),
    ink,
    "ink-soft": mixColor(ink, surface, 0.25),
    "ink-muted": mixColor(ink, surface, 0.45),
    "ink-400": mixColor(ink, surface, 0.62),
    "ink-500": mixColor(ink, surface, 0.45),
    "ink-700": mixColor(ink, surface, 0.25),
    "ink-900": ink,
    "brand-50": mixColor(brand, white, 0.95),
    "brand-100": mixColor(brand, white, 0.88),
    "brand-200": mixColor(brand, white, 0.75),
    "brand-300": mixColor(brand, white, 0.58),
    "brand-400": mixColor(brand, white, 0.32),
    "brand-500": brand,
    "brand-600": mixColor(brand, black, 0.12),
    "brand-700": mixColor(brand, black, 0.28),
    "brand-800": mixColor(brand, black, 0.44),
    "brand-900": mixColor(brand, black, 0.58),
    accent,
    "accent-strong": mixColor(accent, black, 0.18),
    "accent-soft": mixColor(accent, surface, 0.86),
    line: mixColor(surface, ink, 0.13),
    "hero-from": colors.heroFrom,
    "hero-to": colors.heroTo,
    footer: colors.footer,
    "footer-ink": footerInk,
  };
}

/** Tema base de un preset (el estilo propio se resuelve en `resolveTheme`). */
export function themeForPreset(preset: AppearancePreset): ThemePreset {
  return PRESETS[preset === "custom" ? "mania" : preset] ?? PRESETS.mania;
}

export function resolveTheme(config: RestaurantConfig): ThemePreset {
  if (
    config.appearance.preset === "custom" &&
    config.appearance.customColors &&
    CUSTOM_COLOR_KEYS.every(
      (key) => typeof config.appearance.customColors?.[key] === "string",
    )
  ) {
    return buildCustomTheme(config.appearance.customColors);
  }
  return themeForPreset(config.appearance.preset);
}

function hexToChannels(hex: string): string {
  const [r, g, b] = parseHex(hex);
  return `${r} ${g} ${b}`;
}

export function tokensToCssVars(config: RestaurantConfig): string {
  const theme = resolveTheme(config);
  const declarations = THEME_TOKENS.map(
    (token) => `--${token}: ${hexToChannels(theme[token])};`,
  ).join("\n    ");
  return `:root {\n    ${declarations}\n  }`;
}

export function presetThemeColor(config: RestaurantConfig): string {
  return resolveTheme(config)["brand-600"];
}

export function isAppearancePreset(value: unknown): value is AppearancePreset {
  return typeof value === "string" && APPEARANCE_PRESETS.includes(value as AppearancePreset);
}

function nonEmptyString(value: unknown, fallback: string): string {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : fallback;
}

function normalizeCountryCode(
  value: unknown,
  fallback: RestaurantConfig,
): string {
  const text = typeof value === "string" ? value.trim() : "";
  return /^\+\d{1,4}$/.test(text) ? text : fallback.countryCode;
}

/**
 * Las configuraciones antiguas guardaban `phone` con el indicativo incluido.
 * Lo separamos para que el campo «Teléfono» y el indicativo sean independientes.
 */
function normalizePhone(
  rawPhone: unknown,
  rawCountryCode: unknown,
  fallback: RestaurantConfig,
): { phone: string; countryCode: string } {
  const countryCode = normalizeCountryCode(rawCountryCode, fallback);
  let phone = nonEmptyString(rawPhone, fallback.phone);
  if (phone.startsWith(countryCode)) {
    phone = phone.slice(countryCode.length).trim();
  } else if (phone.startsWith("+")) {
    const match = /^\+\d{1,4}\s*/.exec(phone);
    if (match) {
      phone = phone.slice(match[0].length).trim();
    }
  }
  if (!phone) phone = fallback.phone;
  return { phone, countryCode };
}

function normalizeCustomColors(value: unknown): CustomColors | undefined {
  if (!value || typeof value !== "object" || Array.isArray(value)) return undefined;
  const raw = value as Record<string, unknown>;
  const result = {} as CustomColors;
  for (const key of CUSTOM_COLOR_KEYS) {
    const color = normalizeHex(raw[key]);
    if (color) result[key] = color;
  }
  return Object.keys(result).length === CUSTOM_COLOR_KEYS.length
    ? result
    : undefined;
}

/** Acepta solo enlaces http(s); el resto se ignora para no publicar `javascript:`. */
function normalizeExternalUrl(value: unknown, maxLength = 300): string | undefined {
  if (typeof value !== "string") return undefined;
  const text = value.trim();
  if (!text || text.length > maxLength) return undefined;
  try {
    const url = new URL(text);
    return url.protocol === "https:" || url.protocol === "http:" ? text : undefined;
  } catch {
    return undefined;
  }
}

function normalizeSocialLinks(value: unknown): SocialLinks {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const raw = value as Record<string, unknown>;
  const links: SocialLinks = {};
  for (const network of SOCIAL_NETWORKS) {
    const url = normalizeExternalUrl(raw[network]);
    if (url) links[network] = url;
  }
  return links;
}

function normalizeAiText(value: unknown, maxLength: number): string | undefined {
  if (typeof value !== "string") return undefined;
  const text = value.trim().replace(/\s+/g, " ");
  return text && text.length <= maxLength ? text : undefined;
}

function normalizeAiSearch(value: unknown): AiSearchConfig {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const raw = value as Record<string, unknown>;
  const result: AiSearchConfig = {};
  for (const key of AI_SEARCH_KEYS) {
    const text = normalizeAiText(raw[key], AI_SEARCH_LIMITS[key]);
    if (text) result[key] = text;
  }
  return result;
}

function normalizeAppearance(
  value: unknown,
  fallback: RestaurantConfig,
): AppearanceConfig {
  const raw =
    value && typeof value === "object" && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : {};
  const customColors = normalizeCustomColors(raw.customColors);
  const preset = isAppearancePreset(raw.preset)
    ? raw.preset
    : fallback.appearance.preset;
  const bannerUrl =
    typeof raw.bannerUrl === "string" && isAllowedAssetUrl(raw.bannerUrl)
      ? raw.bannerUrl
      : undefined;
  const logoUrl =
    typeof raw.logoUrl === "string" && isAllowedAssetUrl(raw.logoUrl)
      ? raw.logoUrl
      : undefined;
  const gpsUrl = normalizeExternalUrl(raw.gpsUrl, 500);
  const googlePlaceUrl = normalizeExternalUrl(raw.googlePlaceUrl, 500);
  return {
    preset,
    ...(bannerUrl ? { bannerUrl } : {}),
    ...(logoUrl ? { logoUrl } : {}),
    ...(preset === "custom" && customColors ? { customColors } : {}),
    socialLinks: normalizeSocialLinks(raw.socialLinks),
    ...(gpsUrl ? { gpsUrl } : {}),
    ...(googlePlaceUrl ? { googlePlaceUrl } : {}),
  };
}

function normalizeDeliveryOptions(
  value: unknown,
  fallback: RestaurantConfig,
): Record<DeliveryOption, boolean> {
  const raw =
    value && typeof value === "object" && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : {};
  return {
    pickup:
      typeof raw.pickup === "boolean"
        ? raw.pickup
        : fallback.deliveryOptions.pickup,
    delivery:
      typeof raw.delivery === "boolean"
        ? raw.delivery
        : fallback.deliveryOptions.delivery,
    table:
      typeof raw.table === "boolean"
        ? raw.table
        : fallback.deliveryOptions.table,
  };
}

function normalizePaymentMethods(
  value: unknown,
  fallback: RestaurantConfig,
): PaymentMethod[] {
  if (!Array.isArray(value)) return [...fallback.paymentMethods];
  const methods = value.filter(
    (method): method is PaymentMethod =>
      typeof method === "string" && PAYMENT_METHODS.includes(method as PaymentMethod),
  );
  return methods.length > 0 ? [...new Set(methods)] : [...fallback.paymentMethods];
}

function normalizePaymentMethodLabels(value: unknown): PaymentMethodLabels {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const raw = value as Record<string, unknown>;
  const labels: PaymentMethodLabels = {};
  for (const method of PAYMENT_METHODS) {
    const label = raw[method];
    if (typeof label === "string" && label.trim()) labels[method] = label.trim();
  }
  return labels;
}

/** Acepta solo zonas IANA conocidas por la base de datos de `Intl`. */
export function isValidTimeZone(value: string): boolean {
  const zone = value.trim();
  if (!zone || zone.length > 64) return false;
  try {
    const supported = (
      Intl as typeof Intl & {
        supportedValuesOf?: (key: string) => string[];
      }
    ).supportedValuesOf?.("timeZone");
    if (!supported) {
      new Intl.DateTimeFormat("en-US", { timeZone: zone });
      return true;
    }
    return supported.includes(zone) || zone.toUpperCase() === "UTC";
  } catch {
    return false;
  }
}

function normalizeTimeZone(value: unknown): string {
  return typeof value === "string" && isValidTimeZone(value)
    ? value.trim()
    : DEFAULT_RESTAURANT_CONFIG.timeZone;
}

export function isValidTimeOfDay(value: unknown): value is string {
  return (
    typeof value === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(value.trim())
  );
}

function normalizeTimeOfDay(value: unknown, fallback: string): string {
  return isValidTimeOfDay(value) ? value.trim() : fallback;
}

function normalizeOpeningDays(value: unknown): Weekday[] {
  if (!Array.isArray(value)) return [...DEFAULT_OPENING_DAYS];
  const days = value.filter((day): day is Weekday => WEEKDAYS.includes(day as Weekday));
  return days.length > 0
    ? WEEKDAYS.filter((day) => days.includes(day))
    : [...DEFAULT_OPENING_DAYS];
}

/** Texto corto y legable derivado del horario estructurado. */
export function formatOpeningHours(config: Pick<
  RestaurantConfig,
  "openingDays" | "openTime" | "closeTime"
>): string {
  const days = config.openingDays;
  let dayText: string;
  if (days.length === 7) {
    dayText = "Todos los días";
  } else if (days.length === 0) {
    return "Cerrado";
  } else {
    const indices = days.map((day) => WEEKDAYS.indexOf(day)).sort((a, b) => a - b);
    const consecutive =
      indices.every((index, i) => i === 0 || index === indices[i - 1] + 1) &&
      indices.length > 1;
    dayText = consecutive
      ? `${WEEKDAY_LABELS[WEEKDAYS[indices[0]]]}–${WEEKDAY_LABELS[WEEKDAYS[indices[indices.length - 1]]]}`
      : indices.map((index) => WEEKDAY_LABELS[WEEKDAYS[index]]).join(", ");
  }
  return `${dayText} ${config.openTime}–${config.closeTime}`;
}

function normalizeConfig(
  raw: Record<string, unknown>,
  fallback: RestaurantConfig = DEFAULT_RESTAURANT_CONFIG,
): RestaurantConfig {
  const { phone, countryCode } = normalizePhone(raw.phone, raw.countryCode, fallback);
  const currency =
    typeof raw.currency === "string" && /^[A-Z]{3}$/.test(raw.currency.trim())
      ? raw.currency.trim()
      : fallback.currency;
  const timeZone = normalizeTimeZone(raw.timeZone);
  const openingDays = normalizeOpeningDays(raw.openingDays);
  const openTime = normalizeTimeOfDay(raw.openTime, DEFAULT_OPEN_TIME);
  const closeTime = normalizeTimeOfDay(raw.closeTime, DEFAULT_CLOSE_TIME);
  const hours =
    nonEmptyString(raw.hours, "") ||
    formatOpeningHours({ openingDays, openTime, closeTime });
  const aiSearch = normalizeAiSearch(raw.aiSearch);
  return {
    ...fallback,
    name: nonEmptyString(raw.name, fallback.name),
    slogan: nonEmptyString(raw.slogan, fallback.slogan),
    heroTitle: nonEmptyString(raw.heroTitle, fallback.heroTitle),
    heroDescription: nonEmptyString(
      raw.heroDescription,
      fallback.heroDescription,
    ),
    heroBadge: nonEmptyString(raw.heroBadge, fallback.heroBadge),
    appearance: normalizeAppearance(raw.appearance, fallback),
    phone,
    countryCode,
    whatsapp: nonEmptyString(raw.whatsapp, fallback.whatsapp),
    address: nonEmptyString(raw.address, fallback.address),
    city: nonEmptyString(raw.city, fallback.city),
    hours,
    isOpen:
      typeof raw.isOpen === "boolean" ? raw.isOpen : fallback.isOpen,
    timeZone,
    openingDays,
    openTime,
    closeTime,
    ctaTitle: nonEmptyString(raw.ctaTitle, fallback.ctaTitle),
    ctaDescription: nonEmptyString(
      raw.ctaDescription,
      fallback.ctaDescription,
    ),
    currency,
    showOrderTypeOptions:
      typeof raw.showOrderTypeOptions === "boolean"
        ? raw.showOrderTypeOptions
        : fallback.showOrderTypeOptions,
    deliveryOptions: normalizeDeliveryOptions(raw.deliveryOptions, fallback),
    paymentMethods: normalizePaymentMethods(raw.paymentMethods, fallback),
    paymentMethodLabels: normalizePaymentMethodLabels(raw.paymentMethodLabels),
    aiSearch:
      Object.keys(aiSearch).length > 0 ? aiSearch : { ...fallback.aiSearch },
    updatedAt: typeof raw.updatedAt === "string" ? raw.updatedAt : undefined,
  };
}

/** Teléfono listo para mostrar con el indicativo del país. */
export function displayPhone(config: RestaurantConfig): string {
  return `${config.countryCode} ${config.phone}`.trim();
}

/** Número en formato `573001234567` para wa.me y enlaces `tel:`. */
export function whatsappNumber(config: RestaurantConfig): string {
  const fromConfig = config.whatsapp.replace(/\D/g, "");
  if (fromConfig.length >= 8) return fromConfig;
  return `${config.countryCode.replace(/\D/g, "")}${config.phone.replace(/\D/g, "")}`;
}

/**
 * Una única lectura compartida por layout, SEO y rutas públicas.
 * `getDocument` ya respeta revalidate=0; `cache` deduplica dentro de cada request.
 */
export const getRestaurantConfig = cache(
  async (tenantId = DEFAULT_TENANT_ID): Promise<RestaurantConfigSnapshot> => {
    const templateFallback = () => ({
      config: genericRestaurantConfig(tenantId),
      configured: false,
      source: "env" as const,
    });
    if (!isFirestoreConfigured()) {
      if (isTemplateTenant(tenantId)) return templateFallback();
      if (isDemoTenant(tenantId)) {
        return {
          config: getDemoState(tenantId).config,
          configured: false,
          source: "demo",
        };
      }
      return { config: DEFAULT_RESTAURANT_CONFIG, configured: false, source: "env" };
    }
    try {
      const doc = await getDocument<Record<string, unknown>>(
        tenantPath(tenantId, "restaurant"),
        "config",
        0,
      );
      if (!doc) {
        return isTemplateTenant(tenantId)
          ? templateFallback()
          : { config: DEFAULT_RESTAURANT_CONFIG, configured: false, source: "env" };
      }
      const config = normalizeConfig(
        doc,
        isTemplateTenant(tenantId)
          ? GENERIC_RESTAURANT_CONFIG
          : DEFAULT_RESTAURANT_CONFIG,
      );
      // Los restaurantes creados desde la APK no están en la lista fija:
      // registramos su nombre para que etiquetas y códigos de pedido usen
      // datos reales en lugar de los valores de manía.
      registerTenantDefinition({
        id: tenantId,
        label: config.name,
        description: "",
        city: config.city,
        address: config.address,
        phone: config.phone,
        whatsapp: config.whatsapp,
        hours: config.hours,
        currency: config.currency,
      });
      return { config, configured: true, source: "firestore" };
    } catch (error) {
      if (!isDynamicUsageError(error)) {
        console.warn("[restaurant-config] Firestore no disponible, usando valores por defecto:", error);
      }
      return isTemplateTenant(tenantId)
        ? templateFallback()
        : { config: DEFAULT_RESTAURANT_CONFIG, configured: false, source: "env" };
    }
  },
);

/** Persiste la configuración de una instancia demo dentro de su propio estado. */
export function saveDemoRestaurantConfig(
  tenantId: string,
  config: RestaurantConfig,
): void {
  if (!isDemoTenant(tenantId)) return;
  getDemoState(tenantId).config = config;
}

export function toPublicRestaurantConfig(
  config: RestaurantConfig,
): PublicRestaurantConfig {
  const { updatedAt: _updatedAt, ...publicConfig } = config;
  return publicConfig;
}

export class ConfigValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConfigValidationError";
  }
}

const TEXT_LIMITS: Record<
  Exclude<
    keyof RestaurantConfig,
    | "appearance"
    | "updatedAt"
    | "deliveryOptions"
    | "paymentMethods"
    | "paymentMethodLabels"
    | "showOrderTypeOptions"
    | "aiSearch"
    | "isOpen"
    | "timeZone"
    | "openingDays"
    | "openTime"
    | "closeTime"
  >,
  { min: number; max: number }
> = {
  name: { min: 2, max: 80 },
  slogan: { min: 0, max: 160 },
  heroTitle: { min: 2, max: 120 },
  heroDescription: { min: 0, max: 500 },
  heroBadge: { min: 0, max: 80 },
  phone: { min: 5, max: 40 },
  countryCode: { min: 2, max: 5 },
  whatsapp: { min: 6, max: 20 },
  address: { min: 5, max: 160 },
  city: { min: 2, max: 80 },
  hours: { min: 2, max: 80 },
  ctaTitle: { min: 2, max: 120 },
  ctaDescription: { min: 2, max: 300 },
  currency: { min: 3, max: 3 },
};

const TEXT_FIELDS = Object.keys(TEXT_LIMITS) as Array<keyof typeof TEXT_LIMITS>;

function isAllowedAssetUrl(value: string): boolean {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:") return false;
    const hosts = [
      "firebasestorage.googleapis.com",
      "firebasestorage.app",
    ];
    return hosts.some(
      (host) => url.hostname === host || url.hostname.endsWith(`.${host}`),
    );
  } catch {
    return false;
  }
}

/**
 * Solo permite campos del contrato público. Las claves desconocidas se ignoran
 * para no propagar secrets ni campos internos a Firestore.
 */
export function sanitizeConfigPatch(body: unknown): RestaurantConfigPatch {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new ConfigValidationError("El cuerpo debe ser un objeto JSON.");
  }
  const raw = body as Record<string, unknown>;
  const patch: RestaurantConfigPatch = {};
  const errors: string[] = [];

  for (const field of TEXT_FIELDS) {
    if (!(field in raw)) continue;
    const value = raw[field];
    if (typeof value !== "string") {
      errors.push(`${field} debe ser texto.`);
      continue;
    }
    const text = value.trim();
    const { min, max } = TEXT_LIMITS[field];
    if (text.length < min || text.length > max) {
      errors.push(`${field} debe tener entre ${min} y ${max} caracteres.`);
      continue;
    }
    if (field === "whatsapp") {
      const compact = text.replace(/[\s()\-]/g, "");
      const digits = compact.replace(/^\+/, "");
      if (!/^\+?\d+$/.test(compact) || digits.length < 6 || digits.length > 15) {
        errors.push("whatsapp debe ser un número válido (6 a 15 dígitos).");
        continue;
      }
      (patch as Record<string, unknown>)[field] = compact;
    } else if (field === "countryCode") {
      if (!/^\+\d{1,4}$/.test(text)) {
        errors.push("countryCode debe ser un indicativo válido, por ejemplo +57.");
        continue;
      }
      (patch as Record<string, unknown>)[field] = text;
    } else if (field === "currency") {
      if (!/^[A-Za-z]{3}$/.test(text)) {
        errors.push("currency debe ser un código de 3 letras, por ejemplo COP.");
        continue;
      }
      (patch as Record<string, unknown>)[field] = text.toUpperCase();
    } else {
      (patch as Record<string, unknown>)[field] = text;
    }
  }

  if ("isOpen" in raw) {
    if (typeof raw.isOpen !== "boolean") {
      errors.push("isOpen debe ser verdadero o falso.");
    } else {
      patch.isOpen = raw.isOpen;
    }
  }

  if ("timeZone" in raw) {
    if (typeof raw.timeZone !== "string" || !isValidTimeZone(raw.timeZone)) {
      errors.push("timeZone debe ser una zona horaria IANA válida.");
    } else {
      patch.timeZone = raw.timeZone.trim();
    }
  }

  if ("openingDays" in raw) {
    const days = raw.openingDays;
    if (
      !Array.isArray(days) ||
      days.length === 0 ||
      days.length > WEEKDAYS.length ||
      days.some((day) => !WEEKDAYS.includes(day as Weekday))
    ) {
      errors.push(
        "openingDays debe incluir al menos uno de: mon, tue, wed, thu, fri, sat, sun.",
      );
    } else {
      patch.openingDays = WEEKDAYS.filter((day) => days.includes(day));
    }
  }

  const nextOpenTime = isValidTimeOfDay(raw.openTime)
    ? raw.openTime.trim()
    : patch.openTime ?? DEFAULT_OPEN_TIME;
  const nextCloseTime = isValidTimeOfDay(raw.closeTime)
    ? raw.closeTime.trim()
    : patch.closeTime ?? DEFAULT_CLOSE_TIME;
  for (const field of ["openTime", "closeTime"] as const) {
    if (!(field in raw)) continue;
    if (!isValidTimeOfDay(raw[field])) {
      errors.push(`${field} debe tener el formato HH:mm (24 horas).`);
      continue;
    }
    (patch as Record<string, unknown>)[field] = raw[field].trim();
  }
  if (nextOpenTime >= nextCloseTime) {
    errors.push("closeTime debe ser posterior a openTime.");
  }

  if ("showOrderTypeOptions" in raw) {
    if (typeof raw.showOrderTypeOptions !== "boolean") {
      errors.push("showOrderTypeOptions debe ser verdadero o falso.");
    } else {
      patch.showOrderTypeOptions = raw.showOrderTypeOptions;
    }
  }

  if ("deliveryOptions" in raw) {
    const value = raw.deliveryOptions;
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      errors.push("deliveryOptions debe ser un objeto.");
    } else {
      const options = value as Record<string, unknown>;
      const next: Partial<Record<DeliveryOption, boolean>> = {};
      for (const option of DELIVERY_OPTIONS) {
        if (!(option in options)) continue;
        if (typeof options[option] !== "boolean") {
          errors.push(`deliveryOptions.${option} debe ser verdadero o falso.`);
          continue;
        }
        next[option] = options[option] as boolean;
      }
      if (Object.keys(next).length > 0) {
        patch.deliveryOptions = next;
      }
    }
  }

  if ("paymentMethods" in raw) {
    const value = raw.paymentMethods;
    if (
      !Array.isArray(value) ||
      value.length === 0 ||
      value.length > PAYMENT_METHODS.length ||
      value.some(
        (method) =>
          typeof method !== "string" ||
          !PAYMENT_METHODS.includes(method as PaymentMethod),
      )
    ) {
      errors.push(
        "paymentMethods debe incluir al menos uno de: cash, card, nequi, daviplata.",
      );
    } else {
      patch.paymentMethods = [...new Set(value as PaymentMethod[])];
    }
  }

  if ("paymentMethodLabels" in raw) {
    const value = raw.paymentMethodLabels;
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      errors.push("paymentMethodLabels debe ser un objeto.");
    } else {
      const labels = value as Record<string, unknown>;
      const next: PaymentMethodLabels = {};
      for (const method of PAYMENT_METHODS) {
        if (!(method in labels)) continue;
        const label = labels[method];
        if (typeof label !== "string" || label.trim().length > 24) {
          errors.push(`paymentMethodLabels.${method} debe tener máximo 24 caracteres.`);
          continue;
        }
        next[method] = label.trim();
      }
      patch.paymentMethodLabels = next;
    }
  }

  if ("aiSearch" in raw) {
    const value = raw.aiSearch;
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      errors.push("aiSearch debe ser un objeto.");
    } else {
      const search = value as Record<string, unknown>;
      const next: Partial<AiSearchConfig> = {};
      for (const key of AI_SEARCH_KEYS) {
        if (!(key in search)) continue;
        const text = search[key];
        if (
          text === null ||
          (typeof text === "string" && !text.trim())
        ) {
          next[key] = null;
          continue;
        }
        const normalized = normalizeAiText(text, AI_SEARCH_LIMITS[key]);
        if (!normalized && text !== null) {
          errors.push(`aiSearch.${key} debe tener máximo ${AI_SEARCH_LIMITS[key]} caracteres.`);
          continue;
        }
        next[key] = normalized ?? null;
      }
      if (Object.keys(next).length > 0) patch.aiSearch = next;
    }
  }

  if ("appearance" in raw) {
    const value = raw.appearance;
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      errors.push("appearance debe ser un objeto.");
    } else {
      const appearance = value as Record<string, unknown>;
      const next: Partial<AppearanceConfig> = {};
      if ("preset" in appearance) {
        if (!isAppearancePreset(appearance.preset)) {
          errors.push("appearance.preset debe ser mania, fuego, verde, noche, tierra, oceano, uva o custom.");
        } else {
          next.preset = appearance.preset;
        }
      }
      for (const field of ["bannerUrl", "logoUrl"] as const) {
        if (!(field in appearance)) continue;
        const asset = appearance[field];
        if (asset === null || asset === "") {
          next[field] = null;
          continue;
        }
        if (typeof asset !== "string" || !isAllowedAssetUrl(asset)) {
          errors.push(`appearance.${field} debe ser una URL de Firebase Storage.`);
          continue;
        }
        next[field] = asset;
      }
      if ("customColors" in appearance) {
        const colors = normalizeCustomColors(appearance.customColors);
        if (!colors) {
          errors.push(
            "appearance.customColors debe incluir los 7 colores en formato hexadecimal.",
          );
        } else {
          next.customColors = colors;
        }
      }
      if ("socialLinks" in appearance) {
        const value = appearance.socialLinks;
        if (!value || typeof value !== "object" || Array.isArray(value)) {
          errors.push("appearance.socialLinks debe ser un objeto.");
        } else {
          const links = value as Record<string, unknown>;
          const socialLinks: SocialLinks = {};
          for (const network of SOCIAL_NETWORKS) {
            if (!(network in links)) continue;
            const rawUrl = links[network];
            if (
              rawUrl === null ||
              (typeof rawUrl === "string" && !rawUrl.trim())
            ) {
              socialLinks[network] = null;
              continue;
            }
            const url = normalizeExternalUrl(rawUrl);
            if (!url) {
              errors.push(`appearance.socialLinks.${network} debe ser una URL http(s).`);
              continue;
            }
            socialLinks[network] = url;
          }
          next.socialLinks = socialLinks;
        }
      }
      if ("gpsUrl" in appearance) {
        const rawUrl = appearance.gpsUrl;
        if (rawUrl === null || (typeof rawUrl === "string" && !rawUrl.trim())) {
          next.gpsUrl = null;
        } else {
          const url = normalizeExternalUrl(rawUrl, 500);
          if (!url) errors.push("appearance.gpsUrl debe ser una URL http(s).");
          else next.gpsUrl = url;
        }
      }
      if ("googlePlaceUrl" in appearance) {
        const rawUrl = appearance.googlePlaceUrl;
        if (rawUrl === null || (typeof rawUrl === "string" && !rawUrl.trim())) {
          next.googlePlaceUrl = null;
        } else {
          const url = normalizeExternalUrl(rawUrl, 500);
          if (!url) errors.push("appearance.googlePlaceUrl debe ser una URL http(s).");
          else next.googlePlaceUrl = url;
        }
      }
      if (Object.keys(next).length > 0) patch.appearance = next;
    }
  }

  if (errors.length > 0) throw new ConfigValidationError(errors.join(" "));
  if (Object.keys(patch).length === 0) {
    throw new ConfigValidationError("No hay campos válidos para actualizar.");
  }
  return patch;
}
