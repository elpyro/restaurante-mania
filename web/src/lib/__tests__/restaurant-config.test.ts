import { describe, expect, it } from "vitest";
import {
  APPEARANCE_PRESETS,
  ConfigValidationError,
  DEFAULT_RESTAURANT_CONFIG,
  resolveTheme,
  sanitizeConfigPatch,
  themeForPreset,
  DEFAULT_TIME_ZONE,
  tokensToCssVars,
} from "../restaurant-config";

describe("configuración del restaurante", () => {
  it("define todos los presets con todos los tokens", () => {
    for (const preset of APPEARANCE_PRESETS) {
      const theme = themeForPreset(preset);
      expect(Object.keys(theme).length).toBeGreaterThan(20);
      for (const value of Object.values(theme)) {
        expect(value).toMatch(/^#[0-9a-f]{6}$/i);
      }
    }
  });

  it("convierte el preset a variables CSS de canales RGB", () => {
    const css = tokensToCssVars(DEFAULT_RESTAURANT_CONFIG);
    expect(css).toContain(":root");
    expect(css).toContain("--surface:");
    expect(css).toContain("--brand-600:");
    expect(css).not.toMatch(/#[0-9a-f]{6}/i);
  });

  it("publica moneda, entrega, pagos y estilo propio desde la APK", () => {
    const customColors = {
      brand: "#123456",
      accent: "#abcdef",
      surface: "#ffffff",
      ink: "#101010",
      heroFrom: "#eeeeee",
      heroTo: "#dddddd",
      footer: "#202020",
    };
    const patch = sanitizeConfigPatch({
      countryCode: "+1",
      phone: "300 123 4567",
      city: "Bogotá",
      currency: "usd",
      showOrderTypeOptions: false,
      deliveryOptions: { pickup: false, delivery: true },
      paymentMethods: ["nequi"],
      paymentMethodLabels: { nequi: "Nequi" },
      appearance: {
        preset: "custom",
        bannerUrl: "https://firebasestorage.app/v0/b/bucket/o/banner.gif",
        logoUrl: null,
        customColors,
      },
    });
    expect(patch).toMatchObject({
      countryCode: "+1",
      currency: "USD",
      showOrderTypeOptions: false,
      deliveryOptions: { pickup: false, delivery: true },
      paymentMethods: ["nequi"],
    });
    expect(patch.appearance).toMatchObject({
      preset: "custom",
      bannerUrl: "https://firebasestorage.app/v0/b/bucket/o/banner.gif",
      logoUrl: null,
      customColors,
    });
    const theme = resolveTheme({
      ...DEFAULT_RESTAURANT_CONFIG,
      appearance: { preset: "custom", customColors },
    });
    expect(theme["brand-500"]).toBe("#123456");
    expect(theme["hero-from"]).toBe("#eeeeee");
  });

  it("rechaza imágenes que no vienen de Firebase Storage", () => {
    expect(() =>
      sanitizeConfigPatch({
        appearance: { bannerUrl: "https://ejemplo.com/banner.gif" },
      }),
    ).toThrow(ConfigValidationError);
  });

  it("acepta solo el contrato permitido", () => {
    expect(
      sanitizeConfigPatch({
        name: "  Casa Nueva  ",
        heroBadge: "Abiertos hoy",
        appearance: { preset: "verde" },
        updatedAt: "no se puede escribir",
        secret: "no se puede escribir",
      }),
    ).toEqual({
      name: "Casa Nueva",
      heroBadge: "Abiertos hoy",
      appearance: { preset: "verde" },
    });
  });

  it("publica zona horaria, días, rango y textos del bloque final", () => {
    const patch = sanitizeConfigPatch({
      isOpen: false,
      timeZone: "Europe/Madrid",
      openingDays: ["sun", "mon", "sat", "mon"],
      openTime: "10:00",
      closeTime: "18:30",
      ctaTitle: "  Ven a comer  ",
      ctaDescription: "  Abiertos todo el fin de semana.  ",
    });
    expect(patch).toEqual({
      isOpen: false,
      timeZone: "Europe/Madrid",
      openingDays: ["mon", "sat", "sun"],
      openTime: "10:00",
      closeTime: "18:30",
      ctaTitle: "Ven a comer",
      ctaDescription: "Abiertos todo el fin de semana.",
    });
    expect(DEFAULT_TIME_ZONE).toBe("America/Bogota");
  });

  it("rechaza zonas, días y horarios inválidos", () => {
    expect(() => sanitizeConfigPatch({ timeZone: "Marte/Base" })).toThrow(
      ConfigValidationError,
    );
    expect(() => sanitizeConfigPatch({ openingDays: [] })).toThrow(
      ConfigValidationError,
    );
    expect(() => sanitizeConfigPatch({ openTime: "25:00" })).toThrow(
      ConfigValidationError,
    );
    expect(() =>
      sanitizeConfigPatch({ openTime: "20:00", closeTime: "11:00" }),
    ).toThrow(ConfigValidationError);
  });

  it("normaliza whatsapp y rechaza valores inválidos", () => {
    expect(sanitizeConfigPatch({ whatsapp: "+57 (300) 123-4567" })).toEqual({
      whatsapp: "+573001234567",
    });
    expect(() => sanitizeConfigPatch({ appearance: { preset: "otro" } })).toThrow(
      ConfigValidationError,
    );
    expect(() => sanitizeConfigPatch({ name: "" })).toThrow(ConfigValidationError);
    expect(() => sanitizeConfigPatch({})).toThrow(ConfigValidationError);
  });

  it("publica redes sociales, mapa y datos para IA desde la APK", () => {
    const patch = sanitizeConfigPatch({
      appearance: {
        socialLinks: {
          instagram: "https://instagram.com/mania",
          tiktok: "https://www.tiktok.com/@mania",
          facebook: "",
          desconocida: "https://ejemplo.com",
        },
        gpsUrl: "https://www.google.com/maps/search/?api=1&query=medellin",
      },
      aiSearch: {
        description: "  Comida   colombiana en Medellín  ",
        keywords: "bandeja paisa, ajiaco",
        serviceArea: "Medellín y Ángel",
        highlights: "Pedidos rápidos y frescos",
      },
    });

    expect(patch.appearance?.socialLinks).toEqual({
      instagram: "https://instagram.com/mania",
      tiktok: "https://www.tiktok.com/@mania",
      facebook: null,
    });
    expect(patch.appearance?.gpsUrl).toBe(
      "https://www.google.com/maps/search/?api=1&query=medellin",
    );
    expect(patch.aiSearch).toEqual({
      description: "Comida colombiana en Medellín",
      keywords: "bandeja paisa, ajiaco",
      serviceArea: "Medellín y Ángel",
      highlights: "Pedidos rápidos y frescos",
    });
  });

  it("rechaza enlaces que no son http(s) y textos de IA demasiado largos", () => {
    expect(() =>
      sanitizeConfigPatch({
        appearance: { socialLinks: { instagram: "javascript:alert(1)" } },
      }),
    ).toThrow(ConfigValidationError);
    expect(() =>
      sanitizeConfigPatch({ appearance: { gpsUrl: "ftp://maps.example.com" } }),
    ).toThrow(ConfigValidationError);
    expect(() =>
      sanitizeConfigPatch({ aiSearch: { description: "x".repeat(501) } }),
    ).toThrow(ConfigValidationError);
  });
});
