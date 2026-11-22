"use client";

import { useMemo, useState } from "react";
import { MenuItemCard } from "./MenuItemCard";
import { searchMenuItems } from "@/lib/menu";
import type { Category, MenuItem } from "@/lib/types";

interface Props {
  categories: Category[];
  items: MenuItem[];
  initialQuery?: string;
}

export function MenuBrowser({ categories, items, initialQuery = "" }: Props) {
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
      <div className="sticky top-16 z-30 -mx-4 mb-8 border-b border-stone-200 bg-stone-50/95 px-4 py-3 backdrop-blur sm:mx-0 sm:rounded-2xl sm:border sm:px-4">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
          <label className="relative flex-1">
            <span className="sr-only">Buscar en el menú</span>
            <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-ink-500">
              🔍
            </span>
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Buscar plato, ingrediente..."
              className="w-full rounded-full border border-stone-300 bg-white py-2.5 pl-9 pr-4 text-sm outline-none transition focus:border-brand-500 focus:ring-2 focus:ring-brand-200"
            />
          </label>
          <div className="flex gap-2 overflow-x-auto pb-1 sm:pb-0">
            <button
              type="button"
              onClick={() => setActiveCategory("all")}
              className={`whitespace-nowrap rounded-full px-3.5 py-2 text-xs font-semibold transition ${
                activeCategory === "all"
                  ? "bg-ink-900 text-white"
                  : "bg-white text-ink-700 hover:bg-brand-100"
              }`}
            >
              Todo
            </button>
            {categories.map((category) => (
              <button
                key={category.id}
                type="button"
                onClick={() => setActiveCategory(category.slug)}
                className={`whitespace-nowrap rounded-full px-3.5 py-2 text-xs font-semibold transition ${
                  activeCategory === category.slug
                    ? "bg-ink-900 text-white"
                    : "bg-white text-ink-700 hover:bg-brand-100"
                }`}
              >
                {category.emoji} {category.name}
              </button>
            ))}
          </div>
        </div>
        <p className="mt-2 text-xs text-ink-500" aria-live="polite">
          {visible.length} producto{visible.length === 1 ? "" : "s"} encontrado
          {visible.length === 1 ? "" : "s"}
        </p>
      </div>

      {visible.length === 0 ? (
        <div className="rounded-2xl border border-dashed border-stone-300 bg-white p-12 text-center">
          <p className="text-4xl">🕵️</p>
          <p className="mt-3 font-semibold text-ink-900">
            No encontramos platos con esa búsqueda
          </p>
          <p className="mt-1 text-sm text-ink-500">
            Prueba con otro nombre o revisa todas las categorías.
          </p>
          <button
            type="button"
            onClick={() => {
              setQuery("");
              setActiveCategory("all");
            }}
            className="mt-4 rounded-full bg-brand-600 px-4 py-2 text-sm font-semibold text-white hover:bg-brand-700"
          >
            Ver todo el menú
          </button>
        </div>
      ) : grouped ? (
        <div className="space-y-12">
          {grouped.map(({ category, items: categoryItems }) => (
            <section key={category.id} id={category.slug} className="scroll-mt-32">
              <div className="mb-4 flex items-end justify-between gap-3">
                <div>
                  <h2 className="font-display text-2xl font-bold text-ink-900">
                    {category.emoji} {category.name}
                  </h2>
                  <p className="mt-1 text-sm text-ink-500">{category.description}</p>
                </div>
                <span className="hidden text-xs font-medium text-ink-500 sm:block">
                  {categoryItems.length} platos
                </span>
              </div>
              <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
                {categoryItems.map((item) => (
                  <MenuItemCard key={item.id} item={item} />
                ))}
              </div>
            </section>
          ))}
        </div>
      ) : (
        <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {visible.map((item) => (
            <MenuItemCard key={item.id} item={item} />
          ))}
        </div>
      )}
    </div>
  );
}
