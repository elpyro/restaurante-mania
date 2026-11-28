import Image from "next/image";
import Link from "next/link";
import { ViewTransition } from "react";
import clsx from "clsx";
import {
  ArrowRight,
  ChefHat,
  CircleCheck,
  ClipboardList,
  Clock,
  MapPin,
  MessageCircle,
  Sparkles,
  Star,
  UtensilsCrossed,
} from "lucide-react";
import { CartQuantityBadge } from "@/components/CartQuantityBadge";
import { FavoritesCarousel } from "@/components/FavoritesCarousel";
import { JsonLd } from "@/components/JsonLd";
import { formatMoney } from "@/lib/format";
import { getFavoriteItems, getPublicMenu } from "@/lib/menu";
import { openingStatus } from "@/lib/opening-hours";
import { getRestaurantConfig } from "@/lib/restaurant-config";
import { restaurantJsonLd, websiteJsonLd } from "@/lib/seo";
import { whatsappUrl } from "@/lib/site";
import { getServerTenantId } from "@/lib/tenant-server";
import { withTenant } from "@/lib/tenants";

export const dynamic = "force-dynamic";

export default async function HomePage() {
  const tenantId = await getServerTenantId();
  const [{ categories, items, source }, favorites, { config }] =
    await Promise.all([
      getPublicMenu(tenantId),
      getFavoriteItems(12, tenantId),
      getRestaurantConfig(tenantId),
    ]);
  const availableCount = items.length;
  const status = openingStatus(config);
  const whatsapp = whatsappUrl(undefined, config.whatsapp, config.name);
  const bannerUrl = config.appearance.bannerUrl;
  const logoUrl = config.appearance.logoUrl;
  const money = (value: number) => formatMoney(value, config.currency);

  return (
    <>
      <JsonLd
        data={[
          restaurantJsonLd(config, tenantId),
          websiteJsonLd(config, tenantId),
        ]}
      />

      <section
        className={clsx(
          "relative isolate overflow-hidden border-b border-line",
          bannerUrl ? "min-h-[34rem]" : "bg-gradient-to-br from-hero-from via-surface to-hero-to",
        )}
      >
        {bannerUrl ? (
          <>
            <Image
              src={bannerUrl}
              alt=""
              fill
              priority
              unoptimized
              sizes="100vw"
              className="-z-20 object-cover object-right lg:object-center"
            />
            {/* En móvil el recorte va al extremo derecho; en desktop vuelve al centro. El GIF sigue animado. */}
            <div className="absolute inset-0 -z-10 bg-gradient-to-br from-ink/60 via-ink/40 to-ink/55" />
            <div className="pointer-events-none absolute inset-0 -z-10 bg-[radial-gradient(circle_at_20%_20%,rgb(var(--brand-400)/0.28),transparent_45%)]" />
          </>
        ) : (
          <>
            <div className="pointer-events-none absolute -left-24 top-10 -z-10 h-72 w-72 rounded-full bg-brand-200/40 blur-3xl" />
            <div className="pointer-events-none absolute -right-16 bottom-0 -z-10 h-80 w-80 rounded-full bg-accent-soft/70 blur-3xl" />
          </>
        )}

        <div className="relative mx-auto grid max-w-6xl items-center gap-12 px-4 py-16 sm:px-6 lg:grid-cols-[1.1fr_0.9fr] lg:py-24">
          <div className="animate-fade-up">
            <div className="flex items-center gap-3">
              {logoUrl ? (
                <Image
                  src={logoUrl}
                  alt={`Logo de ${config.name}`}
                  width={80}
                  height={80}
                  priority
                  unoptimized
                  className="h-16 w-16 rounded-2xl border border-white/30 bg-surface-raised/90 object-contain p-1.5 shadow-glow sm:h-20 sm:w-20"
                />
              ) : (
                <span
                  className={clsx(
                    "grid h-14 w-14 place-items-center rounded-2xl shadow-glow sm:h-16 sm:w-16",
                    bannerUrl ? "bg-white/15 text-white" : "bg-brand text-white",
                  )}
                >
                  <UtensilsCrossed size={26} aria-hidden />
                </span>
              )}
              <span
                className={clsx(
                  "chip border backdrop-blur",
                  bannerUrl
                    ? "border-white/25 bg-white/10 text-white"
                    : "border-brand-200 bg-surface-raised/80 text-brand-strong",
                )}
              >
                <Sparkles size={14} aria-hidden /> {config.heroBadge}
              </span>
            </div>

            <h1
              className={clsx(
                "mt-6 font-display text-4xl font-bold leading-[1.08] tracking-tight sm:text-5xl lg:text-6xl",
                bannerUrl ? "text-white drop-shadow-lg" : "text-ink",
              )}
            >
              {config.heroTitle}
              <span
                className={clsx(
                  "mt-2 block text-[0.68em] leading-snug",
                  bannerUrl ? "text-brand-200" : "text-brand-strong",
                )}
              >
                {config.slogan}
              </span>
            </h1>
            <p
              className={clsx(
                "mt-5 max-w-xl text-base leading-relaxed sm:text-lg",
                bannerUrl ? "text-white/85" : "text-ink-soft",
              )}
            >
              {config.heroDescription}
            </p>
            <div className="mt-8 flex flex-wrap gap-3">
              <Link href={withTenant("/menu", tenantId)} className="btn-primary">
                Ver el menú y pedir <ArrowRight size={16} aria-hidden />
              </Link>
              <a
                href={whatsapp}
                target="_blank"
                rel="noopener noreferrer"
                className={clsx(
                  "inline-flex items-center justify-center gap-2 rounded-full border px-6 py-3 text-sm font-semibold transition",
                  bannerUrl
                    ? "border-white/30 bg-white/10 text-white hover:bg-white/20"
                    : "btn-secondary",
                )}
              >
                <MessageCircle size={16} aria-hidden /> Pedir por WhatsApp
              </a>
            </div>

            <dl
              className={clsx(
                "mt-10 grid max-w-lg grid-cols-3 gap-3 text-center",
                bannerUrl ? "text-white" : "text-ink",
              )}
            >
              {[
                { icon: Clock, label: "Preparación", value: "~20 min", pulse: false as boolean },
                {
                  icon: CircleCheck,
                  label: "Estado",
                  value: status.isOpen ? "Abierto" : status.label,
                  detail: status.detail,
                  pulse: status.isOpen,
                },
                {
                  icon: UtensilsCrossed,
                  label: "Platos activos",
                  value: String(availableCount),
                },
              ].map(({ icon: Icon, label, value, detail, pulse }) => (
                <div
                  key={label}
                  className={clsx(
                    "rounded-2xl border p-3 backdrop-blur",
                    bannerUrl
                      ? "border-white/20 bg-white/10"
                      : "border-line bg-surface-raised/80",
                  )}
                >
                  <Icon
                    size={16}
                    className={clsx(
                      "mx-auto",
                      bannerUrl ? "text-brand-200" : "text-brand",
                    )}
                    aria-hidden
                  />
                  <dt
                    className={clsx(
                      "mt-1 text-[11px] font-medium uppercase tracking-wide",
                      bannerUrl ? "text-white/70" : "text-ink-muted",
                    )}
                  >
                    {label}
                  </dt>
                  <dd className="mt-1 font-display text-xl font-bold">{value}</dd>
                  {detail ? (
                    <dd
                      className={clsx(
                        "mt-1 inline-flex items-center justify-center gap-1.5 text-[11px] font-semibold leading-tight",
                        bannerUrl ? "text-white/95" : "text-ink-muted",
                      )}
                    >
                      {pulse ? (
                        <span className="relative flex h-2.5 w-2.5 shrink-0">
                          <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-accent opacity-75" />
                          <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-accent" />
                        </span>
                      ) : null}
                      {detail}
                    </dd>
                  ) : null}
                </div>
              ))}
            </dl>
            <p
              className={clsx(
                "mt-4 flex items-center gap-1.5 text-xs",
                bannerUrl ? "text-white/75" : "text-ink-muted",
              )}
            >
              <MapPin size={13} aria-hidden />
              {config.city} · {config.address}
              <span aria-hidden>·</span>
              {source === "firestore"
                ? "Menú sincronizado en tiempo real"
                : "Modo demo con datos semilla"}
            </p>
          </div>

          {/* Columna vacía a propósito: el banner de fondo se ve sin fichas encima. */}
          <div className="hidden lg:block" aria-hidden />
        </div>
      </section>

      <section className="mx-auto max-w-6xl px-4 py-16 sm:px-6">
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div>
            <p className="eyebrow">Marcados desde la app</p>
            <h2 className="section-title mt-1">Favoritos de la casa</h2>
            <p className="mt-2 text-sm text-ink-muted">
              Desliza para descubrir los platos que más se piden.
            </p>
          </div>
          <Link
            href={withTenant("/menu", tenantId)}
            className="inline-flex items-center gap-1 text-sm font-semibold text-brand-strong transition hover:gap-2 hover:underline"
          >
            Ver menú completo <ArrowRight size={15} aria-hidden />
          </Link>
        </div>

        {favorites.length > 0 ? (
          <FavoritesCarousel>
            {favorites.map((item) => (
              <Link
                key={item.id}
                href={`/menu/${item.slug}`}
                className="group surface-card w-[15.5rem] shrink-0 snap-start overflow-hidden transition duration-300 hover:-translate-y-1 hover:shadow-glow sm:w-[17rem]"
              >
                <div className="relative h-44 overflow-hidden bg-gradient-to-br from-brand-100 via-surface to-accent-soft">
                  <ViewTransition
                    name={`dish-${item.slug}`}
                    share="morph"
                    default="none"
                  >
                    {item.imageUrl ? (
                      <Image
                        src={item.imageUrl}
                        alt={item.name}
                        fill
                        sizes="272px"
                        unoptimized={item.imageUrl.toLowerCase().includes(".gif")}
                        className="object-cover transition duration-500 group-hover:scale-105"
                      />
                    ) : (
                      <span className="grid h-full place-items-center text-6xl transition group-hover:scale-110">
                        {item.emoji}
                      </span>
                    )}
                  </ViewTransition>
                  <CartQuantityBadge menuItemId={item.id} />
                  <span className="absolute left-3 top-3 rounded-full bg-surface-raised/90 px-2.5 py-1 text-[10px] font-bold uppercase tracking-wide text-brand-strong shadow-sm">
                    ⭐ Favorito
                  </span>
                </div>
                <div className="p-4">
                  <h3 className="font-display text-lg font-bold leading-tight text-ink">
                    {item.name}
                  </h3>
                  <p className="mt-1 line-clamp-2 text-xs leading-relaxed text-ink-muted">
                    {item.description}
                  </p>
                  <div className="mt-3 flex items-center justify-between">
                    <span className="font-bold text-brand-strong">
                      {money(item.price)}
                    </span>
                    <span className="inline-flex items-center gap-1 text-xs font-semibold text-ink-soft group-hover:text-brand-strong">
                      Ver plato <ArrowRight size={13} aria-hidden />
                    </span>
                  </div>
                </div>
              </Link>
            ))}
          </FavoritesCarousel>
        ) : (
          <div className="surface-card mt-8 flex flex-col items-center gap-3 px-6 py-12 text-center">
            <span className="grid h-14 w-14 place-items-center rounded-full bg-brand-50 text-brand-strong">
              <Star size={24} aria-hidden />
            </span>
            <h3 className="font-display text-xl font-bold text-ink">
              Aún no hay favoritos publicados
            </h3>
            <p className="max-w-md text-sm text-ink-muted">
              Marca «Favorito» en un producto desde la app administrativa y
              aparecerá aquí automáticamente. Mientras tanto, explora todo el
              menú.
            </p>
            <Link href={withTenant("/menu", tenantId)} className="btn-primary mt-2">
              Explorar el menú <ArrowRight size={15} aria-hidden />
            </Link>
          </div>
        )}
      </section>

      <section className="border-y border-line bg-surface-raised">
        <div className="mx-auto max-w-6xl px-4 py-16 sm:px-6">
          <div className="text-center">
            <p className="eyebrow">Explora</p>
            <h2 className="section-title mt-1">Un menú para cada antojo</h2>
            <p className="mx-auto mt-3 max-w-2xl text-sm leading-relaxed text-ink-muted">
              Desde entrantes para compartir hasta postres que se acaban primero.
              Todo se prepara al momento.
            </p>
          </div>
          <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {categories.map((category) => {
              const count = items.filter(
                (item) => item.categoryId === category.id,
              ).length;
              return (
                <Link
                  key={category.id}
                  href={`/menu#${category.slug}`}
                  className="group rounded-3xl border border-line bg-surface p-5 transition hover:-translate-y-0.5 hover:border-brand-300 hover:shadow-card"
                >
                  <span className="text-4xl transition group-hover:scale-110">
                    {category.emoji}
                  </span>
                  <h3 className="mt-3 font-display text-lg font-bold text-ink">
                    {category.name}
                  </h3>
                  <p className="mt-1 line-clamp-2 text-xs leading-relaxed text-ink-muted">
                    {category.description}
                  </p>
                  <p className="mt-3 inline-flex items-center gap-1 text-xs font-semibold text-brand-strong">
                    {count} platos <ArrowRight size={13} aria-hidden />
                  </p>
                </Link>
              );
            })}
          </div>
        </div>
      </section>

      <section className="mx-auto max-w-6xl px-4 py-16 sm:px-6">
        <div className="surface-card grid gap-8 p-8 sm:p-10 lg:grid-cols-3">
          <div>
            <p className="eyebrow">Así funciona</p>
            <h2 className="section-title mt-1 text-2xl sm:text-3xl">
              Pedir es muy fácil
            </h2>
            <p className="mt-3 text-sm leading-relaxed text-ink-muted">
              Sin registros ni complicaciones. Elige, confirma y nosotros nos
              encargamos del resto.
            </p>
          </div>
          <ol className="grid gap-5 sm:grid-cols-3 lg:col-span-2">
            {[
              {
                icon: ClipboardList,
                title: "Elige tus platos",
                text: "Explora el menú por categorías y agrega al carrito.",
              },
              {
                icon: CircleCheck,
                title: "Confirma el pedido",
                text: "Dinos tu nombre, teléfono y cómo quieres recibirlo.",
              },
              {
                icon: ChefHat,
                title: "Disfruta",
                text: "La cocina recibe tu pedido al instante y lo prepara.",
              },
            ].map(({ icon: Icon, title, text }, index) => (
              <li key={title} className="rounded-2xl bg-surface-muted p-4">
                <span className="grid h-9 w-9 place-items-center rounded-full bg-brand text-sm font-bold text-white">
                  {index + 1}
                </span>
                <Icon size={24} className="mt-3 text-brand-strong" aria-hidden />
                <h3 className="mt-2 font-semibold text-ink">{title}</h3>
                <p className="mt-1 text-xs leading-relaxed text-ink-muted">{text}</p>
              </li>
            ))}
          </ol>
        </div>
      </section>

      <section className="mx-auto max-w-6xl px-4 pb-24 sm:px-6">
        <div className="relative overflow-hidden rounded-4xl bg-footer px-8 py-12 text-center text-footer-ink sm:px-12">
          <div className="absolute -right-10 -top-10 h-40 w-40 rounded-full bg-brand-400/20 blur-2xl" />
          <div className="absolute -bottom-16 -left-10 h-48 w-48 rounded-full bg-accent/20 blur-2xl" />
          <h2 className="relative font-display text-3xl font-bold sm:text-4xl">
            {config.ctaTitle}
          </h2>
          <p className="relative mx-auto mt-3 max-w-xl text-sm text-footer-ink/70">
            {config.ctaDescription}
          </p>
          <div className="relative mt-6 flex flex-wrap justify-center gap-3">
            <Link href={withTenant("/menu", tenantId)} className="btn-primary">
              Pedir ahora <ArrowRight size={16} aria-hidden />
            </Link>
            <a href={whatsapp} target="_blank" rel="noopener noreferrer" className="btn-ghost">
              <MessageCircle size={16} aria-hidden /> WhatsApp
            </a>
          </div>
        </div>
      </section>
    </>
  );
}
