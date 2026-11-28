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
    id: "cat-entrantes",
    name: "Entradas",
    slug: "entradas",
    description: "Entradas y aperitivos",
    order: 1,
    emoji: "🥗",
  },
  {
    id: "cat-sopas",
    name: "Sopas",
    slug: "sopas",
    description: "Sopas y caldos",
    order: 2,
    emoji: "🍲",
  },
  {
    id: "cat-platos-fuertes",
    name: "Platos fuertes",
    slug: "platos-fuertes",
    description: "Platos principales",
    order: 3,
    emoji: "🍽️",
  },
  {
    id: "cat-ensaladas",
    name: "Ensaladas",
    slug: "ensaladas",
    description: "Ensaladas frescas",
    order: 4,
    emoji: "🥗",
  },
  {
    id: "cat-guarniciones",
    name: "Guarniciones",
    slug: "guarniciones",
    description: "Acompañamientos y guarniciones",
    order: 5,
    emoji: "🥔",
  },
  {
    id: "cat-postres",
    name: "Postres",
    slug: "postres",
    description: "Postres y dulces",
    order: 6,
    emoji: "🍰",
  },
  {
    id: "cat-bebidas",
    name: "Bebidas",
    slug: "bebidas",
    description: "Bebidas y refrescos",
    order: 7,
    emoji: "🥤",
  },
  {
    id: "cat-licores",
    name: "Licores",
    slug: "licores",
    description: "Bebidas alcohólicas",
    order: 8,
    emoji: "🍷",
  },
  {
    id: "cat-combos",
    name: "Combos y promociones",
    slug: "combos",
    description: "Combinaciones y ofertas",
    order: 9,
    emoji: "🎁",
  },
  {
    id: "cat-menu-infantil",
    name: "Menú infantil",
    slug: "menu-infantil",
    description: "Opciones para niños",
    order: 10,
    emoji: "🧒",
  },
  {
    id: "cat-opciones-dieteticas",
    name: "Opciones dietéticas",
    slug: "opciones-dieteticas",
    description: "Opciones especiales de dieta",
    order: 11,
    emoji: "🥬",
  },
];

export const genericMenuItems: MenuItem[] = [
  {
    id: "item-ensalada-fresca",
    name: "Ensalada fresca",
    slug: "ensalada-fresca",
    description: "Tomates y lechuga fresca preparados al momento.",
    imageUrl:
      "https://firebasestorage.googleapis.com/v0/b/restaurante-mania-e47a0.firebasestorage.app/o/imagenesglobales%2FGemini_Generated_Image_u3798u3798u3798u.png?alt=media",
    price: 12000,
    categoryId: "cat-ensaladas",
    categorySlug: "ensaladas",
    status: "available",
    ingredients: ["Tomates", "Lechuga"],
    allergens: [],
    emoji: "🥗",
    // Plaza de la plantilla inicial de un restaurante nuevo.
    featured: true,
    prepMinutes: 10,
    calories: 320,
    sku: "SKU-ENSALADA",
    recipe: [
      { ingredientId: "ing-tomates", quantity: 100 },
      { ingredientId: "ing-lechuga", quantity: 120 },
    ],
  },
  {
    id: "item-cafe-con-leche",
    name: "Cafe con leche",
    slug: "cafe-con-leche",
    description: "Cafe caliente con leche.",
    imageUrl:
      "https://firebasestorage.googleapis.com/v0/b/restaurante-mania-e47a0.firebasestorage.app/o/imagenesglobales%2FGemini_Generated_Image_kfkrwkfkrwkfkrwk.png?alt=media",
    price: 8500,
    categoryId: "cat-bebidas",
    categorySlug: "bebidas",
    status: "available",
    ingredients: ["Cafe", "Leche"],
    allergens: ["Leche"],
    emoji: "☕",
    // Plaza de la plantilla inicial de un restaurante nuevo.
    featured: true,
    prepMinutes: 5,
    calories: 180,
    sku: "SKU-CAFE-LECHE",
    recipe: [
      { ingredientId: "ing-cafe", quantity: 20 },
      { ingredientId: "ing-leche", quantity: 150 },
    ],
  },
];

export const genericIngredientStocks: Record<string, number> = {
  "ing-tomates": 5000,
  "ing-lechuga": 5000,
  "ing-cafe": 40,
  "ing-leche": 5000,
};

export const genericRecipes: Record<string, RecipeIngredient[]> = {
  "item-ensalada-fresca": [
    { ingredientId: "ing-tomates", quantity: 100 },
    { ingredientId: "ing-lechuga", quantity: 120 },
  ],
  "item-cafe-con-leche": [
    { ingredientId: "ing-cafe", quantity: 20 },
    { ingredientId: "ing-leche", quantity: 150 },
  ],
};
