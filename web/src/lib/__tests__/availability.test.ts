import { describe, expect, it } from "vitest";
import {
  computeMaxServings,
  deriveMenuItemStatus,
} from "../../../../firebase/functions/src/domain";

const recipe = [
  { ingredientId: "cafe", quantity: 15 },
  { ingredientId: "agua", quantity: 200 },
];

describe("disponibilidad derivada del stock (Cloud Functions)", () => {
  it("calcula el máximo de porciones por el insumo limitante", () => {
    expect(
      computeMaxServings(recipe, new Map([["cafe", 2000], ["agua", 20000]])),
    ).toBe(100);
  });

  it("marca unavailable cuando un insumo está a cero", () => {
    const result = deriveMenuItemStatus(
      recipe,
      new Map([["cafe", 0], ["agua", 20000]]),
    );
    expect(result).toEqual({ status: "unavailable", maxServings: 0 });
  });

  it("marca available al reponer stock suficiente", () => {
    expect(
      deriveMenuItemStatus(recipe, new Map([["cafe", 30], ["agua", 20000]])),
    ).toEqual({ status: "available", maxServings: 2 });
  });

  it("un bloqueo manual gana aunque haya stock", () => {
    expect(
      deriveMenuItemStatus(
        recipe,
        new Map([["cafe", 2000], ["agua", 20000]]),
        "unavailable",
      ).status,
    ).toBe("unavailable");
  });

  it("trata insumos sin documento de stock como agotados", () => {
    expect(computeMaxServings(recipe, new Map())).toBe(0);
    expect(
      deriveMenuItemStatus(recipe, new Map([["agua", 20000]])),
    ).toEqual({ status: "unavailable", maxServings: 0 });
  });
});
