import { describe, expect, it, vi } from "vitest";

const rest = vi.hoisted(() => ({
  getDocument: vi.fn(),
  isFirestoreConfigured: vi.fn(),
  listDocuments: vi.fn(),
  setDocument: vi.fn(),
}));

vi.mock("../firebase/rest", () => rest);

import { setMenuItemStatus, syncMenuStatusesFromStock } from "../menu";

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
      expect.objectContaining({
        status: "unavailable",
        manualStatus: "unavailable",
        statusReason: "manual",
      }),
    );
  });

  it("no reescribe statusUpdatedAt si el estado efectivo no cambia", async () => {
    rest.isFirestoreConfigured.mockReturnValue(true);
    rest.getDocument.mockResolvedValue({
      name: "Limonada de coco",
      status: "unavailable",
      manualStatus: "unavailable",
      statusReason: "manual",
      statusUpdatedAt: "2026-01-01T00:00:00.000Z",
    });
    rest.setDocument.mockClear();

    const result = await setMenuItemStatus("item-limonada-coco", "unavailable");

    expect(result).toEqual({
      id: "item-limonada-coco",
      status: "unavailable",
    });
    expect(rest.setDocument).not.toHaveBeenCalled();
  });

  it("guarda el motivo ingredients cuando el agotamiento viene del stock", async () => {
    rest.isFirestoreConfigured.mockReturnValue(true);
    rest.getDocument.mockResolvedValue({ name: "Café de origen" });
    rest.setDocument.mockClear();

    await setMenuItemStatus("item-cafe", "unavailable", false, "ingredients");

    expect(rest.setDocument).toHaveBeenCalledWith(
      "menuItems",
      "item-cafe",
      expect.objectContaining({
        status: "unavailable",
        manualStatus: null,
        statusReason: "ingredients",
      }),
    );
  });

  it("limpia el bloqueo manual al marcar disponible", async () => {
    rest.isFirestoreConfigured.mockReturnValue(true);
    rest.getDocument.mockResolvedValue({ name: "Limonada de coco" });
    rest.setDocument.mockClear();

    await setMenuItemStatus("item-limonada-coco", "available", false);

    expect(rest.setDocument).toHaveBeenCalledWith(
      "menuItems",
      "item-limonada-coco",
      expect.objectContaining({ status: "available", manualStatus: null }),
    );
  });

  it("persiste el estado derivado del stock sin pisar bloqueos manuales", async () => {
    rest.isFirestoreConfigured.mockReturnValue(true);
    rest.listDocuments.mockImplementation(async (collection: string) =>
      collection === "ingredients"
        ? [{ id: "cafe", stock: 0 }]
        : [
            {
              id: "item-cafe",
              status: "available",
              manualStatus: null,
              recipe: [{ ingredientId: "cafe", quantity: 15 }],
            },
            {
              id: "item-bloqueado",
              status: "unavailable",
              manualStatus: "unavailable",
              recipe: [{ ingredientId: "cafe", quantity: 15 }],
            },
          ],
    );
    rest.setDocument.mockClear();

    const updated = await syncMenuStatusesFromStock();

    expect(updated).toEqual(["item-cafe"]);
    expect(rest.setDocument).toHaveBeenCalledTimes(1);
    expect(rest.setDocument).toHaveBeenCalledWith(
      "menuItems",
      "item-cafe",
      expect.objectContaining({ status: "unavailable", statusReason: "ingredients" }),
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
