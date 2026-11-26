import { afterEach, describe, expect, it, vi } from "vitest";

const rest = vi.hoisted(() => ({
  createDocument: vi.fn(),
  getDocument: vi.fn(),
  isFirestoreConfigured: vi.fn(() => false),
  listDocuments: vi.fn(),
  setDocument: vi.fn(),
  tenantPath: vi.fn(
    (tenantId: string, collection: string) => `tenants/${tenantId}/${collection}`,
  ),
}));

vi.mock("@/lib/firebase/rest", () => rest);

import { GET, POST } from "@/app/api/visits/route";
import {
  closeCashShift,
  getCurrentCashShift,
  listCashShifts,
} from "@/lib/cash-shifts";
import {
  getDemoState,
  resetDemoStateForTests,
} from "@/lib/demo-store";
import { getPublicMenu } from "@/lib/menu";
import {
  createOrder,
  getOrderById,
  listOrders,
  updateOrder,
} from "@/lib/orders";
import {
  getRestaurantConfig,
  saveDemoRestaurantConfig,
} from "@/lib/restaurant-config";
import { demoIngredientStocks } from "@/lib/seed";

const baseOrder = {
  customerName: "Ana Pérez",
  customerPhone: "300 123 4567",
  deliveryAddress: "",
  type: "pickup" as const,
  tableNumber: null,
  paymentMethod: "cash" as const,
  notes: "",
  items: [{ menuItemId: "item-tres-leches", quantity: 2 }],
};

function visitRequest(tenantId: string, visitorId: string): Request {
  return new Request("http://localhost/api/visits", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-tenant-id": tenantId,
    },
    body: JSON.stringify({
      visitorId,
      occurredAt: "2026-11-25T10:00:00.000Z",
      dayKey: "2026-11-25",
      referenceLabel: "/menu",
    }),
  });
}

afterEach(() => {
  resetDemoStateForTests();
  rest.isFirestoreConfigured.mockReturnValue(false);
  rest.getDocument.mockReset();
  rest.listDocuments.mockReset();
  rest.setDocument.mockReset();
});

describe("aislamiento de catálogo y configuración", () => {
  it("cada tenant tiene su propio menú y stock inicial", async () => {
    const [mania, fuego, verde] = await Promise.all([
      getPublicMenu("mania"),
      getPublicMenu("fuego"),
      getPublicMenu("verde"),
    ]);

    expect(mania.items.some((item) => item.id === "item-fuego-parrilla")).toBe(false);
    expect(fuego.items.some((item) => item.id === "item-fuego-parrilla")).toBe(true);
    expect(getDemoState("fuego").stocks["maiz-blanco"]).toBe(0);
    expect(getDemoState("mania").stocks["maiz-blanco"]).not.toBe(0);
    expect(getDemoState("verde").stocks["carne-res"]).toBe(0);
    expect(getDemoState("fuego").stocks["carne-res"]).not.toBe(0);
    expect(
      getDemoState("verde").items.find((item) => item.id === "item-ajiaco")?.status,
    ).toBe("unavailable");
    expect(
      getDemoState("mania").items.find((item) => item.id === "item-ajiaco")?.status,
    ).not.toBe("unavailable");
    expect(verde.items.some((item) => item.id === "item-ajiaco")).toBe(false);
  });

  it("la configuración es independiente y nunca se escribe en Firestore", async () => {
    const [fuego, verde] = await Promise.all([
      getRestaurantConfig("fuego"),
      getRestaurantConfig("verde"),
    ]);
    expect(fuego.source).toBe("demo");
    expect(fuego.config.name).toBe("Fuego · Parrilla & Brasa");
    expect(verde.config.name).toBe("Verde · Cocina fresca");
    expect(fuego.config.city).not.toBe(verde.config.city);

    saveDemoRestaurantConfig("fuego", { ...fuego.config, name: "Fuego editado" });
    expect(getDemoState("fuego").config.name).toBe("Fuego editado");
    expect(getDemoState("verde").config.name).toBe("Verde · Cocina fresca");
    expect(rest.setDocument).not.toHaveBeenCalled();
  });
});

describe("aislamiento de pedidos e inventario", () => {
  it("un pedido creado en fuego no existe en manía ni en verde", async () => {
    const fuegoOrder = await createOrder(baseOrder, "fuego");
    expect(fuegoOrder.code).toMatch(/^FUE-/);

    expect(await getOrderById(fuegoOrder.id, "fuego")).toMatchObject({
      id: fuegoOrder.id,
    });
    expect(await getOrderById(fuegoOrder.id, "mania")).toBeNull();
    expect(await getOrderById(fuegoOrder.id, "verde")).toBeNull();
    expect(await listOrders("mania")).toHaveLength(0);
    expect(await listOrders("verde")).toHaveLength(0);
    expect(await listOrders("fuego")).toHaveLength(1);
  });

  it("el descuento de stock de un tenant no afecta a los demás", async () => {
    const lecheInicialFuego = getDemoState("fuego").stocks.leche;
    const lecheInicialVerde = getDemoState("verde").stocks.leche;
    const lecheLegacy = demoIngredientStocks.leche;

    const order = await createOrder(baseOrder, "fuego");
    await updateOrder(order.id, { status: "confirmed" }, "fuego");

    expect(getDemoState("fuego").stocks.leche).toBe(lecheInicialFuego - 240);
    expect(getDemoState("verde").stocks.leche).toBe(lecheInicialVerde);
    expect(demoIngredientStocks.leche).toBe(lecheLegacy);
    expect(rest.setDocument).not.toHaveBeenCalled();
  });
});

describe("aislamiento de turnos y visitas", () => {
  it("los turnos de cada tenant son independientes", async () => {
    const fuegoShift = await getCurrentCashShift("fuego");
    expect(await listCashShifts("fuego")).toHaveLength(1);
    expect(await listCashShifts("verde")).toHaveLength(0);
    expect(await listCashShifts("mania")).toHaveLength(0);

    const closed = await closeCashShift(fuegoShift, "fuego");
    expect(closed.currentShift.id).not.toBe(fuegoShift.id);
    expect(await listCashShifts("fuego")).toHaveLength(2);
    expect(await listCashShifts("verde")).toHaveLength(0);
  });

  it("las visitas de fuego no aparecen en manía ni en verde", async () => {
    const created = await POST(visitRequest("fuego", "visitor-aislamiento"));
    expect(created.status).toBe(200);
    expect((await created.json()).tenantId).toBe("fuego");

    const fuego = await (await GET(visitRequest("fuego", "x"))).json();
    const mania = await (await GET(visitRequest("mania", "x"))).json();
    const verde = await (await GET(visitRequest("verde", "x"))).json();

    expect(fuego.visits).toHaveLength(1);
    expect(fuego.visits[0].visitorId).toBe("visitor-aislamiento");
    expect(mania.visits).toHaveLength(0);
    expect(verde.visits).toHaveLength(0);
    expect(rest.setDocument).not.toHaveBeenCalled();
  });
});
