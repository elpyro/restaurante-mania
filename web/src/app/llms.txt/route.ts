import { formatCOP } from "@/lib/format";
import { getMenu } from "@/lib/menu";
import { siteConfig } from "@/lib/site";

export const revalidate = 3600;

export async function GET() {
  const { categories, items, source } = await getMenu();
  const lines: string[] = [
    `# ${siteConfig.name}`,
    "",
    `> ${siteConfig.description}`,
    "",
    "## Datos del restaurante",
    `- Nombre: ${siteConfig.name}`,
    `- Dirección: ${siteConfig.address}, ${siteConfig.city}, Colombia`,
    `- Teléfono / WhatsApp: ${siteConfig.phone}`,
    `- Horario: todos los días ${siteConfig.hours}`,
    `- Moneda: ${siteConfig.currency}`,
    `- Pedidos en línea: ${siteConfig.siteUrl}/menu`,
    `- Menú en JSON: ${siteConfig.siteUrl}/api/menu`,
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
