import { describe, expect, it } from "vitest";
import { openingStatus, zonedTime } from "../opening-hours";
import {
  DEFAULT_RESTAURANT_CONFIG,
  formatOpeningHours,
  isValidTimeZone,
} from "../restaurant-config";

const config = {
  isOpen: true,
  timeZone: "America/Bogota",
  openingDays: DEFAULT_RESTAURANT_CONFIG.openingDays,
  openTime: DEFAULT_RESTAURANT_CONFIG.openTime,
  closeTime: DEFAULT_RESTAURANT_CONFIG.closeTime,
};

describe("estado de apertura de la portada", () => {
  it("respeta la zona horaria configurada", () => {
    expect(isValidTimeZone("America/Bogota")).toBe(true);
    expect(isValidTimeZone("Europe/Madrid")).toBe(true);
    expect(isValidTimeZone("UTC")).toBe(true);
    expect(isValidTimeZone("No/Zona")).toBe(false);
    expect(zonedTime(new Date("2026-11-26T17:00:00Z"), "UTC").minutes).toBe(
      17 * 60,
    );
    expect(
      zonedTime(new Date("2026-11-26T17:00:00Z"), "America/Bogota").minutes,
    ).toBe(12 * 60);
  });

  it("muestra «Abierto: recibiendo pedidos» dentro del horario", () => {
    const status = openingStatus(config, new Date("2026-11-26T17:00:00Z"));
    expect(status).toEqual({
      isOpen: true,
      label: "Abierto",
      detail: "Recibiendo pedidos",
      full: "Abierto: Recibiendo pedidos",
    });
  });

  it("muestra la hora de apertura cuando aún no abre", () => {
    const status = openingStatus(config, new Date("2026-11-26T16:00:00Z"));
    expect(status.full).toBe("Cerrado: abre a las 11:30");
  });

  it("anuncia el siguiente día hábil cuando cerró o es domingo", () => {
    const night = openingStatus(config, new Date("2026-11-26T02:00:00Z"));
    expect(night.full).toBe("Cerrado: abre el jueves a las 11:30");
    const sunday = openingStatus(config, new Date("2026-11-29T17:00:00Z"));
    expect(sunday.full).toBe("Cerrado: abre el lunes a las 11:30");
  });

  it("permite forzar el cierre sin bloquear pedidos", () => {
    const status = openingStatus(
      { ...config, isOpen: false },
      new Date("2026-11-26T17:00:00Z"),
    );
    expect(status.isOpen).toBe(false);
    expect(status.full).toBe("Cerrado: abre a las 11:30");
  });

  it("deriva el texto corto del horario estructurado", () => {
    expect(formatOpeningHours(DEFAULT_RESTAURANT_CONFIG)).toBe(
      "Lun–Sáb 11:30–20:30",
    );
    expect(
      formatOpeningHours({
        ...DEFAULT_RESTAURANT_CONFIG,
        openingDays: ["mon", "tue", "wed", "thu", "fri", "sat", "sun"],
      }),
    ).toBe("Todos los días 11:30–20:30");
  });
});
