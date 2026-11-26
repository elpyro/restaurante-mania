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
    getDocument: vi.fn(),
    setDocument: vi.fn(),
    deleteDocument: vi.fn(),
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
  getDocument: mocks.getDocument,
  setDocument: mocks.setDocument,
  deleteDocument: mocks.deleteDocument,
  tenantPath: mocks.tenantPath,
}));

import { DELETE, GET, POST } from "../route";

function request(
  options: { query?: string; token?: string; body?: unknown } = {},
) {
  return new Request(`http://localhost/api/users${options.query ?? ""}`, {
    method: options.body === undefined ? "GET" : "POST",
    headers: {
      "content-type": "application/json",
      ...(options.token ? { authorization: `Bearer ${options.token}` } : {}),
    },
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
}

const validBody = {
  id: "u-nueva",
  name: "Nueva Cajera",
  email: "nueva@restaurante.com",
  role: "cashier",
};

describe("/api/users", () => {
  beforeEach(() => {
    for (const mock of [
      mocks.verifyAdminIdToken,
      mocks.listDocuments,
      mocks.getDocument,
      mocks.setDocument,
      mocks.deleteDocument,
    ]) {
      mock.mockReset();
    }
    mocks.verifyAdminIdToken.mockResolvedValue({ uid: "admin-1", role: "admin" });
    mocks.listDocuments.mockResolvedValue([]);
    mocks.getDocument.mockResolvedValue(null);
    mocks.setDocument.mockResolvedValue(undefined);
    mocks.deleteDocument.mockResolvedValue(undefined);
  });

  it("rechaza peticiones sin token y a roles que no son admin", async () => {
    expect((await GET(request())).status).toBe(401);
    expect((await POST(request({ body: validBody }))).status).toBe(401);

    mocks.verifyAdminIdToken.mockResolvedValue({ uid: "u", role: "waiter" });
    expect((await GET(request({ token: "token" }))).status).toBe(403);
    expect((await POST(request({ token: "token", body: validBody }))).status).toBe(403);
    expect((await DELETE(request({ token: "token", query: "?id=u-nueva" }))).status).toBe(403);
    expect(mocks.setDocument).not.toHaveBeenCalled();
  });

  it("devuelve 503 si Firebase Admin no está disponible", async () => {
    mocks.verifyAdminIdToken.mockRejectedValue(
      new mocks.AdminUnavailableError("sin credenciales"),
    );
    expect((await GET(request({ token: "token" }))).status).toBe(503);
  });

  it("lista usuarios del tenant resuelto por query", async () => {
    mocks.listDocuments.mockResolvedValue([
      {
        id: "u-1",
        uid: "u-1",
        name: "Admin QA",
        email: "admin.qa@restaurante.com",
        role: "admin",
        status: "active",
        createdAt: "2026-11-20T00:00:00.000Z",
      },
    ]);
    const response = await GET(request({ token: "token", query: "?tenant=verde" }));
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      tenantId: "verde",
      users: [{ id: "u-1", email: "admin.qa@restaurante.com" }],
    });
    expect(mocks.listDocuments.mock.calls[0]?.[0]).toBe("tenants/verde/users");
    expect(mocks.verifyAdminIdToken.mock.calls[0]).toEqual(["token", "verde"]);
  });

  it("guarda el alta con el contrato de roles y el tenant del header", async () => {
    const response = await POST(
      new Request("http://localhost/api/users", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: "Bearer token",
          "x-tenant-id": "fuego",
        },
        body: JSON.stringify(validBody),
      }),
    );
    expect(response.status).toBe(200);
    const [collection, id, document] = mocks.setDocument.mock.calls[0] as [
      string,
      string,
      Record<string, unknown>,
    ];
    expect(collection).toBe("tenants/fuego/users");
    expect(id).toBe("u-nueva");
    expect(document).toMatchObject({
      uid: "u-nueva",
      name: "Nueva Cajera",
      email: "nueva@restaurante.com",
      role: "cashier",
      status: "active",
    });
  });

  it("valida correo y rol antes de escribir", async () => {
    expect(
      (await POST(request({ token: "token", body: { ...validBody, email: "malo" } }))).status,
    ).toBe(400);
    expect(
      (await POST(request({ token: "token", body: { ...validBody, role: "root" } }))).status,
    ).toBe(400);
    expect(mocks.setDocument).not.toHaveBeenCalled();
  });

  it("elimina por id dentro del tenant correcto", async () => {
    const response = await DELETE(
      request({ token: "token", query: "?tenant=verde&id=u-nueva" }),
    );
    expect(response.status).toBe(200);
    expect(mocks.deleteDocument).toHaveBeenCalledWith("tenants/verde/users", "u-nueva");
  });
});
