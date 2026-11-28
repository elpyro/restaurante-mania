import type { Metadata } from "next";
import Image from "next/image";
import { ImageLightbox } from "@/components/ImageLightbox";
import { LazyVideo } from "@/components/LazyVideo";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ViewTransition } from "react";
import {
  ArrowRight,
  ChefHat,
  CircleCheck,
  Clock,
  Flame,
  Leaf,
  MessageCircle,
  Sparkles,
} from "lucide-react";
import { AddToCartButton } from "@/components/AddToCartButton";
import { JsonLd } from "@/components/JsonLd";
import { MenuItemCard } from "@/components/MenuItemCard";
import { formatCOP } from "@/lib/format";
import { getPublicMenu } from "@/lib/menu";
import { getRestaurantConfig } from "@/lib/restaurant-config";
import { breadcrumbJsonLd, menuItemJsonLd } from "@/lib/seo";
import { whatsappUrl } from "@/lib/site";
import { getServerTenantId } from "@/lib/tenant-server";
import { withTenant } from "@/lib/tenants";

interface Props {
  params: Promise<{ slug: string }>;
}

export const dynamic = "force-dynamic";

/**
 * Next 16 entrega los segmentos dinámicos codificados en la página, pero
 * decodificados en `generateMetadata`. Normalizamos ambos para que los slugs
 * con caracteres no ASCII (p. ej. `ajiaco-santafereño`) resuelvan igual.
 */
function decodedSlug(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const slug = decodedSlug((await params).slug);
  const tenantId = await getServerTenantId();
  const [{ items }, { config }] = await Promise.all([
    getPublicMenu(tenantId),
    getRestaurantConfig(tenantId),
  ]);
  const item = items.find((entry) => entry.slug === slug);
  if (!item) {
    return { title: "Plato no encontrado", robots: { index: false } };
  }
  const description = `${item.description} Precio: ${formatCOP(item.price)}. Pide en línea en ${config.name}.`;
  const image = item.imageUrl
    ? item.imageUrl
    : `/api/og?${new URLSearchParams({ title: item.name, description }).toString()}`;

  return {
    title: `${item.name} — ${formatCOP(item.price)}`,
    description,
    alternates: { canonical: withTenant(`/menu/${item.slug}`, tenantId) },
    openGraph: {
      title: `${item.name} | ${config.name}`,
      description,
      url: withTenant(`/menu/${item.slug}`, tenantId),
      images: [
        {
          url: image,
          width: 1200,
          height: 630,
          alt: `${item.name} — ${config.name}`,
        },
      ],
    },
    twitter: { card: "summary_large_image", title: item.name, description },
  };
}

