import { describe, expect, it, vi } from "vitest";

const rest = vi.hoisted(() => ({
  getDocument: vi.fn(),
  isFirestoreConfigured: vi.fn(),
  listDocuments: vi.fn(),
  setDocument: vi.fn(),
}));

vi.mock("../firebase/rest", () => rest);

import { setMenuItemStatus } from "../menu";

describe("setMenuItemStatus", () => {
  it("rechaza estados que no sean disponible o agotado", async () => {
    const result = await setMenuItemStatus("item-limonada-coco", "limited");
    expect(result).toBeNull();
    expect(rest.setDocument).not.toHaveBeenCalled();
  });

  it("escribe el estado en el documento compartido de Firestore", async () => {
    rest.isFirestoreConfigured.mockReturnValue(true);
    rest.getDocument.mockResolvedValue({ name: "Limonada de coco" });
    rest.setDocument.mockResolvedValue(undefined);

    const result = await setMenuItemStatus(
      "item-limonada-coco",
      "unavailable",
    );

    expect(result).toEqual({
      id: "item-limonada-coco",
      status: "unavailable",
    });
    expect(rest.getDocument).toHaveBeenCalledWith(
      "menuItems",
      "item-limonada-coco",
      0,
    );
    expect(rest.setDocument).toHaveBeenCalledWith(
      "menuItems",
      "item-limonada-coco",
      { status: "unavailable" },
    );
  });

  it("no escribe si el plato no existe", async () => {
    rest.isFirestoreConfigured.mockReturnValue(true);
    rest.getDocument.mockResolvedValue(null);
    rest.setDocument.mockClear();

    const result = await setMenuItemStatus("item-inexistente", "available");

    expect(result).toBeNull();
    expect(rest.setDocument).not.toHaveBeenCalled();
  });
});
