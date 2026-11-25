import { describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  closeCashShift: vi.fn(),
}));

vi.mock("@/lib/cash-shifts", () => ({
  closeCashShift: mocks.closeCashShift,
  CashShiftValidationError: class CashShiftValidationError extends Error {
    errors: string[];
    constructor(errors: string[]) {
      super(errors.join(" "));
      this.errors = errors;
    }
  },
}));

import { POST } from "../route";

describe("POST /api/cash-shifts/close", () => {
  it("devuelve el turno nuevo para que la app lo adopte", async () => {
    mocks.closeCashShift.mockReset();
    const currentShift = { id: "shift-2", status: "open" };
    mocks.closeCashShift.mockResolvedValue({
      shift: { id: "shift-1", status: "closed" },
      currentShift,
      shifts: [],
    });

    const response = await POST(
      new Request("http://localhost/api/cash-shifts/close", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ shift: { id: "shift-1", openedAt: "2026-11-24T10:00:00Z" } }),
      }),
    );

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.currentShift).toEqual(currentShift);
    expect(mocks.closeCashShift).toHaveBeenCalledWith({
      id: "shift-1",
      openedAt: "2026-11-24T10:00:00Z",
    });
  });

  it("rechaza JSON inválido", async () => {
    const response = await POST(
      new Request("http://localhost/api/cash-shifts/close", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: "{",
      }),
    );
    expect(response.status).toBe(400);
  });
});
