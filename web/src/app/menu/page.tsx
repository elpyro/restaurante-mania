import type { Metadata } from "next";
import { JsonLd } from "@/components/JsonLd";
import { MenuBrowser } from "@/components/MenuBrowser";
import { getPublicMenu } from "@/lib/menu";
import { breadcrumbJsonLd, menuJsonLd } from "@/lib/seo";
import { siteConfig } from "@/lib/site";

export const metadata: Metadata = {
  title: "Menú completo",
  description:
    "Explora el menú de Restaurante Manía: entrantes, platos fuertes, postres y bebidas. Precios, ingredientes y pedidos en línea.",
  alternates: { canonical: "/menu" },
  openGraph: {
    title: `Menú completo | ${siteConfig.name}`,
    description:
      "Entrantes, platos fuertes, postres y bebidas. Pide en línea y recibe en casa.",
    url: "/menu",
    images: [{ url: "/og.svg", width: 1200, height: 630, alt: "Menú del restaurante" }],
  },
};

export default async function MenuPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const [{ categories, items, source }, params] = await Promise.all([
    getPublicMenu(),
    searchParams,
  ]);

  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6 sm:py-14">
      <JsonLd
        data={[
          menuJsonLd(categories, items),
          breadcrumbJsonLd([
            { name: "Inicio", path: "/" },
            { name: "Menú", path: "/menu" },
          ]),
        ]}
      />

      <header className="mb-8 max-w-2xl">
        <p className="text-xs font-bold uppercase tracking-widest text-brand-700">
          Catálogo
        </p>
        <h1 className="section-title mt-1">Nuestro menú</h1>
        <p className="mt-3 text-sm leading-relaxed text-ink-500 sm:text-base">
          Todo se prepara al momento con ingredientes frescos. Busca por nombre
          o filtra por categoría; agrega tus favoritos al carrito y confirma en
          segundos.
        </p>
        <p className="mt-2 text-xs text-ink-500">
          {source === "firestore"
            ? "Precios y disponibilidad sincronizados con Firestore."
            : "Datos de demostración. Conecta Firebase para administrar el menú en vivo."}
        </p>
      </header>

      <MenuBrowser
        categories={categories}
        items={items}
        initialQuery={params.q ?? ""}
      />
    </div>
  );
}
