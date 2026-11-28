import type { Metadata } from "next";
import { Sparkles } from "lucide-react";
import { JsonLd } from "@/components/JsonLd";
import { MenuBrowser } from "@/components/MenuBrowser";
import { getPublicMenu } from "@/lib/menu";
import { getRestaurantConfig } from "@/lib/restaurant-config";
import { breadcrumbJsonLd, menuJsonLd } from "@/lib/seo";
import { getServerTenantId } from "@/lib/tenant-server";
import { withTenant } from "@/lib/tenants";

export const dynamic = "force-dynamic";

export async function generateMetadata(): Promise<Metadata> {
  const tenantId = await getServerTenantId();
  const { config } = await getRestaurantConfig(tenantId);
  const description = `Explora el menú de ${config.name}: entrantes, platos fuertes, postres y bebidas. Precios, ingredientes y pedidos en línea.`;
  const image = `/api/og?${new URLSearchParams({
    title: "Nuestro menú",
    description,
  }).toString()}`;

  return {
    title: "Menú completo",
    description,
    alternates: { canonical: withTenant("/menu", tenantId) },
    openGraph: {
      title: `Menú completo | ${config.name}`,
      description,
      url: withTenant("/menu", tenantId),
      images: [{ url: image, width: 1200, height: 630, alt: `Menú de ${config.name}` }],
    },
    twitter: {
      card: "summary_large_image",
      title: `Menú completo | ${config.name}`,
      description,
      images: [image],
    },
  };
}

export default async function MenuPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const tenantId = await getServerTenantId();
  const [{ categories, items }, params, { config }] = await Promise.all([
    getPublicMenu(tenantId),
    searchParams,
    getRestaurantConfig(tenantId),
  ]);

  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6 sm:py-14">
      <JsonLd
        data={[
          menuJsonLd(categories, items, config, tenantId),
          breadcrumbJsonLd(
            [
              { name: "Inicio", path: "/" },
              { name: "Menú", path: "/menu" },
            ],
            tenantId,
          ),
        ]}
      />

      <header className="mb-8 max-w-3xl animate-fade-up">
        <span className="chip border border-brand-200 bg-surface-raised text-brand-strong">
          <Sparkles size={14} aria-hidden /> Catálogo
        </span>
        <h1 className="section-title mt-4">Nuestro menú</h1>
        <p className="mt-3 text-sm leading-relaxed text-ink-muted sm:text-base">
          Todo se prepara al momento con ingredientes frescos. Busca por nombre
          o filtra por categoría; agrega tus favoritos al carrito y confirma en
          segundos.
        </p>
      </header>

      <MenuBrowser
        categories={categories}
        items={items}
        tenantId={tenantId}
        initialQuery={params.q ?? ""}
      />
    </div>
  );
}
