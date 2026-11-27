/**
 * Catálogo mínimo con el que arranca cualquier restaurante nuevo.
 *
 * Los IDs son compartidos con la APK (`SeedData.generic*`) para que la web y el
 * POS puedan leer y editar exactamente los mismos documentos de Firestore.
 * No hay ciudad, país ni platos típicos: son ejemplos neutrales y editables.
 */

import type { Category, MenuItem, RecipeIngredient } from "./types";

export const genericCategories: Category[] = [
  {
    id: "cat-generales",
    name: "Platos",
    slug: "platos",
    description: "Opciones preparadas al momento para todos los gustos.",
    order: 1,
    emoji: "🍽️",
  },
];

export const genericMenuItems: MenuItem[] = [
  {
    id: "item-plato-del-dia",
    name: "Plato del día",
    slug: "plato-del-dia",
    description:
      "Una preparación completa con ingredientes frescos, lista para disfrutar en cualquier momento.",
    price: 15000,
    categoryId: "cat-generales",
    categorySlug: "platos",
    status: "available",
    ingredients: ["Ingrediente base", "Vegetales frescos", "Acompañamiento"],
    allergens: [],
    emoji: "🍽️",
    featured: true,
    prepMinutes: 20,
    calories: 550,
    sku: "SKU-PLATO-DIA",
    recipe: [
      { ingredientId: "ing-base-generico", quantity: 150 },
      { ingredientId: "ing-vegetales-genericos", quantity: 100 },
      { ingredientId: "ing-acompanamiento-generico", quantity: 120 },
    ],
  },
  {
    id: "item-ensalada-fresca",
    name: "Ensalada fresca",
    slug: "ensalada-fresca",
    description:
      "Vegetales frescos con un aderezo suave, preparados al momento.",
    price: 12000,
    categoryId: "cat-generales",
    categorySlug: "platos",
    status: "available",
    ingredients: ["Vegetales frescos", "Aderezo suave"],
    allergens: [],
    emoji: "🥗",
    featured: false,
    prepMinutes: 10,
    calories: 320,
    sku: "SKU-ENSALADA",
    recipe: [
      { ingredientId: "ing-vegetales-genericos", quantity: 120 },
      { ingredientId: "ing-aderezo-suave", quantity: 30 },
    ],
  },
];

export const genericIngredientStocks: Record<string, number> = {
  "ing-base-generico": 5000,
  "ing-vegetales-genericos": 5000,
  "ing-acompanamiento-generico": 5000,
  "ing-aderezo-suave": 2000,
};

export const genericRecipes: Record<string, RecipeIngredient[]> = {
  "item-plato-del-dia": [
    { ingredientId: "ing-base-generico", quantity: 150 },
    { ingredientId: "ing-vegetales-genericos", quantity: 100 },
    { ingredientId: "ing-acompanamiento-generico", quantity: 120 },
  ],
  "item-ensalada-fresca": [
    { ingredientId: "ing-vegetales-genericos", quantity: 120 },
    { ingredientId: "ing-aderezo-suave", quantity: 30 },
  ],
};
