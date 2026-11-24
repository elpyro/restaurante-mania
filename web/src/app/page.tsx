import Link from "next/link";
import { JsonLd } from "@/components/JsonLd";
import { MenuItemCard } from "@/components/MenuItemCard";
import { formatCOP } from "@/lib/format";
import { getFeaturedItems, getPublicMenu } from "@/lib/menu";
import { restaurantJsonLd, websiteJsonLd } from "@/lib/seo";
import { siteConfig, whatsappUrl } from "@/lib/site";

export default async function HomePage() {
  const [{ categories, items, source }, featured] = await Promise.all([
    getPublicMenu(),
    getFeaturedItems(6),
  ]);
  const availableCount = items.length;

  return (
    <>
      <JsonLd data={[restaurantJsonLd(), websiteJsonLd()]} />

      <section className="relative overflow-hidden border-b border-stone-200 bg-gradient-to-b from-brand-50 via-stone-50 to-stone-50">
        <div className="mx-auto grid max-w-6xl items-center gap-12 px-4 py-16 sm:px-6 lg:grid-cols-2 lg:py-24">
          <div>
            <p className="inline-flex items-center gap-2 rounded-full border border-brand-200 bg-white/70 px-3 py-1 text-xs font-semibold text-brand-800">
              🇨🇴 Cocina colombiana · {siteConfig.city}
            </p>
            <h1 className="mt-5 font-display text-4xl font-bold leading-[1.1] tracking-tight text-ink-900 sm:text-5xl lg:text-6xl">
              El sabor de casa,
              <span className="block text-brand-700">a un clic de distancia.</span>
            </h1>
            <p className="mt-5 max-w-xl text-base leading-relaxed text-ink-700 sm:text-lg">
              Pide tu bandeja paisa, un ajiaco bien caliente o una limonada de
              coco. Preparamos todo al momento y lo tienes listo en minutos.
            </p>
            <div className="mt-8 flex flex-wrap gap-3">
              <Link href="/menu" className="btn-primary">
                Ver el menú y pedir
              </Link>
              <a
                href={whatsappUrl()}
                target="_blank"
                rel="noopener noreferrer"
                className="btn-secondary"
              >
                Pedir por WhatsApp
              </a>
            </div>
            <dl className="mt-10 grid max-w-lg grid-cols-3 gap-4 text-center">
              <div className="rounded-2xl border border-stone-200 bg-white/80 p-3">
                <dt className="text-[11px] font-medium uppercase tracking-wide text-ink-500">
                  Preparación
                </dt>
                <dd className="mt-1 font-display text-xl font-bold text-ink-900">
                  ~20 min
                </dd>
              </div>
              <div className="rounded-2xl border border-stone-200 bg-white/80 p-3">
                <dt className="text-[11px] font-medium uppercase tracking-wide text-ink-500">
                  Calificación
                </dt>
                <dd className="mt-1 font-display text-xl font-bold text-ink-900">
                  4.8 ★
                </dd>
              </div>
              <div className="rounded-2xl border border-stone-200 bg-white/80 p-3">
                <dt className="text-[11px] font-medium uppercase tracking-wide text-ink-500">
                  Platos activos
                </dt>
                <dd className="mt-1 font-display text-xl font-bold text-ink-900">
                  {availableCount}
                </dd>
              </div>
            </dl>
            <p className="mt-4 text-xs text-ink-500">
              {source === "firestore"
                ? "Menú sincronizado en tiempo real con Firestore."
                : "Modo demo: configura Firebase para sincronizar el menú en vivo."}
            </p>
          </div>

          <div className="relative mx-auto w-full max-w-md">
            <div className="absolute -left-6 top-8 h-24 w-24 rounded-full bg-brand-200/60 blur-2xl" />
            <div className="absolute -right-4 bottom-6 h-32 w-32 rounded-full bg-emerald-200/50 blur-2xl" />
            <div className="relative rounded-[2.5rem] border border-white/60 bg-white/80 p-6 shadow-card backdrop-blur">
              <div className="grid h-64 place-items-center rounded-[2rem] bg-gradient-to-br from-brand-100 via-amber-50 to-emerald-100 text-[7rem]">
                🍛
              </div>
              <div className="mt-5 flex items-center justify-between">
                <div>
                  <p className="font-display text-lg font-bold text-ink-900">
                    Bandeja paisa
                  </p>
                  <p className="text-xs text-ink-500">El plato insignia de la casa</p>
                </div>
                <p className="font-bold text-brand-700">{formatCOP(38900)}</p>
              </div>
              <div className="mt-4 flex items-center gap-2 rounded-xl bg-emerald-50 px-3 py-2 text-xs font-medium text-emerald-800">
                <span className="grid h-5 w-5 place-items-center rounded-full bg-emerald-600 text-[10px] text-white">
                  ✓
                </span>
                Pedido confirmado · llega a la cocina al instante
              </div>
            </div>
            <div className="absolute -left-4 bottom-16 rotate-[-6deg] rounded-2xl border border-stone-200 bg-white px-3 py-2 text-xs font-semibold shadow-card">
              ⭐ 4.8 · +1.200 pedidos
            </div>
          </div>
        </div>
      </section>

      <section className="mx-auto max-w-6xl px-4 py-16 sm:px-6">
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div>
            <p className="text-xs font-bold uppercase tracking-widest text-brand-700">
              Los favoritos
            </p>
            <h2 className="section-title mt-1">Lo que todos piden</h2>
          </div>
          <Link
            href="/menu"
            className="text-sm font-semibold text-brand-700 hover:underline"
          >
            Ver menú completo →
          </Link>
        </div>
        <div className="mt-8 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {featured.map((item) => (
            <MenuItemCard key={item.id} item={item} />
          ))}
        </div>
      </section>

      <section className="border-y border-stone-200 bg-white">
        <div className="mx-auto max-w-6xl px-4 py-16 sm:px-6">
          <div className="text-center">
            <p className="text-xs font-bold uppercase tracking-widest text-brand-700">
              Explora
            </p>
            <h2 className="section-title mt-1">Un menú para cada antojo</h2>
            <p className="mx-auto mt-3 max-w-2xl text-sm leading-relaxed text-ink-500">
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
                  className="group rounded-2xl border border-stone-200 bg-stone-50 p-5 transition hover:-translate-y-0.5 hover:border-brand-300 hover:bg-brand-50"
                >
                  <span className="text-4xl">{category.emoji}</span>
                  <h3 className="mt-3 font-display text-lg font-bold text-ink-900">
                    {category.name}
                  </h3>
                  <p className="mt-1 line-clamp-2 text-xs leading-relaxed text-ink-500">
                    {category.description}
                  </p>
                  <p className="mt-3 text-xs font-semibold text-brand-700">
                    {count} platos · Ver →
                  </p>
                </Link>
              );
            })}
          </div>
        </div>
      </section>

      <section className="mx-auto max-w-6xl px-4 py-16 sm:px-6">
        <div className="grid gap-8 rounded-3xl border border-stone-200 bg-white p-8 sm:p-10 lg:grid-cols-3">
          <div>
            <p className="text-xs font-bold uppercase tracking-widest text-brand-700">
              Así funciona
            </p>
            <h2 className="section-title mt-1 text-2xl sm:text-3xl">
              Pedir es muy fácil
            </h2>
            <p className="mt-3 text-sm leading-relaxed text-ink-500">
              Sin registros ni complicaciones. Elige, confirma y nosotros nos
              encargamos del resto.
            </p>
          </div>
          <ol className="grid gap-5 sm:grid-cols-3 lg:col-span-2">
            {[
              {
                step: "1",
                title: "Elige tus platos",
                text: "Explora el menú por categorías y agrega al carrito.",
                icon: "📋",
              },
              {
                step: "2",
                title: "Confirma el pedido",
                text: "Dinos tu nombre, teléfono y cómo quieres recibirlo.",
                icon: "✅",
              },
              {
                step: "3",
                title: "Disfruta",
                text: "La cocina recibe tu pedido al instante y lo prepara.",
                icon: "🍽️",
              },
            ].map((item) => (
              <li key={item.step} className="rounded-2xl bg-stone-50 p-4">
                <span className="grid h-9 w-9 place-items-center rounded-full bg-brand-600 text-sm font-bold text-white">
                  {item.step}
                </span>
                <p className="mt-3 text-xl">{item.icon}</p>
                <h3 className="mt-1 font-semibold text-ink-900">{item.title}</h3>
                <p className="mt-1 text-xs leading-relaxed text-ink-500">
                  {item.text}
                </p>
              </li>
            ))}
          </ol>
        </div>
      </section>

      <section className="mx-auto max-w-6xl px-4 pb-8 sm:px-6">
        <div className="relative overflow-hidden rounded-3xl bg-ink-900 px-8 py-12 text-center text-white sm:px-12">
          <div className="absolute -right-10 -top-10 h-40 w-40 rounded-full bg-brand-500/20 blur-2xl" />
          <div className="absolute -bottom-16 -left-10 h-48 w-48 rounded-full bg-emerald-500/20 blur-2xl" />
          <h2 className="relative font-display text-3xl font-bold sm:text-4xl">
            ¿Hambre? Tu mesa o domicilio te espera.
          </h2>
          <p className="relative mx-auto mt-3 max-w-xl text-sm text-stone-300">
            Abrimos todos los días de {siteConfig.hours}. Haz tu pedido en línea
            o escríbenos por WhatsApp.
          </p>
          <div className="relative mt-6 flex flex-wrap justify-center gap-3">
            <Link href="/menu" className="btn-primary">
              Pedir ahora
            </Link>
            <a
              href={whatsappUrl()}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center justify-center rounded-full border border-white/20 px-6 py-3 text-sm font-semibold text-white transition hover:bg-white/10"
            >
              WhatsApp
            </a>
          </div>
        </div>
      </section>
    </>
  );
}
