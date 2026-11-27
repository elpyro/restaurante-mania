/**
 * Estado demo por tenant. Cada instancia nueva tiene sus propios catálogos,
 * stock, pedidos, turnos, visitas, CRM y configuración. Nada de esto se
 * escribe en Firestore.
 */

import {
  DEFAULT_RESTAURANT_CONFIG,
  GENERIC_RESTAURANT_CONFIG,
  type RestaurantConfig,
} from "./restaurant-config";
import {
  genericCategories,
  genericIngredientStocks,
  genericMenuItems,
  genericRecipes,
} from "./generic-template";
import {
  demoIngredientStocks,
  demoRecipes,
  seedCategories,
  seedMenuItems,
} from "./seed";
import {
  DEFAULT_TENANT_ID,
  isKnownTenant,
  isTemplateTenant,
  tenantDefinition,
} from "./tenants";
import type {
  CashShift,
  Category,
  MenuItem,
  Order,
  RecipeIngredient,
} from "./types";

export interface DemoTenantState {
  categories: Category[];
  items: MenuItem[];
  stocks: Record<string, number>;
  recipes: Record<string, RecipeIngredient[]>;
  orders: Map<string, Order>;
  shifts: Map<string, CashShift>;
  visits: Record<string, unknown>[];
  customers: Record<string, unknown>[];
  losses: Record<string, unknown>[];
  config: RestaurantConfig;
}

type DemoGlobal = {
  __restauranteDemoTenants?: Map<string, DemoTenantState>;
};

const globalStore = globalThis as unknown as DemoGlobal;

function clone<T>(value: T): T {
  return structuredClone(value);
}

function buildConfig(tenantId: string): RestaurantConfig {
  const tenant = tenantDefinition(tenantId);
  if (isTemplateTenant(tenantId)) {
    return {
      ...clone(GENERIC_RESTAURANT_CONFIG),
      name: isKnownTenant(tenantId)
        ? tenant.label
        : GENERIC_RESTAURANT_CONFIG.name,
    };
  }
  return {
    ...clone(DEFAULT_RESTAURANT_CONFIG),
    name: tenant.label,
    slogan:
      tenantId === "fuego"
        ? "Brasa, fuego y sabor que se comparte."
        : "Ingredientes frescos, platos ligeros y llenos de color.",
    heroTitle:
      tenantId === "fuego"
        ? "Carnes a la brasa, listas para tu mesa."
        : "Lo fresco de la huerta, directo a tu plato.",
    heroDescription:
      tenantId === "fuego"
        ? "Nuestra parrilla enciende al momento. Pide tu corte favorito y recíbelo al punto."
        : "Una carta ligera preparada al momento, pensada para todos los días.",
    heroBadge: `🔥 ${tenant.city} · cocina en vivo`,
    appearance: { preset: tenant.preset, socialLinks: {} },
    phone: tenant.phone,
    countryCode: "+57",
    whatsapp: tenant.whatsapp,
    address: tenant.address,
    city: tenant.city,
    hours: tenant.hours,
    currency: tenant.currency,
    aiSearch: {
      description: tenant.description,
      keywords: `${tenant.label}, ${tenant.city}, pedidos en línea`,
      serviceArea: tenant.city,
      highlights: tenantId === "fuego" ? "parrilla, brasa, carnes" : "fresco, vegetariano, ligero",
    },
  };
}

function buildCatalog(tenantId: string): Pick<
  DemoTenantState,
  "categories" | "items" | "stocks" | "recipes"
> {
  const categories = clone(
    isTemplateTenant(tenantId) ? genericCategories : seedCategories,
  );
  const items = clone(
    isTemplateTenant(tenantId) ? genericMenuItems : seedMenuItems,
  );
  const stocks = clone(
    isTemplateTenant(tenantId) ? genericIngredientStocks : demoIngredientStocks,
  );
  const recipes = clone(
    isTemplateTenant(tenantId) ? genericRecipes : demoRecipes,
  );

  if (tenantId === "fuego") {
    items.push({
      id: "item-fuego-parrilla",
      name: "Parrilla de la casa",
      slug: "parrilla-de-la-casa",
      description: "Corte de res a la brasa con hogao y papa criolla.",
      price: 42000,
      categoryId: "cat-fuertes",
      categorySlug: "platos-fuertes",
      status: "available",
      ingredients: ["Carne de res", "Hogao", "Papa criolla"],
      allergens: [],
      emoji: "🔥",
      featured: true,
      prepMinutes: 22,
      calories: 780,
      recipe: [
        { ingredientId: "carne-res", quantity: 350 },
        { ingredientId: "hogao", quantity: 80 },
      ],
    });
    recipes["item-fuego-parrilla"] = [
      { ingredientId: "carne-res", quantity: 350 },
      { ingredientId: "hogao", quantity: 80 },
    ];
    // Stock propio: las arepas se agotan aquí pero no en Manía.
    stocks["maiz-blanco"] = 0;
    stocks.camaron = 1200;
    const empanadas = items.find((item) => item.id === "item-empanadas");
    if (empanadas) empanadas.price += 2000;
  }

  if (tenantId === "verde") {
    stocks["carne-res"] = 0;
    stocks.lechuga = 40;
    const ajiaco = items.find((item) => item.id === "item-ajiaco");
    if (ajiaco) ajiaco.status = "unavailable";
  }

  return { categories, items, stocks, recipes };
}

function createState(tenantId: string): DemoTenantState {
  return {
    ...buildCatalog(tenantId),
    orders: new Map(),
    shifts: new Map(),
    visits: [],
    customers: [],
    losses: [],
    config: buildConfig(tenantId),
  };
}

/**
 * Devuelve el estado aislado de un tenant. Los tenants nuevos se crean bajo
 * demanda; Manía nunca se inicializa aquí para no interferir con Firestore.
 */
export function getDemoState(tenantId: string): DemoTenantState {
  if (!globalStore.__restauranteDemoTenants) {
    globalStore.__restauranteDemoTenants = new Map();
  }
  let state = globalStore.__restauranteDemoTenants.get(tenantId);
  if (!state) {
    state = createState(tenantId);
    globalStore.__restauranteDemoTenants.set(tenantId, state);
  }
  return state;
}

export function hasDemoState(tenantId: string): boolean {
  return Boolean(globalStore.__restauranteDemoTenants?.has(tenantId));
}

export function resetDemoStateForTests(tenantId?: string): void {
  if (!globalStore.__restauranteDemoTenants) return;
  if (tenantId) {
    globalStore.__restauranteDemoTenants.delete(tenantId);
  } else {
    for (const id of globalStore.__restauranteDemoTenants.keys()) {
      if (id !== DEFAULT_TENANT_ID) {
        globalStore.__restauranteDemoTenants.delete(id);
      }
    }
  }
}
