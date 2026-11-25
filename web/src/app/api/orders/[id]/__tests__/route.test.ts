import { describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  getOrderById: vi.fn(),
  updateOrder: vi.fn(),
  syncMenuStatusesFromStock: vi.fn(),
}));

vi.mock("@/lib/orders", () => ({
  getOrderById: mocks.getOrderById,
  updateOrder: mocks.updateOrder,
  OrderValidationError: class OrderValidationError extends Error {},
}));

vi.mock("@/lib/menu", () => ({
  syncMenuStatusesFromStock: mocks.syncMenuStatusesFromStock,
}));

import { PATCH } from "../route";

describe("PATCH /api/orders/[id]", () => {
  it("acepta inventoryDeducted como único cambio", async () => {
    mocks.updateOrder.mockReset();
    mocks.syncMenuStatusesFromStock.mockReset();
    mocks.updateOrder.mockResolvedValue({
      id: "order-1",
      inventoryDeducted: true,
    });
    mocks.syncMenuStatusesFromStock.mockResolvedValue([]);

    const response = await PATCH(
      new Request("http://localhost/api/orders/order-1", {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ inventoryDeducted: true }),
      }),
      { params: Promise.resolve({ id: "order-1" }) },
    );

    expect(response.status).toBe(200);
    expect(mocks.updateOrder).toHaveBeenCalledWith("order-1", {
      inventoryDeducted: true,
    });
  });

  it("rechaza una petición sin cambios", async () => {
    const response = await PATCH(
      new Request("http://localhost/api/orders/order-1", {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({}),
      }),
      { params: Promise.resolve({ id: "order-1" }) },
    );

    expect(response.status).toBe(400);
  });
});
