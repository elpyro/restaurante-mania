import { describe, expect, it } from "vitest";
import { dayKeyFor, normalizeDayKey, visitDocumentId } from "../visit-identity";

describe("identidad de visitas web", () => {
  it("calcula el día en America/Bogota", () => {
    expect(dayKeyFor(new Date("2026-11-24T02:30:00.000Z"))).toBe("2026-11-23");
    expect(dayKeyFor(new Date("2026-11-24T05:30:00.000Z"))).toBe("2026-11-24");
  });

  it("genera el mismo ID para el mismo visitante y día", () => {
    const first = visitDocumentId("phone:3001234567", "2026-11-24");
    const second = visitDocumentId("phone:3001234567", "2026-11-24");
    expect(first).toBe(second);
    expect(first).toMatch(/^vis_2026-11-24_[0-9a-f]{8}$/);
  });

  it("cambia el ID al cambiar de día o de visitante", () => {
    const today = visitDocumentId("visitor_abc12345", "2026-11-24");
    expect(visitDocumentId("visitor_abc12345", "2026-11-25")).not.toBe(today);
    expect(visitDocumentId("visitor_xyz98765", "2026-11-24")).not.toBe(today);
  });

  it("normaliza días inválidos", () => {
    expect(normalizeDayKey("no-es-un-dia", new Date("2026-11-24T05:30:00.000Z"))).toBe(
      "2026-11-24",
    );
  });
});
