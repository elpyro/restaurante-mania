import Link from "next/link";
import { AddToCartButton } from "./AddToCartButton";
import { formatCOP } from "@/lib/format";
import type { MenuItem } from "@/lib/types";

const statusLabel: Record<MenuItem["status"], string> = {
  available: "Disponible",
  limited: "Últimas unidades",
  unavailable: "Agotado",
};

export function MenuItemCard({ item }: { item: MenuItem }) {
  return (
    <article className="group flex flex-col overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-sm transition hover:-translate-y-0.5 hover:shadow-card">
      <Link
        href={`/menu/${item.slug}`}
        className="relative grid h-36 place-items-center overflow-hidden bg-gradient-to-br from-brand-100 via-amber-50 to-emerald-50 text-6xl"
        aria-label={`Ver ${item.name}`}
      >
        {item.imageUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={item.imageUrl}
            alt={item.name}
            className="h-full w-full object-cover"
            loading="lazy"
          />
        ) : (
          <span className="transition group-hover:scale-110">{item.emoji}</span>
        )}
        {item.featured ? (
          <span className="absolute left-3 top-3 rounded-full bg-white/85 px-2.5 py-1 text-[11px] font-bold uppercase tracking-wide text-brand-700 shadow-sm">
            Favorito
          </span>
        ) : null}
        {item.status !== "available" ? (
          <span className="absolute right-3 top-3 rounded-full bg-ink-900/80 px-2.5 py-1 text-[11px] font-semibold text-white">
            {statusLabel[item.status]}
          </span>
        ) : null}
      </Link>

      <div className="flex flex-1 flex-col p-4">
        <div className="flex items-start justify-between gap-3">
          <h3 className="font-display text-lg font-bold leading-tight text-ink-900">
            <Link href={`/menu/${item.slug}`} className="hover:text-brand-700">
              {item.name}
            </Link>
          </h3>
          <p className="whitespace-nowrap text-sm font-bold text-brand-700">
            {formatCOP(item.price)}
          </p>
        </div>
        <p className="mt-1.5 line-clamp-2 text-sm leading-relaxed text-ink-500">
          {item.description}
        </p>
        <div className="mt-3 flex items-center gap-2 text-[11px] font-medium text-ink-500">
          <span>⏱ {item.prepMinutes} min</span>
          <span aria-hidden>·</span>
          <span>{item.calories} kcal</span>
        </div>
        <div className="mt-4 flex items-center justify-between gap-2">
          <Link
            href={`/menu/${item.slug}`}
            className="text-xs font-semibold text-ink-500 underline-offset-4 hover:text-brand-700 hover:underline"
          >
            Ver detalle
          </Link>
          <AddToCartButton item={item} />
        </div>
      </div>
    </article>
  );
}
