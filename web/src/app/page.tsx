import Image from "next/image";
import Link from "next/link";
import { ArrowRight, MessageCircle, Sparkles, UtensilsCrossed } from "lucide-react";

import { RestaurantPicker } from "@/components/RestaurantPicker";
import { getTenantDirectory } from "@/lib/tenant-directory";

export const dynamic = "force-dynamic";

const SOFTWARE_WHATSAPP =
  "https://wa.me/5731258666072?text=" +
  encodeURIComponent("Hola, quiero información sobre Software Manía");

export default async function LandingPage() {
  const tenants = await getTenantDirectory();

  return (
    <main className="relative isolate overflow-hidden">
      <div className="pointer-events-none absolute -left-24 top-0 -z-10 h-96 w-96 rounded-full bg-brand-200/40 blur-3xl" />
      <div className="pointer-events-none absolute -right-24 top-40 -z-10 h-96 w-96 rounded-full bg-accent-soft/70 blur-3xl" />

      <section className="mx-auto max-w-6xl px-4 pb-12 pt-14 sm:px-6 sm:pt-20">
        <div className="flex flex-col items-center text-center">
          <Image
            src="/rm-logo.png"
            alt="Logo de Restaurante Manía"
            width={96}
            height={96}
            priority
            unoptimized
            className="h-24 w-24 rounded-3xl border border-line bg-surface-raised object-contain p-2 shadow-card"
          />
          <span className="chip mt-6 border border-brand-200 bg-surface-raised/80 text-brand-strong">
            <Sparkles size={14} aria-hidden /> Pedidos en línea · POS · CRM
          </span>
          <h1 className="mt-5 max-w-3xl font-display text-4xl font-bold leading-[1.1] tracking-tight text-ink sm:text-5xl lg:text-6xl">
            Bienvenido a <span className="text-brand-strong">Restaurante Manía</span>
          </h1>
          <p className="mt-4 max-w-xl text-base leading-relaxed text-ink-muted sm:text-lg">
            Elige un restaurante para empezar y descubre su menú, sus horarios y
            la forma más rápida de hacer tu pedido.
          </p>
        </div>

        <div className="mt-12">
          <RestaurantPicker tenants={tenants} />
        </div>
      </section>

      <section className="border-y border-line bg-surface-raised/60">
        <div className="mx-auto grid max-w-6xl items-center gap-8 px-4 py-14 sm:px-6 lg:grid-cols-[1.15fr_0.85fr]">
          <div>
            <span className="chip border border-accent/30 bg-accent-soft/60 text-brand-strong">
              <UtensilsCrossed size={14} aria-hidden /> Para restaurantes
            </span>
            <h2 className="mt-5 font-display text-3xl font-bold leading-tight text-ink sm:text-4xl">
              Software Manía: tu restaurante, completo y conectado
            </h2>
            <p className="mt-4 max-w-2xl text-sm leading-relaxed text-ink-muted sm:text-base">
              Punto de venta, menú digital, pedidos en línea, inventario, turnos
              y CRM en una sola plataforma. Sincronización en tiempo real para
              que tu cocina, tu salón y tus clientes estén siempre al día.
            </p>
            <a
              href={SOFTWARE_WHATSAPP}
              target="_blank"
              rel="noopener noreferrer"
              className="mt-7 inline-flex items-center gap-2 rounded-full bg-accent px-6 py-3 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 hover:bg-accent-strong"
            >
              <MessageCircle size={17} aria-hidden /> Hablar por WhatsApp
              <ArrowRight size={16} aria-hidden />
            </a>
            <p className="mt-3 text-xs text-ink-muted">
              Escríbenos al +57 312 586 6072 y te contamos cómo empezar.
            </p>
          </div>

          <div className="relative hidden min-h-64 overflow-hidden rounded-4xl border border-line bg-gradient-to-br from-brand via-brand-strong to-ink p-8 text-white shadow-card lg:block">
            <div className="absolute -right-16 -top-16 h-56 w-56 rounded-full bg-white/15 blur-2xl" />
            <div className="absolute -bottom-20 -left-10 h-56 w-56 rounded-full bg-accent/30 blur-2xl" />
            <div className="relative flex h-full flex-col justify-between">
              <span className="text-xs font-semibold uppercase tracking-[0.2em] text-white/80">
                Software Manía
              </span>
              <div>
                <p className="font-display text-2xl font-bold leading-snug">
                  Más pedidos, menos papel, cero desconexiones.
                </p>
                <div className="mt-6 flex flex-wrap gap-2">
                  {["POS", "Menú", "Inventario", "CRM"].map((tag) => (
                    <span
                      key={tag}
                      className="rounded-full border border-white/25 bg-white/10 px-3 py-1 text-xs font-semibold"
                    >
                      {tag}
                    </span>
                  ))}
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section className="mx-auto max-w-6xl px-4 py-12 text-center sm:px-6">
        <Link
          href="/menu"
          className="inline-flex items-center gap-2 text-sm font-semibold text-brand-strong hover:underline"
        >
          Ir directo a Restaurante Manía <ArrowRight size={15} aria-hidden />
        </Link>
      </section>
    </main>
  );
}
