import { describe, expect, it } from "vitest";
import { seedCategories, seedMenuItems } from "../seed";
import { searchMenuItems } from "../menu";
import { breadcrumbJsonLd, menuJsonLd, restaurantJsonLd } from "../seo";

describe("búsqueda de menú", () => {
  it("encuentra por nombre sin importar tildes", () => {
    const results = searchMenuItems(seedMenuItems, "ajiaco");
    expect(results.map((item) => item.slug)).toContain("ajiaco-santafereño");
    expect(searchMenuItems(seedMenuItems, "santafereño")).toHaveLength(1);
  });

  it("encuentra por ingrediente", () => {
    const results = searchMenuItems(seedMenuItems, "coco");
    expect(results.length).toBeGreaterThan(0);
    expect(results.every((item) => JSON.stringify(item).toLowerCase().includes("coco"))).toBe(true);
  });

  it("devuelve todo cuando la consulta está vacía", () => {
    expect(searchMenuItems(seedMenuItems, "   ")).toHaveLength(seedMenuItems.length);
  });

  it("devuelve vacío cuando no hay coincidencias", () => {
    expect(searchMenuItems(seedMenuItems, "sushi")).toHaveLength(0);
  });
});

describe("JSON-LD", () => {
  it("describe el restaurante con dirección y menú", () => {
    const data = restaurantJsonLd();
    expect(data["@type"]).toBe("Restaurant");
    expect(data.name).toBeTruthy();
    expect(data.hasMenu).toContain("/menu");
  });

  it("genera secciones de menú con sus productos", () => {
    const data = menuJsonLd(seedCategories, seedMenuItems) as {
      hasMenuSection: Array<{ name: string; hasMenuItem: unknown[] }>;
    };
    expect(data.hasMenuSection).toHaveLength(seedCategories.length);
    expect(data.hasMenuSection[0].hasMenuItem.length).toBeGreaterThan(0);
  });

  it("genera migas de pan numeradas", () => {
    const data = breadcrumbJsonLd([
      { name: "Inicio", path: "/" },
      { name: "Menú", path: "/menu" },
    ]) as { itemListElement: Array<{ position: number }> };
    expect(data.itemListElement.map((entry) => entry.position)).toEqual([1, 2]);
  });
});