export default async function DishPage({ params }: Props) {
  const slug = decodedSlug((await params).slug);
  const tenantId = await getServerTenantId();
  const [{ categories, items }, { config }] = await Promise.all([
    getPublicMenu(tenantId),
    getRestaurantConfig(tenantId),
  ]);
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
          menuItemJsonLd(item, category, config, tenantId),
          breadcrumbJsonLd(
            [
              { name: "Inicio", path: "/" },
              { name: "Menú", path: "/menu" },
              { name: category.name, path: `/menu#${category.slug}` },
              { name: item.name, path: `/menu/${item.slug}` },
            ],
            tenantId,
          ),
        ]}
      />

      <nav className="mb-6 flex flex-wrap items-center gap-1.5 text-xs text-ink-muted" aria-label="Ruta de navegación">
        <Link href={withTenant("/", tenantId)} className="transition hover:text-brand-strong">Inicio</Link>
        <span aria-hidden>/</span>
        <Link href={withTenant("/menu", tenantId)} className="transition hover:text-brand-strong">Menú</Link>
        <span aria-hidden>/</span>
        <span className="font-medium text-ink-soft">{item.name}</span>
      </nav>

      <div className="grid gap-8 lg:grid-cols-2">
        <ViewTransition name={`dish-${item.slug}`} share="morph" default="none">
          <div className="relative grid min-h-[22rem] place-items-center overflow-hidden rounded-4xl border border-line bg-gradient-to-br from-brand-100 via-surface to-accent-soft shadow-card">
            {item.imageUrl ? (
              <ImageLightbox
                src={item.imageUrl}
                alt={item.name}
                priority
                sizes="(max-width: 1024px) 100vw, 560px"
                className="object-cover"
              />
            ) : (
              <span className="text-[10rem]">{item.emoji}</span>
            )}
            {item.featured ? (
              <span className="pointer-events-none absolute left-5 top-5 inline-flex items-center gap-1.5 rounded-full bg-surface-raised/90 px-3 py-1 text-xs font-bold uppercase tracking-wide text-brand-strong shadow-sm">
                <Sparkles size={13} aria-hidden /> Favorito de la casa
              </span>
            ) : null}
          </div>
        </ViewTransition>

        <div className="animate-fade-up">
          <span className="chip text-brand-strong">
            {category.emoji} {category.name}
          </span>
          <h1 className="mt-3 font-display text-4xl font-bold tracking-tight text-ink">
            {item.name}
          </h1>
          <p className="mt-4 text-base leading-relaxed text-ink-soft">
            {item.description}
          </p>
          <div className="mt-6 flex flex-wrap items-center gap-3">
            <p className="font-display text-3xl font-bold text-brand-strong">
              {formatCOP(item.price)}
            </p>
            {item.prepMinutes > 0 ? (
              <span className="chip">
                <Clock size={14} aria-hidden /> {item.prepMinutes} min
              </span>
            ) : null}
            {item.calories > 0 ? (
              <span className="chip">
                <Flame size={14} aria-hidden /> {item.calories} kcal
              </span>
            ) : null}
            <span
              className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold ${
                item.status === "available"
                  ? "bg-accent-soft text-accent-strong"
                  : "bg-brand-100 text-brand-800"
              }`}
            >
              <CircleCheck size={13} aria-hidden />
              {item.status === "available" ? "Disponible" : "Últimas unidades"}
            </span>
          </div>

          <div className="mt-6 flex flex-wrap gap-3">
            <AddToCartButton
              item={item}
              label="Agregar al carrito"
              className="btn-primary"
            />
            <a
              href={whatsappUrl(
                `Hola, quiero pedir ${item.name} (${formatCOP(item.price)}).`,
                config.whatsapp,
                config.name,
              )}
              target="_blank"
              rel="noopener noreferrer"
              className="btn-secondary"
            >
              <MessageCircle size={16} aria-hidden /> Pedir por WhatsApp
            </a>
          </div>

          <div className="mt-8 grid gap-4 sm:grid-cols-2">
            <div className="surface-card p-4">
              <h2 className="inline-flex items-center gap-2 text-sm font-bold text-ink">
                <ChefHat size={16} className="text-brand" aria-hidden /> Ingredientes
              </h2>
              <ul className="mt-3 flex flex-wrap gap-1.5">
                {item.ingredients.map((ingredient) => (
                  <li key={ingredient} className="chip">
                    {ingredient}
                  </li>
                ))}
              </ul>
            </div>
            {item.allergens.length > 0 ? (
              <div className="surface-card p-4">
                <h2 className="inline-flex items-center gap-2 text-sm font-bold text-ink">
                  <Leaf size={16} className="text-accent" aria-hidden /> Alérgenos
                </h2>
                <ul className="mt-3 flex flex-wrap gap-1.5">
                  {item.allergens.map((allergen) => (
                    <li
                      key={allergen}
                      className="rounded-full bg-brand-100 px-2.5 py-1 text-[11px] font-semibold text-brand-800"
                    >
                      {allergen}
                    </li>
                  ))}
                </ul>
              </div>
            ) : null}
          </div>
          {item.videoUrl && /^https?:\/\//i.test(item.videoUrl) ? (
            <div className="mt-6 surface-card overflow-hidden p-4">
              <h2 className="mb-3 text-sm font-bold text-ink">Video del plato</h2>
              {/(?:youtube\.com\/(?:watch\?v=|embed\/)|youtu\.be\/)([A-Za-z0-9_-]+)/.test(item.videoUrl) ? (
                <iframe
                  src={'https://www.youtube.com/embed/' + ((item.videoUrl.match(/(?:youtube\.com\/(?:watch\?v=|embed\/)|youtu\.be\/)([A-Za-z0-9_-]+)/) || [])[1] ?? '')}
                  className="aspect-video w-full rounded-xl"
                  allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                  allowFullScreen
                  title={'Video de ' + item.name}
                />
              ) : (
                <LazyVideo src={item.videoUrl} title={item.name} poster={item.imageUrl || undefined} />
              )}
            </div>
          ) : null}
        </div>
      </div>

      {related.length > 0 ? (
        <section className="mt-16">
          <div className="mb-6 flex items-center justify-between">
            <h2 className="section-title text-2xl">También te puede gustar</h2>
            <Link
              href={withTenant("/menu", tenantId)}
              className="inline-flex items-center gap-1 text-sm font-semibold text-brand-strong hover:underline"
            >
              Ver todo <ArrowRight size={15} aria-hidden />
            </Link>
          </div>
          <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            {related.map((entry) => (
              <MenuItemCard key={entry.id} item={entry} tenantId={tenantId} />
            ))}
          </div>
        </section>
      ) : null}
    </div>
  );
}
