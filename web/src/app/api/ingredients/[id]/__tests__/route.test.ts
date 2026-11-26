import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  deleteDocument: vi.fn(),
  getDocument: vi.fn(),
  isFirestoreConfigured: vi.fn(() => true),
  setDocument: vi.fn(),
  syncMenuStatusesFromStock: vi.fn(async () => [] as string[]),
  tenantPath: vi.fn(
    (tenantId: string, collection: string) => `tenants/${tenantId}/${collection}`,
  ),
}));

vi.mock("@/lib/firebase/rest", () => mocks);
vi.mock("@/lib/menu", () => ({
  syncMenuStatusesFromStock: mocks.syncMenuStatusesFromStock,
}));

import { PATCH } from "../route";

const context = { params: Promise.resolve({ id: "cafe" }) };

function request(body: unknown) {
  return new Request("http://localhost/api/ingredients/cafe?tenant=mania", {
    method: "PATCH",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("PATCH /api/ingredients/[id]", () => {
  beforeEach(() => {
    mocks.getDocument.mockReset();
    mocks.setDocument.mockReset();
    mocks.syncMenuStatusesFromStock.mockReset();
    mocks.syncMenuStatusesFromStock.mockResolvedValue([]);
  });

  it("crea el insumo con el ID de la URL, no con uno aleatorio", async () => {
    mocks.getDocument.mockResolvedValue(null);

    const response = await PATCH(
      request({ name: "Cafe", unit: "und", stock: 2000, minStock: 0 }),
      context,
    );

    expect(response.status).toBe(200);
    expect(mocks.setDocument).toHaveBeenCalledTimes(1);
    expect(mocks.setDocument).toHaveBeenCalledWith(
      "tenants/mania/ingredients",
      "cafe",
      expect.objectContaining({ name: "Cafe", unit: "und", stock: 2000 }),
    );
    expect(await response.json()).toMatchObject({ ok: true, id: "cafe" });
  });

  it("actualiza solo los campos publicados cuando el insumo ya existe", async () => {
    mocks.getDocument.mockResolvedValue({ name: "Cafe", stock: 10 });

    const response = await PATCH(request({ stock: 25 }), context);

    expect(response.status).toBe(200);
    expect(mocks.setDocument).toHaveBeenCalledWith(
      "tenants/mania/ingredients",
      "cafe",
      expect.objectContaining({ stock: 25 }),
    );
  });
});
