import { cache } from "react";
import { getDemoState } from "./demo-store";
import { demoIngredientStocks, demoRecipes, seedCategories, seedMenuItems } from "./seed";
import { slugify } from "./format";
import {
  getDocument,
  isFirestoreConfigured,
  listDocuments,
  setDocument,
  tenantPath,
} from "./firebase/rest";
import { DEFAULT_TENANT_ID, isDemoTenant } from "./tenants";
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
    // Si el documento del insumo no existe, el plato está agotado: tratarlo
    // como "sin límite" permitiría vender más de lo que se puede preparar.
    const stock = stocks.get(line.ingredientId) ?? 0;
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

function seedMenu(tenantId = DEFAULT_TENANT_ID): MenuData {
  const demo = isDemoTenant(tenantId)
    ? getDemoState(tenantId)
    : {
        categories: seedCategories,
        items: seedMenuItems,
        stocks: demoIngredientStocks,
        recipes: demoRecipes,
      };
  const stocks = new Map(Object.entries(demo.stocks));
  const items = demo.items.map((item) => {
    const recipe = item.recipe ?? demo.recipes[item.id] ?? [];
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
    categories: [...demo.categories].sort((a, b) => a.order - b.order),
    items: items.sort((a, b) => a.name.localeCompare(b.name)),
    source: "demo",
  };
}

async function loadMenu(tenantId = DEFAULT_TENANT_ID): Promise<MenuData> {
  if (!isFirestoreConfigured()) {
    return seedMenu(tenantId);
  }
  try {
    const [categories, ingredientDocs] = await Promise.all([
      listDocuments(tenantPath(tenantId, "categories"), mapCategory, 30),
      listDocuments(
        tenantPath(tenantId, "ingredients"),
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
      tenantPath(tenantId, "menuItems"),
      (doc) => mapMenuItem(doc, categories, stocks),
      0,
    );
    if (categories.length === 0 || items.length === 0) return seedMenu(tenantId);
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
    return seedMenu(tenantId);
  }
}

export const getMenu = cache(loadMenu);

export type WritableMenuItemStatus = Extract<
  MenuItemStatus,
  "available" | "unavailable"
>;

export type MenuStatusReason = "manual" | "ingredients";

type DemoItemStatus = MenuItem & {
  manualStatus?: "unavailable" | null;
  statusReason?: MenuStatusReason | null;
};

/**
 * Actualiza el estado real del plato en Firestore (catálogo compartido).
 *
 * `manual = true` fija un bloqueo que el trigger de stock no puede levantar.
 * `reason` distingue un toggle manual de un agotamiento calculado por stock.
 * Al marcar «Disponible» se limpia el bloqueo y se guarda el estado que
 * realmente permiten los insumos.
 */
export async function setMenuItemStatus(
  id: string,
  status: unknown,
  manual = status === "unavailable",
  reason: MenuStatusReason = "manual",
  tenantId = DEFAULT_TENANT_ID,
): Promise<{ id: string; status: WritableMenuItemStatus } | null> {
  const documentId = id.trim();
  if (!documentId || !WRITABLE_STATUS.includes(status as WritableMenuItemStatus)) {
    return null;
  }

  if (!isFirestoreConfigured()) {
    const state = getDemoState(tenantId);
    const item = state.items.find((entry) => entry.id === documentId);
    if (!item) return null;
    const recipe = item.recipe ?? state.recipes[item.id] ?? [];
    const stocks = new Map(Object.entries(state.stocks));
    const servings = computeMaxServings(recipe, stocks);
    let next = status as WritableMenuItemStatus;
    if (next === "available" && recipe.length > 0 && servings === 0) {
      next = "unavailable";
    }
    item.status = next;
    item.maxServings = servings;
    const detail = item as DemoItemStatus;
    detail.manualStatus = next === "unavailable" && manual ? "unavailable" : null;
    detail.statusReason = next === "unavailable" && servings === 0
      ? "ingredients"
      : reason;
    return { id: documentId, status: next };
  }

  if (!isFirestoreConfigured()) return null;

  const requested = status as WritableMenuItemStatus;
  const existing = await getDocument<Record<string, unknown>>(
    tenantPath(tenantId, "menuItems"),
    documentId,
    0,
  );
  if (!existing) return null;

  let next = requested;
  const nextManual =
    requested === "unavailable" && manual ? "unavailable" : null;
  const patch: Record<string, unknown> = {
    status: next,
    manualStatus: nextManual,
    statusReason: reason,
    statusUpdatedAt: new Date().toISOString(),
  };

  if (requested === "available") {
    const recipe = asRecipe(existing.recipe);
    if (recipe.length > 0) {
      try {
        const ingredients = await listDocuments(
          tenantPath(tenantId, "ingredients"),
          (doc) => ({
            id: doc.id,
            stock: asNumber(doc.data.stock, 0),
          }),
          0,
        );
        const stocks = new Map(
          ingredients.map((ingredient) => [ingredient.id, ingredient.stock]),
        );
        if (computeMaxServings(recipe, stocks) === 0) next = "unavailable";
      } catch (error) {
        console.warn("[menu] No se pudo validar stock al disponibilizar:", error);
      }
    }
    patch.status = next;
    patch.statusReason = next === "unavailable" ? "ingredients" : reason;
  }

  // La app reenvía el mismo estado en cada reconciliación. Solo cambiar
  // `statusUpdatedAt` cuando el estado efectivo cambia evita reescrituras
  // constantes del documento (y ruido en el trigger de Firestore).
  const currentStatus = asString(existing.status);
  const currentManual =
    existing.manualStatus === "unavailable" ? "unavailable" : null;
  const currentReason =
    existing.statusReason === "ingredients" ||
    existing.statusReason === "manual"
      ? existing.statusReason
      : null;
  if (
    next === currentStatus &&
    nextManual === currentManual &&
    patch.statusReason === currentReason
  ) {
    return { id: documentId, status: next };
  }

  await setDocument(tenantPath(tenantId, "menuItems"), documentId, patch);
  return { id: documentId, status: next };
}

/**
 * Escribe en Firestore el estado derivado del stock para todos los platos.
 * Equivale al trigger `onDocumentWritten('ingredients/{id}')` y permite que la
 * reconciliación funcione aunque el despliegue de Functions esté limitado.
 * Respeta los bloqueos manuales (`manualStatus: "unavailable"`).
 */
export async function syncMenuStatusesFromStock(
  tenantId = DEFAULT_TENANT_ID,
): Promise<string[]> {
  if (!isFirestoreConfigured()) {
    const state = getDemoState(tenantId);
    const stocks = new Map(Object.entries(state.stocks));
    const updated: string[] = [];
    for (const item of state.items) {
      const detail = item as DemoItemStatus;
      if (detail.manualStatus === "unavailable") continue;
      const recipe = item.recipe ?? state.recipes[item.id] ?? [];
      const next = computeMaxServings(recipe, stocks) === 0
        ? "unavailable"
        : "available";
      if (item.status === next) continue;
      item.status = next;
      detail.statusReason = "ingredients";
      updated.push(item.id);
    }
    return updated;
  }
  if (!isFirestoreConfigured()) return [];
  const [ingredients, items] = await Promise.all([
    listDocuments(
      tenantPath(tenantId, "ingredients"),
      (doc) => ({ id: doc.id, stock: asNumber(doc.data.stock, 0) }),
      0,
    ),
    listDocuments(
      tenantPath(tenantId, "menuItems"),
      (doc) => ({
        id: doc.id,
        status: asString(doc.data.status, "available"),
        manualStatus:
          doc.data.manualStatus === "unavailable" ? "unavailable" : null,
        recipe: asRecipe(doc.data.recipe),
      }),
      0,
    ),
  ]);
  const stocks = new Map(
    ingredients.map((ingredient) => [ingredient.id, ingredient.stock]),
  );
  const updatedAt = new Date().toISOString();
  const updated: string[] = [];
  for (const item of items) {
    if (item.manualStatus === "unavailable") continue;
    const next =
      computeMaxServings(item.recipe, stocks) === 0
        ? "unavailable"
        : "available";
    if (item.status === next) continue;
    await setDocument(tenantPath(tenantId, "menuItems"), item.id, {
      status: next,
      statusReason: "ingredients",
      statusUpdatedAt: updatedAt,
    });
    updated.push(item.id);
  }
  return updated;
}

/** Un plato sin insumos no es vendible aunque su estado manual diga lo contrario. */
export function isSoldOutByIngredients(menuItem: MenuItem): boolean {
  return menuItem.maxServings === 0;
}

export function isAvailable(menuItem: MenuItem): boolean {
  return menuItem.status !== "unavailable" && !isSoldOutByIngredients(menuItem);
}

/** Catálogo público: los platos agotados nunca se muestran ni se indexan. */
export const getPublicMenu = cache(
  async (tenantId = DEFAULT_TENANT_ID): Promise<MenuData> => {
    const menu = await getMenu(tenantId);
    return { ...menu, items: menu.items.filter(isAvailable) };
  },
);

export async function getMenuItemBySlug(
  slug: string,
  tenantId = DEFAULT_TENANT_ID,
): Promise<MenuItem | null> {
  const { items } = await getPublicMenu(tenantId);
  return items.find((item) => item.slug === slug) ?? null;
}

export async function getFeaturedItems(
  limit = 6,
  tenantId = DEFAULT_TENANT_ID,
): Promise<MenuItem[]> {
  const { items } = await getPublicMenu(tenantId);
  const featured = items.filter((item) => item.featured);
  const pool = featured.length >= limit ? featured : items;
  return pool.slice(0, limit);
}

/** Favoritos marcados desde la APK; nunca rellena con otros platos. */
export async function getFavoriteItems(
  limit = 12,
  tenantId = DEFAULT_TENANT_ID,
): Promise<MenuItem[]> {
  const { items } = await getPublicMenu(tenantId);
  return items.filter((item) => item.featured).slice(0, limit);
}

/** Marca/desmarca el campo «Favorito» compartido con la app administrativa. */
export async function setMenuItemFeatured(
  id: string,
  featured: boolean,
  tenantId = DEFAULT_TENANT_ID,
): Promise<{ id: string; featured: boolean } | null> {
  const documentId = id.trim();
  if (!documentId || typeof featured !== "boolean") return null;
  if (!isFirestoreConfigured()) {
    const item = getDemoState(tenantId).items.find((entry) => entry.id === documentId);
    if (!item) return null;
    item.featured = featured;
    return { id: documentId, featured };
  }
  if (!isFirestoreConfigured()) return null;
  const existing = await getDocument<Record<string, unknown>>(
    tenantPath(tenantId, "menuItems"),
    documentId,
    0,
  );
  if (!existing) return null;
  if (existing.featured === featured) return { id: documentId, featured };
  await setDocument(tenantPath(tenantId, "menuItems"), documentId, { featured });
  return { id: documentId, featured };
}

export async function getItemsByCategory(
  slug: string,
  tenantId = DEFAULT_TENANT_ID,
): Promise<MenuItem[]> {
  const { items } = await getPublicMenu(tenantId);
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
