import { beforeEach, describe, expect, it, vi } from "vitest";

const rest = vi.hoisted(() => ({
  isFirestoreConfigured: vi.fn(() => false),
  listDocuments: vi.fn(),
  setDocument: vi.fn(),
}));

vi.mock("../firebase/rest", () => rest);

import {
  CashShiftValidationError,
  closeCashShift,
  getCurrentCashShift,
  listCashShifts,
  makeCashShift,
  resetCashShiftStoreForTests,
} from "../cash-shifts";

beforeEach(() => {
  resetCashShiftStoreForTests();
  rest.isFirestoreConfigured.mockReturnValue(false);
  rest.listDocuments.mockReset();
  rest.setDocument.mockReset();
});

describe("turnos de caja", () => {
  it("mantiene un único turno abierto mientras no se cierra caja", async () => {
    const first = await getCurrentCashShift();
    const second = await getCurrentCashShift();

    expect(first.status).toBe("open");
    expect(second.id).toBe(first.id);
    expect(await listCashShifts()).toHaveLength(1);
  });

  it("cierra el turno, abre otro y es idempotente por id", async () => {
    const open = await getCurrentCashShift();
    const incoming = {
      ...open,
      status: "closed",
      closedAt: "2026-11-24T15:00:00.000Z",
      closedBy: "u-cashier",
      closedByName: "Andrés Mejía",
      orderCount: 2,
      total: 88000,
      totalsByPaymentMethod: { cash: 58000, card: 30000 },
      closingAmount: 58500,
      notes: "Cierre de prueba",
    };

    const first = await closeCashShift(incoming);
    expect(first.shift.status).toBe("closed");
    expect(first.shift.total).toBe(88000);
    expect(first.currentShift.status).toBe("open");
    expect(first.currentShift.id).not.toBe(first.shift.id);
    expect(first.shifts.filter((shift) => shift.status === "open")).toHaveLength(1);

    const retry = await closeCashShift(incoming);
    expect(retry.shift.id).toBe(first.shift.id);
    expect(retry.currentShift.id).toBe(first.currentShift.id);
    expect(await listCashShifts()).toHaveLength(2);
  });

  it("cierra turnos huérfanos antes de dejar uno abierto", async () => {
    const first = makeCashShift("2026-11-24T10:00:00.000Z");
    const orphan = makeCashShift("2026-11-24T11:00:00.000Z", "u-admin", "Admin");
    await closeCashShift({ ...orphan, status: "open" });
    await closeCashShift({
      ...first,
      status: "closed",
      closedAt: "2026-11-24T12:00:00.000Z",
    });

    const shifts = await listCashShifts();
    expect(shifts.filter((shift) => shift.status === "open")).toHaveLength(1);
  });

  it("rechaza turnos sin id", async () => {
    await expect(closeCashShift({ openedAt: "2026-11-24T10:00:00.000Z" }))
      .rejects.toBeInstanceOf(CashShiftValidationError);
  });
});
