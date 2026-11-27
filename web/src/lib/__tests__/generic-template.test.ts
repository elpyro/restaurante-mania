import { afterEach, describe, expect, it, vi } from "vitest";

const rest = vi.hoisted(() => ({
  getDocument: vi.fn(),
  isFirestoreConfigured: vi.fn(() => false),
  listDocuments: vi.fn(),
  setDocument: vi.fn(),
  tenantPath: vi.fn(
    (tenantId: string, collection: string) => `tenants/${tenantId}/${collection}`,
  ),
}));

vi.mock("@/lib/firebase/rest", () => rest);

import {
  GENERIC_RESTAURANT_CONFIG,
  genericRestaurantConfig,
  getRestaurantConfig,
} from "@/lib/restaurant-config";
import {
  genericCategories,
  genericIngredientStocks,
  genericMenuItems,
  genericRecipes,
} from "@/lib/generic-template";
import { getMenu } from "@/lib/menu";
import { isFixedTenant, isTemplateTenant } from "@/lib/tenants";

afterEach(() => {
  rest.getDocument.mockReset();
  rest.isFirestoreConfigured.mockReturnValue(false);
  rest.listDocuments.mockReset();
  rest.setDocument.mockReset();
});

describe("plantilla genérica de restaurantes nuevos", () => {
  it("no contiene datos de otro restaurante", () => {
    const text = JSON.stringify({
      ...GENERIC_RESTAURANT_CONFIG,
      categories: genericCategories,
      items: genericMenuItems,
      stocks: genericIngredientStocks,
      recipes: genericRecipes,
    });
    expect(text).not.toContain("Medellín");
    expect(text).not.toContain("Colombia");
    expect(text).not.toContain("bandeja paisa");
    expect(text).not.toContain(" Restaurante Manía");
    expect(genericMenuItems).toHaveLength(2);
    expect(genericCategories).toHaveLength(1);
  });

  it("reconoce solo como plantilla los tenants creados por el usuario", () => {
    expect(isFixedTenant("mania")).toBe(true);
    expect(isFixedTenant("fuego")).toBe(true);
    expect(isFixedTenant("verde")).toBe(true);
    expect(isTemplateTenant("resturantedeejemplo")).toBe(true);
    expect(isTemplateTenant("casa-nueva")).toBe(true);
    expect(isTemplateTenant("Mi Tienda")).toBe(false);
    expect(genericRestaurantConfig("casa-nueva").name).toBe(
      "Restaurante de ejemplo",
    );
  });

  it("sirve la plantilla en la config y el menú de un tenant nuevo", async () => {
    const [config, menu] = await Promise.all([
      getRestaurantConfig("resturantedeejemplo"),
      getMenu("resturantedeejemplo"),
    ]);

    expect(config.configured).toBe(false);
    expect(config.config.name).toBe("Restaurante de ejemplo");
    expect(config.config.slogan).toBe(
      "Comida lista para compartir, todos los días.",
    );
    expect(config.config.aiSearch.description).toContain("pedidos en línea");
    expect(menu.categories.map((category) => category.id)).toEqual([
      "cat-generales",
    ]);
    expect(menu.items.map((item) => item.id).sort()).toEqual([
      "item-ensalada-fresca",
      "item-plato-del-dia",
    ]);
    expect(menu.items.every((item) => item.status === "available")).toBe(true);
  });

  it("conserva el catálogo histórico de un tenant ya configurado", async () => {
    rest.isFirestoreConfigured.mockReturnValue(true);
    rest.listDocuments.mockResolvedValue([]);
    rest.getDocument.mockResolvedValue({
      name: "Taquitos históricos",
      phone: "3212308383",
      countryCode: "+57",
      city: "Medellín",
      address: "Calle 10 # 43-12, Medellín",
      hours: "11:00 - 22:00",
    });

    const [config, menu] = await Promise.all([
      getRestaurantConfig("taquitos-historicos"),
      getMenu("taquitos-historicos"),
    ]);

    expect(config.configured).toBe(true);
    expect(config.config.name).toBe("Taquitos históricos");
    expect(menu.items.some((item) => item.id === "item-empanadas")).toBe(true);
    expect(menu.items.some((item) => item.id === "item-plato-del-dia")).toBe(
      false,
    );
  });
});
