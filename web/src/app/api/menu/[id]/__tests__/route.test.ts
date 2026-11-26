import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => {
  class AdminUnavailableError extends Error {
    constructor(message: string) {
      super(message);
      this.name = "AdminUnavailableError";
    }
  }
  return {
    AdminUnavailableError,
    verifyAdminIdToken: vi.fn(),
    setMenuItemStatus: vi.fn(),
    setMenuItemFeatured: vi.fn(),
  };
});

vi.mock("@/lib/firebase/admin", () => ({
  verifyAdminIdToken: mocks.verifyAdminIdToken,
  AdminUnavailableError: mocks.AdminUnavailableError,
}));

vi.mock("@/lib/menu", () => ({
  setMenuItemStatus: mocks.setMenuItemStatus,
  setMenuItemFeatured: mocks.setMenuItemFeatured,
}));

import { PATCH } from "../route";

const context = { params: Promise.resolve({ id: "item-1" }) };

function request(body: unknown, authorization?: string) {
  return new Request("http://localhost/api/menu/item-1", {
    method: "PATCH",
    headers: {
      "content-type": "application/json",
      ...(authorization ? { authorization } : {}),
    },
    body: JSON.stringify(body),
  });
}

describe("PATCH /api/menu/[id]", () => {
  beforeEach(() => {
    mocks.verifyAdminIdToken.mockReset();
    mocks.setMenuItemStatus.mockReset();
    mocks.setMenuItemFeatured.mockReset();
    mocks.verifyAdminIdToken.mockResolvedValue({ uid: "admin-1", role: "admin" });
    mocks.setMenuItemStatus.mockResolvedValue({ id: "item-1", status: "available" });
    mocks.setMenuItemFeatured.mockResolvedValue({ id: "item-1", featured: true });
  });

  it("rechaza peticiones sin token", async () => {
    const response = await PATCH(request({ featured: true }), context);
    expect(response.status).toBe(401);
    expect(mocks.setMenuItemFeatured).not.toHaveBeenCalled();
  });

  it("rechaza tokens sin rol admin", async () => {
    mocks.verifyAdminIdToken.mockResolvedValue({ uid: "user-1", role: "waiter" });
    const response = await PATCH(request({ featured: true }, "Bearer token"), context);
    expect(response.status).toBe(403);
    expect(mocks.setMenuItemFeatured).not.toHaveBeenCalled();
  });

  it("rechaza tokens inválidos o expirados", async () => {
    mocks.verifyAdminIdToken.mockRejectedValue(new Error("token expirado"));
    const response = await PATCH(request({ featured: true }, "Bearer token"), context);
    expect(response.status).toBe(401);
  });

  it("devuelve 503 si Firebase Admin no está disponible", async () => {
    mocks.verifyAdminIdToken.mockRejectedValue(
      new mocks.AdminUnavailableError("sin credenciales"),
    );
    const response = await PATCH(request({ featured: true }, "Bearer token"), context);
    expect(response.status).toBe(503);
  });

  it("publica favoritos cuando el token es de admin", async () => {
    const response = await PATCH(request({ featured: true }, "Bearer token"), context);
    expect(response.status).toBe(200);
    expect(mocks.verifyAdminIdToken).toHaveBeenCalledWith("token", "mania");
    expect(mocks.setMenuItemFeatured).toHaveBeenCalledWith("item-1", true, "mania");
    const payload = await response.json();
    expect(payload.item).toMatchObject({ id: "item-1", featured: true });
  });

  it("publica disponibilidad cuando el token es de admin", async () => {
    const response = await PATCH(
      request({ status: "unavailable", manual: true, reason: "manual" }, "Bearer token"),
      context,
    );
    expect(response.status).toBe(200);
    expect(mocks.setMenuItemStatus).toHaveBeenCalledWith(
      "item-1",
      "unavailable",
      true,
      "manual",
      "mania",
    );
  });

  it("valida el cuerpo antes de escribir", async () => {
    const empty = await PATCH(request({}, "Bearer token"), context);
    expect(empty.status).toBe(400);
    const badFeatured = await PATCH(request({ featured: "sí" }, "Bearer token"), context);
    expect(badFeatured.status).toBe(400);
    expect(mocks.setMenuItemStatus).not.toHaveBeenCalled();
    expect(mocks.setMenuItemFeatured).not.toHaveBeenCalled();
  });

  it("devuelve 404 si el plato no existe", async () => {
    mocks.setMenuItemFeatured.mockResolvedValue(null);
    const response = await PATCH(request({ featured: true }, "Bearer token"), context);
    expect(response.status).toBe(404);
  });
});
