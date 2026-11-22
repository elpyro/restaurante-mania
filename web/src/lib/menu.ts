import { cache } from "react";
import { seedCategories, seedMenuItems } from "./seed";
import { slugify } from "./format";
import { isFirestoreConfigured, listDocuments } from "./firebase/rest";
import type { Category, MenuItem, MenuItemStatus } from "./types";

const VALID_STATUS: MenuItemStatus[] = ["available", "unavailable", "limited"];

function asString(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

function asNumber(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function asStringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((entry): entry is string => typeof entry === "string")
    : [];
}

function mapCategory(doc: { id: string; data: Record<string, unknown> }): Category {
  const name = asString(doc.data.name, "Categoría");
  return {
    id: doc.id,
    name,
    slug: asString(doc.data.slug, slugify(name)),
    description: asString(doc.data.description),
    order: asNumber(doc.data.order, 99),
    emoji: asString(doc.data.emoji, "🍽️"),
  };
}

function mapMenuItem(
  doc: { id: string; data: Record<string, unknown> },
  categories: Category[],
): MenuItem {
  const name = asString(doc.data.name, "Plato");
  const categoryId = asString(doc.data.categoryId);
  const category = categories.find((entry) => entry.id === categoryId);
  const rawStatus = asString(doc.data.status, "available") as MenuItemStatus;
  return {
    id: doc.id,
    name,
    slug: asString(doc.data.slug, slugify(name)),
    description: asString(doc.data.description),
    price: asNumber(doc.data.price),
    categoryId,
    categorySlug: category?.slug ?? asString(doc.data.categorySlug, "otros"),
    status: VALID_STATUS.includes(rawStatus) ? rawStatus : "available",
    ingredients: asStringArray(doc.data.ingredients),
    allergens: asStringArray(doc.data.allergens),
    emoji: asString(doc.data.emoji, "🍽️"),
    featured: doc.data.featured === true,
    prepMinutes: asNumber(doc.data.prepMinutes, 15),
    calories: asNumber(doc.data.calories),
    sku: asString(doc.data.sku),
    imageUrl: asString(doc.data.imageUrl),
    videoUrl: asString(doc.data.videoUrl),
  };
}

export interface MenuData {
  categories: Category[];
  items: MenuItem[];
  source: "firestore" | "demo";
}

function seedMenu(): MenuData {
  return {
    categories: [...seedCategories].sort((a, b) => a.order - b.order),
    items: [...seedMenuItems].sort((a, b) => a.name.localeCompare(b.name)),
    source: "demo",
  };
}

async function loadMenu(): Promise<MenuData> {
  if (!isFirestoreConfigured()) return seedMenu();
  try {
    const categories = await listDocuments("categories", mapCategory);
    const items = await listDocuments("menuItems", (doc) =>
      mapMenuItem(doc, categories),
    );
    if (categories.length === 0 || items.length === 0) return seedMenu();
    categories.sort((a, b) => a.order - b.order);
    const categoryOrder = new Map(
      categories.map((category, index) => [category.id, index]),
    );
    items.sort((a, b) => {
      const byCategory =
        (categoryOrder.get(a.categoryId) ?? 99) -
        (categoryOrder.get(b.categoryId) ?? 99);
      return byCategory !== 0 ? byCategory : a.name.localeCompare(b.name);
    });
    return { categories, items, source: "firestore" };
  } catch (error) {
    console.warn("[menu] Firestore no disponible, usando datos demo:", error);
    return seedMenu();
  }
}

export const getMenu = cache(loadMenu);

export async function getMenuItemBySlug(slug: string): Promise<MenuItem | null> {
  const { items } = await getMenu();
  return items.find((item) => item.slug === slug) ?? null;
}

export async function getFeaturedItems(limit = 6): Promise<MenuItem[]> {
  const { items } = await getMenu();
  const featured = items.filter(
    (item) => item.featured && item.status !== "unavailable",
  );
  const pool = featured.length >= limit ? featured : items;
  return pool.slice(0, limit);
}

export async function getItemsByCategory(slug: string): Promise<MenuItem[]> {
  const { items } = await getMenu();
  return items.filter((item) => item.categorySlug === slug);
}

export function searchMenuItems(items: MenuItem[], query: string): MenuItem[] {
  const normalized = query
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
  if (!normalized) return items;
  return items.filter((item) =>
    `${item.name} ${item.description} ${item.ingredients.join(" ")}`
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .includes(normalized),
  );
}
