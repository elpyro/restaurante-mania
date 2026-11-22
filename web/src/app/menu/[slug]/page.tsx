import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { AddToCartButton } from "@/components/AddToCartButton";
import { JsonLd } from "@/components/JsonLd";
import { MenuItemCard } from "@/components/MenuItemCard";
import { formatCOP } from "@/lib/format";
import { getMenu } from "@/lib/menu";
import { seedMenuItems } from "@/lib/seed";
import { breadcrumbJsonLd, menuItemJsonLd } from "@/lib/seo";
import { siteConfig, whatsappUrl } from "@/lib/site";

interface Props {
  params: Promise<{ slug: string }>;
}

export const dynamicParams = true;

export async function generateStaticParams() {
  return seedMenuItems.map((item) => ({ slug: item.slug }));
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const { items } = await getMenu();
  const item = items.find((entry) => entry.slug === slug);
  if (!item) {
    return { title: "Plato no encontrado", robots: { index: false } };
  }
  const description = `${item.description} Precio: ${formatCOP(item.price)}. Pide en línea en ${siteConfig.name}.`;
  return {
    title: `${item.name} — ${formatCOP(item.price)}`,
    description,
    alternates: { canonical: `/menu/${item.slug}` },
    openGraph: {
      title: `${item.name} | ${siteConfig.name}`,
      description,
      url: `/menu/${item.slug}`,
      images: [
        {
          url: "/og.svg",
          width: 1200,
          height: 630,
          alt: `${item.name} — ${siteConfig.name}`,
        },
      ],
    },
    twitter: { card: "summary_large_image", title: item.name, description },
  };
}

export default async function DishPage({ params }: Props) {
  const { slug } = await params;
  const { categories, items } = await getMenu();
  const item = items.find((entry) => entry.slug === slug);
  if (!item) notFound();

  const category =
    categories.find((entry) => entry.id === item.categoryId) ?? categories[0];
  const related = items
    .filter(
      (entry) =>
        entry.categoryId === item.categoryId && entry.id !== item.id,
    )
    .slice(0, 3);

  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6 sm:py-14">
      <JsonLd
        data={[
          menuItemJsonLd(item, category),
          breadcrumbJsonLd([
            { name: "Inicio", path: "/" },
            { name: "Menú", path: "/menu" },
            { name: category.name, path: `/menu#${category.slug}` },
            { name: item.name, path: `/menu/${item.slug}` },
          ]),
        ]}
      />

      <nav className="mb-6 text-xs text-ink-500" aria-label="Ruta de navegación">
        <Link href="/" className="hover:text-brand-700">
          Inicio
        </Link>
        <span className="mx-1.5">/</span>
        <Link href="/menu" className="hover:text-brand-700">
          Menú
        </Link>
        <span className="mx-1.5">/</span>
        <span className="text-ink-700">{item.name}</span>
      </nav>

      <div className="grid gap-8 lg:grid-cols-2">
        <div className="relative grid min-h-72 place-items-center overflow-hidden rounded-3xl border border-stone-200 bg-gradient-to-br from-brand-100 via-amber-50 to-emerald-100 text-[10rem] shadow-card">
          <span>{item.emoji}</span>
          {item.featured ? (
            <span className="absolute left-5 top-5 rounded-full bg-white/85 px-3 py-1 text-xs font-bold uppercase tracking-wide text-brand-700 shadow-sm">
              Favorito de la casa
            </span>
          ) : null}
        </div>

        <div>
          <p className="text-xs font-bold uppercase tracking-widest text-brand-700">
            {category.emoji} {category.name}
          </p>
          <h1 className="mt-2 font-display text-4xl font-bold tracking-tight text-ink-900">
            {item.name}
          </h1>
          <p className="mt-4 text-base leading-relaxed text-ink-700">
            {item.description}
          </p>
          <div className="mt-6 flex flex-wrap items-center gap-3">
            <p className="font-display text-3xl font-bold text-brand-700">
              {formatCOP(item.price)}
            </p>
            <span className="rounded-full bg-stone-100 px-3 py-1 text-xs font-medium text-ink-700">
              ⏱ {item.prepMinutes} min
            </span>
            <span className="rounded-full bg-stone-100 px-3 py-1 text-xs font-medium text-ink-700">
              🔥 {item.calories} kcal
            </span>
            <span
              className={`rounded-full px-3 py-1 text-xs font-semibold ${
                item.status === "available"
                  ? "bg-emerald-100 text-emerald-800"
                  : "bg-amber-100 text-amber-800"
              }`}
            >
              {item.status === "available" ? "Disponible" : "Últimas unidades"}
            </span>
          </div>

          <div className="mt-6 flex flex-wrap gap-3">
            <AddToCartButton
              item={item}
              label="Agregar al carrito"
              className="inline-flex items-center justify-center rounded-full bg-brand-600 px-6 py-3 text-sm font-bold text-white transition hover:bg-brand-700 disabled:cursor-not-allowed disabled:bg-stone-200 disabled:text-stone-500"
            />
            <a
              href={whatsappUrl(
                `Hola, quiero pedir ${item.name} (${formatCOP(item.price)}).`,
              )}
              target="_blank"
              rel="noopener noreferrer"
              className="btn-secondary"
            >
              Pedir por WhatsApp
            </a>
          </div>

          <div className="mt-8 grid gap-4 sm:grid-cols-2">
            <div className="rounded-2xl border border-stone-200 bg-white p-4">
              <h2 className="text-sm font-bold text-ink-900">Ingredientes</h2>
              <ul className="mt-2 flex flex-wrap gap-1.5">
                {item.ingredients.map((ingredient) => (
                  <li
                    key={ingredient}
                    className="rounded-full bg-stone-100 px-2.5 py-1 text-[11px] font-medium text-ink-700"
                  >
                    {ingredient}
                  </li>
                ))}
              </ul>
            </div>
            <div className="rounded-2xl border border-stone-200 bg-white p-4">
              <h2 className="text-sm font-bold text-ink-900">Alérgenos</h2>
              {item.allergens.length > 0 ? (
                <ul className="mt-2 flex flex-wrap gap-1.5">
                  {item.allergens.map((allergen) => (
                    <li
                      key={allergen}
                      className="rounded-full bg-amber-100 px-2.5 py-1 text-[11px] font-semibold text-amber-900"
                    >
                      {allergen}
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="mt-2 text-xs text-ink-500">
                  Sin alérgenos declarados. Consulta por preparaciones especiales.
                </p>
              )}
            </div>
          </div>
        </div>
      </div>

      {related.length > 0 ? (
        <section className="mt-16">
          <h2 className="section-title text-2xl">También te puede gustar</h2>
          <div className="mt-6 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            {related.map((entry) => (
              <MenuItemCard key={entry.id} item={entry} />
            ))}
          </div>
        </section>
      ) : null}
    </div>
  );
}
