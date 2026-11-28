"use client";

import { useMemo, useState } from "react";
import { ArrowRight, Search, SlidersHorizontal, X } from "lucide-react";
import { MenuItemCard } from "./MenuItemCard";
import { searchMenuItems } from "@/lib/menu";
import type { Category, MenuItem } from "@/lib/types";

interface Props {
  categories: Category[];
  items: MenuItem[];
  tenantId: string;
  initialQuery?: string;
}

export function MenuBrowser({
  categories,
  items,
  tenantId,
  initialQuery = "",
}: Props) {
  const [query, setQuery] = useState(initialQuery);
  const [activeCategory, setActiveCategory] = useState<string>("all");

  const visible = useMemo(() => {
    const byCategory =
      activeCategory === "all"
        ? items
        : items.filter((item) => item.categorySlug === activeCategory);
    return searchMenuItems(byCategory, query);
  }, [items, activeCategory, query]);

  const grouped = useMemo(() => {
    if (activeCategory !== "all" || query.trim()) return null;
    return categories
      .map((category) => ({
        category,
        items: items.filter((item) => item.categoryId === category.id),
      }))
      .filter((group) => group.items.length > 0);
  }, [categories, items, activeCategory, query]);

  return (
    <div>
      <div className="sticky top-[4.5rem] z-30 -mx-4 mb-10 border-y border-line bg-surface/95 px-4 py-4 backdrop-blur-xl sm:mx-0 sm:rounded-3xl sm:border">
        <div className="flex flex-col gap-3 lg:flex-row lg:items-center">
          <label className="relative flex-1">
            <span className="sr-only">Buscar en el menú</span>
            <Search
              size={17}
              className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 text-ink-muted"
              aria-hidden
            />
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Buscar plato, ingrediente..."
              className="field rounded-full py-3 pl-11 pr-10"
            />
            {query ? (
              <button
                type="button"
                onClick={() => setQuery("")}
                className="absolute right-3 top-1/2 grid h-7 w-7 -translate-y-1/2 place-items-center rounded-full text-ink-muted transition hover:bg-surface-muted hover:text-ink"
                aria-label="Limpiar búsqueda"
              >
                <X size={15} />
              </button>
            ) : null}
          </label>
          <div className="flex items-center gap-2 overflow-x-auto pb-1 lg:pb-0">
            <span className="hidden shrink-0 text-ink-muted sm:block" aria-hidden>
              <SlidersHorizontal size={17} />
            </span>
            <button
              type="button"
              onClick={() => setActiveCategory("all")}
              aria-pressed={activeCategory === "all"}
              className={`whitespace-nowrap rounded-full px-4 py-2 text-xs font-semibold transition ${
                activeCategory === "all"
                  ? "bg-ink text-surface"
                  : "bg-surface-raised text-ink-soft hover:bg-brand-50 hover:text-brand-strong"
              }`}
            >
              Todo
            </button>
            {categories.map((category) => (
              <button
                key={category.id}
                type="button"
                onClick={() => setActiveCategory(category.slug)}
                aria-pressed={activeCategory === category.slug}
                className={`whitespace-nowrap rounded-full px-4 py-2 text-xs font-semibold transition ${
                  activeCategory === category.slug
                    ? "bg-ink text-surface"
                    : "bg-surface-raised text-ink-soft hover:bg-brand-50 hover:text-brand-strong"
                }`}
              >
                {category.emoji} {category.name}
              </button>
            ))}
          </div>
        </div>
        <p className="mt-2 text-xs text-ink-muted" aria-live="polite">
          {visible.length} producto{visible.length === 1 ? "" : "s"} encontrado
          {visible.length === 1 ? "" : "s"}
        </p>
      </div>

      {visible.length === 0 ? (
        <div className="surface-card border-dashed p-12 text-center">
          <p className="text-4xl" aria-hidden>🕵️</p>
          <p className="mt-3 font-semibold text-ink">
            No encontramos platos con esa búsqueda
          </p>
          <p className="mt-1 text-sm text-ink-muted">
            Prueba con otro nombre o revisa todas las categorías.
          </p>
          <button
            type="button"
            onClick={() => {
              setQuery("");
              setActiveCategory("all");
            }}
            className="btn-primary mt-5"
          >
            Ver todo el menú <ArrowRight size={15} aria-hidden />
          </button>
        </div>
      ) : grouped ? (
        <div className="space-y-14">
          {grouped.map(({ category, items: categoryItems }) => (
            <section key={category.id} id={category.slug} className="scroll-mt-36">
              <div className="mb-5 flex items-end justify-between gap-3">
                <div>
                  <h2 className="font-display text-2xl font-bold text-ink">
                    {category.emoji} {category.name}
                  </h2>
                  <p className="mt-1 text-sm text-ink-muted">{category.description}</p>
                </div>
                <span className="hidden text-xs font-medium text-ink-muted sm:block">
                  {categoryItems.length} platos
                </span>
              </div>
              <div className="grid grid-cols-2 gap-3 sm:gap-5 lg:grid-cols-3">
                {categoryItems.map((item) => (
                  <MenuItemCard key={item.id} item={item} tenantId={tenantId} />
                ))}
              </div>
            </section>
          ))}
        </div>
      ) : (
        <div className="grid grid-cols-2 gap-3 sm:gap-5 lg:grid-cols-3">
          {visible.map((item) => (
            <MenuItemCard key={item.id} item={item} tenantId={tenantId} />
          ))}
        </div>
      )}
    </div>
  );
}
