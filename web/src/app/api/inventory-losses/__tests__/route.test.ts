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
    isFirestoreConfigured: vi.fn(() => true),
    listDocuments: vi.fn(),
    setDocument: vi.fn(),
    tenantPath: vi.fn(
      (tenantId: string, collection: string) => `tenants/${tenantId}/${collection}`,
    ),
  };
});

vi.mock("@/lib/firebase/admin", () => ({
  verifyAdminIdToken: mocks.verifyAdminIdToken,
  AdminUnavailableError: mocks.AdminUnavailableError,
}));

vi.mock("@/lib/firebase/rest", () => ({
  isFirestoreConfigured: mocks.isFirestoreConfigured,
  listDocuments: mocks.listDocuments,
  setDocument: mocks.setDocument,
  tenantPath: mocks.tenantPath,
}));

import { GET, POST } from "../route";

function request(body?: unknown, authorization?: string, method = "POST") {
  return new Request("http://localhost/api/inventory-losses", {
    method,
    headers: {
      "content-type": "application/json",
      ...(authorization ? { authorization } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

const validBody = {
  id: "loss-1",
  reason: "caducado",
  lines: [
    {
      ingredientId: "leche",
      name: "Leche entera",
      quantity: 2,
      unit: "l",
    },
  ],
  notes: "Se venció el lote",
  photoUrl: null,
  createdAt: "2026-11-25T10:00:00.000Z",
  createdBy: { uid: "cook-1", name: "Jorge", role: "cook" },
  auditLog: [
    {
      action: "Pérdida registrada",
      timestamp: "2026-11-25T10:00:00.000Z",
      actorId: "cook-1",
      actorName: "Jorge",
      actorRole: "cook",
    },
  ],
};

describe("/api/inventory-losses", () => {
  beforeEach(() => {
    mocks.verifyAdminIdToken.mockReset();
    mocks.listDocuments.mockReset();
    mocks.setDocument.mockReset();
    mocks.verifyAdminIdToken.mockResolvedValue({
      uid: "admin-1",
      role: "admin",
    });
    mocks.listDocuments.mockResolvedValue([]);
    mocks.setDocument.mockResolvedValue(undefined);
  });

  it("rechaza peticiones sin token", async () => {
    expect((await POST(request(validBody))).status).toBe(401);
    expect((await GET(request(undefined, undefined, "GET"))).status).toBe(401);
    expect(mocks.setDocument).not.toHaveBeenCalled();
  });

  it("rechaza a roles que no son admin ni cocinero", async () => {
    mocks.verifyAdminIdToken.mockResolvedValue({ uid: "u", role: "waiter" });
    expect((await POST(request(validBody, "Bearer token"))).status).toBe(403);
    expect((await GET(request(undefined, "Bearer token", "GET"))).status).toBe(403);
  });

  it("devuelve 503 si Firebase Admin no está disponible", async () => {
    mocks.verifyAdminIdToken.mockRejectedValue(
      new mocks.AdminUnavailableError("sin credenciales"),
    );
    expect((await POST(request(validBody, "Bearer token"))).status).toBe(503);
  });

  it("permite a un cocinero registrar una pérdida con auditoría", async () => {
    mocks.verifyAdminIdToken.mockResolvedValue({ uid: "cook-1", role: "cook" });
    const response = await POST(request(validBody, "Bearer token"));
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      ok: true,
      tenantId: "mania",
      id: "loss-1",
    });

    const [collection, id, document] = mocks.setDocument.mock.calls[0] as [
      string,
      string,
      Record<string, unknown>,
    ];
    expect(collection).toBe("tenants/mania/inventoryLosses");
    expect(id).toBe("loss-1");
    expect(document).toMatchObject({
      reason: "caducado",
      notes: "Se venció el lote",
      receivedBy: { uid: "cook-1", role: "cook" },
    });
    expect(document.auditLog).toHaveLength(1);
  });

  it("valida el motivo y las cantidades", async () => {
    const badReason = await POST(
      request({ ...validBody, reason: "robo" }, "Bearer token"),
    );
    expect(badReason.status).toBe(400);

    const badQuantity = await POST(
      request(
        {
          ...validBody,
          lines: [{ ...validBody.lines[0], quantity: 0 }],
        },
        "Bearer token",
      ),
    );
    expect(badQuantity.status).toBe(400);
    expect(mocks.setDocument).not.toHaveBeenCalled();
  });

  it("lista las pérdidas ordenadas por fecha", async () => {
    mocks.listDocuments.mockResolvedValue([
      { id: "old", createdAt: "2026-11-24T10:00:00.000Z" },
      { id: "new", createdAt: "2026-11-25T10:00:00.000Z" },
    ]);
    const response = await GET(request(undefined, "Bearer token", "GET"));
    expect(response.status).toBe(200);
    const payload = await response.json();
    expect(payload.losses.map((loss: { id: string }) => loss.id)).toEqual([
      "new",
      "old",
    ]);
  });
});
