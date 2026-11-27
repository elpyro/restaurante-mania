import Image from "next/image";
import Link from "next/link";
import { ViewTransition } from "react";
import { ArrowUpRight, Clock, Flame } from "lucide-react";
import { AddToCartButton } from "./AddToCartButton";
import { CartQuantityBadge } from "./CartQuantityBadge";
import { formatCOP } from "@/lib/format";
import type { MenuItem } from "@/lib/types";

const statusLabel: Record<MenuItem["status"], string> = {
  available: "Disponible",
  limited: "Últimas unidades",
  unavailable: "Agotado",
};

export function MenuItemCard({ item }: { item: MenuItem }) {
  return (
    <article className="surface-card group flex flex-col overflow-hidden transition duration-300 hover:-translate-y-1 hover:shadow-glow">
      <Link
        href={`/menu/${item.slug}`}
        className="relative block h-44 overflow-hidden bg-gradient-to-br from-brand-100 via-surface to-accent-soft sm:h-56"
        aria-label={`Ver ${item.name}`}
      >
        <ViewTransition name={`dish-${item.slug}`} share="morph" default="none">
          {item.imageUrl ? (
            <Image
              src={item.imageUrl}
              alt={item.name}
              fill
              sizes="(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 33vw"
              className="object-cover object-center transition duration-500 group-hover:scale-105 group-hover:shadow-lg"
            />
          ) : (
            <span className="grid h-full w-full place-items-center text-7xl transition duration-500 group-hover:scale-110">
              {item.emoji}
            </span>
          )}
        </ViewTransition>
        <div className="absolute inset-x-0 bottom-0 h-20 bg-gradient-to-t from-black/35 to-transparent" />
        <CartQuantityBadge menuItemId={item.id} />

        {item.featured ? (
          <span className="absolute left-3 top-3 rounded-full bg-surface-raised/90 px-2.5 py-1 text-[11px] font-bold uppercase tracking-wide text-brand-strong shadow-sm">
            Favorito
          </span>
        ) : null}
        {item.status !== "available" ? (
          <span className="absolute right-3 top-3 rounded-full bg-ink/85 px-2.5 py-1 text-[11px] font-semibold text-surface-raised">
            {statusLabel[item.status]}
          </span>
        ) : null}
      </Link>

      <div className="flex flex-1 flex-col p-3 sm:p-5">
        <div className="flex items-start justify-between gap-3">
          <h3 className="font-display text-base font-bold leading-tight text-ink sm:text-lg">
            <Link
              href={`/menu/${item.slug}`}
              className="transition hover:text-brand-strong"
            >
              {item.name}
            </Link>
          </h3>
          <p className="whitespace-nowrap text-xs font-bold text-brand-strong sm:text-sm">
            {formatCOP(item.price)}
          </p>
        </div>
        <p className="mt-1.5 line-clamp-2 text-xs leading-relaxed text-ink-muted sm:mt-2 sm:text-sm">
          {item.description}
        </p>
        <div className="mt-auto flex items-center justify-between gap-1.5 pt-3 sm:gap-2 sm:pt-5">
          <Link
            href={`/menu/${item.slug}`}
            className="inline-flex items-center gap-0.5 text-[11px] font-semibold text-ink-soft underline-offset-4 transition hover:text-brand-strong hover:underline sm:gap-1 sm:text-xs"
          >
            Ver detalle <ArrowUpRight size={13} aria-hidden />
          </Link>
          <AddToCartButton item={item} />
        </div>
      </div>
    </article>
  );
}
