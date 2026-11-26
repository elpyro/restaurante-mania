import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  verifyIdToken: vi.fn(),
  getDocument: vi.fn(),
  listDocuments: vi.fn(),
  tenantPath: vi.fn(
    (tenantId: string, collection: string) => `tenants/${tenantId}/${collection}`,
  ),
}));

vi.mock("firebase-admin/app", () => ({
  getApps: () => [{}],
  initializeApp: vi.fn(),
  cert: vi.fn(),
}));

vi.mock("firebase-admin/auth", () => ({
  getAuth: () => ({ verifyIdToken: mocks.verifyIdToken }),
}));

vi.mock("@/lib/firebase/rest", () => ({
  getDocument: mocks.getDocument,
  listDocuments: mocks.listDocuments,
  tenantPath: mocks.tenantPath,
}));

import { verifyAdminIdToken } from "@/lib/firebase/admin";

describe("verifyAdminIdToken", () => {
  beforeEach(() => {
    mocks.verifyIdToken.mockReset();
    mocks.getDocument.mockReset();
    mocks.listDocuments.mockReset();
    mocks.verifyIdToken.mockResolvedValue({
      uid: "uid-1",
      email: "admin@restaurante.com",
      role: undefined,
    });
    mocks.getDocument.mockResolvedValue(null);
    mocks.listDocuments.mockResolvedValue([]);
  });

  it("acepta el claim de administrador sin consultar Firestore", async () => {
    mocks.verifyIdToken.mockResolvedValue({
      uid: "uid-1",
      email: "admin@restaurante.com",
      role: "admin",
    });

    const identity = await verifyAdminIdToken("token");

    expect(identity.role).toBe("admin");
    expect(identity.roleSource).toBe("claim");
    expect(mocks.getDocument).not.toHaveBeenCalled();
  });

  it("usa el rol del documento users/{uid} cuando no hay claim", async () => {
    mocks.getDocument.mockResolvedValue({ role: "admin" });

    const identity = await verifyAdminIdToken("token");

    expect(identity.role).toBe("admin");
    expect(identity.roleSource).toBe("firestore");
    expect(mocks.getDocument).toHaveBeenCalledWith(
      "tenants/mania/users",
      "uid-1",
      0,
    );
  });

  it("busca por email cuando el documento por uid no existe", async () => {
    mocks.listDocuments.mockResolvedValue([
      { uid: "otro", email: "ADMIN@RESTAURANTE.COM", role: "admin" },
    ]);

    const identity = await verifyAdminIdToken("token");

    expect(identity.role).toBe("admin");
    expect(identity.roleSource).toBe("firestore");
  });

  it("devuelve el rol real de Firestore aunque no sea admin", async () => {
    mocks.getDocument.mockResolvedValue({ role: "waiter" });

    const identity = await verifyAdminIdToken("token");

    expect(identity.role).toBe("waiter");
    expect(identity.roleSource).toBe("firestore");
  });

  it("devuelve roleSource none si no hay rol en token ni en Firestore", async () => {
    const identity = await verifyAdminIdToken("token");

    expect(identity.role).toBeUndefined();
    expect(identity.roleSource).toBe("none");
  });
});
