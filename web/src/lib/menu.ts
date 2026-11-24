import { cache } from "react";
import { demoIngredientStocks, demoRecipes, seedCategories, seedMenuItems } from "./seed";
import { slugify } from "./format";
import {
  getDocument,
  isFirestoreConfigured,
  listDocuments,
  setDocument,
} from "./firebase/rest";
import type { Category, MenuItem, MenuItemStatus, RecipeIngredient } from "./types";

const VALID_STATUS: MenuItemStatus[] = ["available", "unavailable", "limited"];
const WRITABLE_STATUS: MenuItemStatus[] = ["available", "unavailable"];

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

function asRecipe(value: unknown): RecipeIngredient[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => {
      if (!entry || typeof entry !== "object") return null;
      const row = entry as Record<string, unknown>;
      const ingredientId = asString(row.ingredientId);
      const quantity = asNumber(row.quantity);
      if (!ingredientId || quantity <= 0) return null;
      return { ingredientId, quantity };
    })
    .filter((entry): entry is RecipeIngredient => entry !== null);
}

function computeMaxServings(
  recipe: RecipeIngredient[],
  stocks: Map<string, number> | null,
): number | null {
  if (!stocks || recipe.length === 0) return null;
  let max = Number.POSITIVE_INFINITY;
  for (const line of recipe) {
    const stock = stocks.get(line.ingredientId);
    if (stock === undefined) continue;
    const canMake = stock <= 0 ? 0 : Math.floor(stock / line.quantity);
    if (canMake < max) max = canMake;
  }
  if (!Number.isFinite(max)) return null;
  return Math.max(0, max);
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
  stocks: Map<string, number> | null = null,
): MenuItem {
  const name = asString(doc.data.name, "Plato");
  const categoryId = asString(doc.data.categoryId);
  const category = categories.find((entry) => entry.id === categoryId);
  const rawStatus = asString(doc.data.status, "available") as MenuItemStatus;
  const recipe = asRecipe(doc.data.recipe);
  const maxServings = computeMaxServings(recipe, stocks);
  const status = VALID_STATUS.includes(rawStatus) ? rawStatus : "available";
  return {
    id: doc.id,
    name,
    slug: asString(doc.data.slug, slugify(name)),
    description: asString(doc.data.description),
    price: asNumber(doc.data.price),
    categoryId,
    categorySlug: category?.slug ?? asString(doc.data.categorySlug, "otros"),
    status:
      status === "unavailable"
        ? status
        : maxServings === 0
          ? "unavailable"
          : status,
    ingredients: asStringArray(doc.data.ingredients),
    allergens: asStringArray(doc.data.allergens),
    emoji: asString(doc.data.emoji, "🍽️"),
    featured: doc.data.featured === true,
    prepMinutes: asNumber(doc.data.prepMinutes, 15),
    calories: asNumber(doc.data.calories),
    sku: asString(doc.data.sku),
    imageUrl: asString(doc.data.imageUrl),
    videoUrl: asString(doc.data.videoUrl),
    recipe,
    maxServings,
  };
}

export interface MenuData {
  categories: Category[];
  items: MenuItem[];
  source: "firestore" | "demo";
}

function seedMenu(): MenuData {
  const stocks = new Map(Object.entries(demoIngredientStocks));
  const items = seedMenuItems.map((item) => {
    const recipe = item.recipe ?? demoRecipes[item.id] ?? [];
    const maxServings = computeMaxServings(recipe, stocks);
    return {
      ...item,
      recipe,
      maxServings,
      status:
        item.status === "unavailable"
          ? item.status
          : maxServings === 0
            ? "unavailable"
            : item.status,
    };
  });
  return {
    categories: [...seedCategories].sort((a, b) => a.order - b.order),
    items: items.sort((a, b) => a.name.localeCompare(b.name)),
    source: "demo",
  };
}

async function loadMenu(): Promise<MenuData> {
  if (!isFirestoreConfigured()) return seedMenu();
  try {
    const [categories, ingredientDocs] = await Promise.all([
      listDocuments("categories", mapCategory, 30),
      listDocuments(
        "ingredients",
        (doc) => ({
          id: doc.id,
          stock: asNumber(doc.data.stock, 0),
        }),
        0,
      ).catch(() => []),
    ]);
    const stocks =
      ingredientDocs.length > 0
        ? new Map(ingredientDocs.map((i) => [i.id, i.stock]))
        : null;
    const items = await listDocuments(
      "menuItems",
      (doc) => mapMenuItem(doc, categories, stocks),
      0,
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

export type WritableMenuItemStatus = Extract<
  MenuItemStatus,
  "available" | "unavailable"
>;

/** Actualiza el estado real del plato en Firestore (catálogo compartido). */
export async function setMenuItemStatus(
  id: string,
  status: unknown,
): Promise<{ id: string; status: WritableMenuItemStatus } | null> {
  const documentId = id.trim();
  if (!documentId || !WRITABLE_STATUS.includes(status as WritableMenuItemStatus)) {
    return null;
  }
  if (!isFirestoreConfigured()) return null;

  const next = status as WritableMenuItemStatus;
  const existing = await getDocument<Record<string, unknown>>(
    "menuItems",
    documentId,
    0,
  );
  if (!existing) return null;

  await setDocument("menuItems", documentId, { status: next });
  return { id: documentId, status: next };
}

export function isAvailable(menuItem: MenuItem): boolean {
  return menuItem.status !== "unavailable";
}

/** Catálogo público: los platos agotados nunca se muestran ni se indexan. */
export const getPublicMenu = cache(async (): Promise<MenuData> => {
  const menu = await getMenu();
  return { ...menu, items: menu.items.filter(isAvailable) };
});

export async function getMenuItemBySlug(slug: string): Promise<MenuItem | null> {
  const { items } = await getPublicMenu();
  return items.find((item) => item.slug === slug) ?? null;
}

export async function getFeaturedItems(limit = 6): Promise<MenuItem[]> {
  const { items } = await getPublicMenu();
  const featured = items.filter((item) => item.featured);
  const pool = featured.length >= limit ? featured : items;
  return pool.slice(0, limit);
}

export async function getItemsByCategory(slug: string): Promise<MenuItem[]> {
  const { items } = await getPublicMenu();
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
