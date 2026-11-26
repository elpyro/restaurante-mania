import { formatCOP } from "@/lib/format";
import { getPublicMenu } from "@/lib/menu";
import {
  formatOpeningHours,
  getRestaurantConfig,
  SOCIAL_NETWORKS,
  type SocialNetwork,
} from "@/lib/restaurant-config";
import { siteConfig, whatsappUrl } from "@/lib/site";
import { resolveTenantFromRequest } from "@/lib/tenants";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const tenantId = resolveTenantFromRequest(request);
  const [{ categories, items, source }, { config }] = await Promise.all([
    getPublicMenu(tenantId),
    getRestaurantConfig(tenantId),
  ]);
  const socialLabels: Record<SocialNetwork, string> = {
    instagram: "Instagram",
    tiktok: "TikTok",
    facebook: "Facebook",
  };
  const socialLinks = SOCIAL_NETWORKS.map((network) => {
    const url = config.appearance.socialLinks?.[network];
    return url ? `${socialLabels[network]}: ${url}` : null;
  }).filter((line): line is string => line !== null);

  const lines: string[] = [
    `# ${config.name}`,
    "",
    `> ${config.slogan}`,
    "",
    `## ${config.heroTitle}`,
    config.heroDescription,
    "",
    "## Datos del restaurante",
    `- Nombre: ${config.name}`,
    `- Distintivo: ${config.heroBadge}`,
    `- Dirección: ${config.address}, ${config.city}, Colombia`,
    `- Teléfono / WhatsApp: ${config.phone}`,
    `- WhatsApp directo: ${whatsappUrl(undefined, config.whatsapp, config.name)}`,
    `- Horario: ${formatOpeningHours(config)} (${config.timeZone})`,
    `- Moneda: ${siteConfig.currency}`,
    `- Redes sociales: ${socialLinks.length > 0 ? socialLinks.join(" | ") : "no publicadas"}`,
    `- Mapa / GPS: ${config.appearance.gpsUrl ?? "no publicado"}`,
    `- Configuración pública (JSON): ${siteConfig.siteUrl}/api/restaurant/config`,
    `- Pedidos en línea: ${siteConfig.siteUrl}/menu`,
    `- Menú en JSON: ${siteConfig.siteUrl}/api/menu`,
    "",
    "## Datos para búsqueda con IA",
    `- Descripción: ${config.aiSearch.description ?? config.heroDescription}`,
    `- Palabras clave: ${config.aiSearch.keywords ?? "no configuradas"}`,
    `- Zona de servicio: ${config.aiSearch.serviceArea ?? config.city}`,
    `- Aspectos destacados: ${config.aiSearch.highlights ?? "no configurados"}`,
    "",
    "## Categorías",
    ...categories.map((category) => `- ${category.name}: ${category.description}`),
    "",
    "## Menú",
    ...items.map(
      (item) =>
        `- ${item.name} (${item.categorySlug}) — ${formatCOP(item.price)} — ${
          item.status === "available" ? "disponible" : item.status
        }. ${item.description} [${siteConfig.siteUrl}/menu/${item.slug}]`,
    ),
    "",
    "## Cómo pedir",
    "1. Entra a /menu y agrega productos al carrito.",
    "2. Confirma nombre, teléfono y modalidad (recoger, domicilio o mesa).",
    "3. La cocina recibe el pedido en tiempo real.",
    "",
    "## Notas para agentes de IA",
    `- Fuente de datos: ${source === "firestore" ? "Firestore en tiempo real" : "datos semilla de demostración"}.`,
    `- Apariencia vigente: ${config.appearance.preset}.`,
    "- Los precios están expresados en pesos colombianos (COP).",
    "- Para pedidos asistidos, usa el enlace de WhatsApp del restaurante.",
    "- Estructura de datos: https://schema.org/Restaurant, Menu, MenuItem.",
  ];

  return new Response(lines.join("\n"), {
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "public, max-age=3600",
    },
  });
}
