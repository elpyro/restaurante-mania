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
    setDocument: vi.fn(),
    getDocument: vi.fn(),
    isFirestoreConfigured: vi.fn(() => false),
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
  setDocument: mocks.setDocument,
  getDocument: mocks.getDocument,
  isFirestoreConfigured: mocks.isFirestoreConfigured,
  tenantPath: mocks.tenantPath,
}));

import { GET, PATCH } from "../route";

function request(body: unknown, authorization?: string) {
  return new Request("http://localhost/api/restaurant/config", {
    method: "PATCH",
    headers: {
      "content-type": "application/json",
      ...(authorization ? { authorization } : {}),
    },
    body: JSON.stringify(body),
  });
}

describe("GET /api/restaurant/config", () => {
  it("expone el contrato público sin secretos", async () => {
    mocks.isFirestoreConfigured.mockReturnValue(false);
    const response = await GET(
      new Request("http://localhost/api/restaurant/config"),
    );
    expect(response.status).toBe(200);
    const payload = await response.json();
    expect(payload.tenantId).toBe("mania");
    expect(payload.configured).toBe(false);
    expect(payload.source).toBe("env");
    expect(payload.config).toMatchObject({
      name: expect.any(String),
      slogan: expect.any(String),
      heroTitle: expect.any(String),
      heroDescription: expect.any(String),
      heroBadge: expect.any(String),
      appearance: { preset: "mania", socialLinks: {} },
      aiSearch: {},
      phone: expect.any(String),
      whatsapp: expect.any(String),
      address: expect.any(String),
      city: expect.any(String),
      hours: expect.any(String),
    });
    expect(payload.config).not.toHaveProperty("updatedAt");
    expect(payload.config).not.toHaveProperty("serviceAccount");
  });
});

describe("PATCH /api/restaurant/config", () => {
  beforeEach(() => {
    mocks.verifyAdminIdToken.mockReset();
    mocks.setDocument.mockReset();
    mocks.getDocument.mockReset();
    mocks.isFirestoreConfigured.mockReturnValue(true);
    mocks.getDocument.mockResolvedValue(null);
    mocks.verifyAdminIdToken.mockResolvedValue({ uid: "admin-1", role: "admin" });
    mocks.setDocument.mockResolvedValue(undefined);
  });

  it("rechaza peticiones sin token", async () => {
    const response = await PATCH(request({ name: "Nuevo nombre" }));
    expect(response.status).toBe(401);
    expect(mocks.setDocument).not.toHaveBeenCalled();
  });

  it("rechaza tokens sin rol admin", async () => {
    mocks.verifyAdminIdToken.mockResolvedValue({ uid: "user-1", role: "client" });
    const response = await PATCH(
      request({ name: "Nuevo nombre" }, "Bearer token"),
    );
    expect(response.status).toBe(403);
    expect(mocks.setDocument).not.toHaveBeenCalled();
  });

  it("devuelve 503 si Firebase Admin no está disponible", async () => {
    mocks.verifyAdminIdToken.mockRejectedValue(
      new mocks.AdminUnavailableError("sin credenciales"),
    );
    const response = await PATCH(request({ name: "Nuevo nombre" }, "Bearer token"));
    expect(response.status).toBe(503);
  });

  it("guarda solo campos permitidos con updatedAt", async () => {
    const response = await PATCH(
      request(
        {
          name: "Nueva Manía",
          slogan: "Sabor de barrio",
          appearance: { preset: "fuego", secret: "no" },
          secret: "no debe guardarse",
        },
        "Bearer token",
      ),
    );
    expect(response.status).toBe(200);
    expect(mocks.verifyAdminIdToken).toHaveBeenCalledWith("token", "mania");
    expect(mocks.setDocument).toHaveBeenCalledTimes(1);
    const [collection, id, data] = mocks.setDocument.mock.calls[0];
    expect(collection).toBe("tenants/mania/restaurant");
    expect(id).toBe("config");
    expect(data).toMatchObject({
      name: "Nueva Manía",
      slogan: "Sabor de barrio",
      appearance: { preset: "fuego" },
    });
    expect(data).not.toHaveProperty("secret");
    expect(data).toHaveProperty("updatedAt");
    expect(new Date(data.updatedAt).toString()).not.toBe("Invalid Date");
  });

  it("fusiona redes, mapa y datos de IA con la configuración remota", async () => {
    mocks.isFirestoreConfigured.mockReturnValue(true);
    mocks.getDocument.mockResolvedValue({
      name: "Manía",
      appearance: {
        preset: "mania",
        socialLinks: { facebook: "https://facebook.com/mania" },
        gpsUrl: "https://maps.example.com/mania",
      },
      aiSearch: { description: "Descripción previa" },
    });

    const response = await PATCH(
      request(
        {
          appearance: {
            socialLinks: { instagram: "https://instagram.com/mania" },
          },
          aiSearch: { keywords: "colombiana, medellín" },
        },
        "Bearer token",
      ),
    );
    expect(response.status).toBe(200);
    const data = mocks.setDocument.mock.calls[0][2];
    expect(data.appearance.socialLinks).toEqual({
      facebook: "https://facebook.com/mania",
      instagram: "https://instagram.com/mania",
    });
    expect(data.appearance.gpsUrl).toBe("https://maps.example.com/mania");
    expect(data.aiSearch).toEqual({
      description: "Descripción previa",
      keywords: "colombiana, medellín",
    });
  });

  it("permite borrar enlaces y textos de IA enviando null", async () => {
    const response = await PATCH(
      request(
        {
          appearance: {
            socialLinks: { facebook: null },
            gpsUrl: null,
          },
          aiSearch: { description: null, keywords: null },
        },
        "Bearer token",
      ),
    );
    expect(response.status).toBe(200);
    const data = mocks.setDocument.mock.calls[0][2];
    expect(data.appearance.socialLinks).toEqual({ facebook: null });
    expect(data.appearance.gpsUrl).toBeNull();
    expect(data.aiSearch).toEqual({ description: null, keywords: null });
  });

  it("valida el preset y rechaza JSON inválido", async () => {
    const invalidPreset = await PATCH(
      request({ appearance: { preset: "rosa" } }, "Bearer token"),
    );
    expect(invalidPreset.status).toBe(400);

    const invalidJson = new Request("http://localhost/api/restaurant/config", {
      method: "PATCH",
      headers: {
        "content-type": "application/json",
        authorization: "Bearer token",
      },
      body: "{",
    });
    const response = await PATCH(invalidJson);
    expect(response.status).toBe(400);
    expect(mocks.setDocument).not.toHaveBeenCalled();
  });
});
