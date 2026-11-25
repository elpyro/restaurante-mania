import { NextResponse } from "next/server";

import {
  CashShiftValidationError,
  closeCashShift,
} from "@/lib/cash-shifts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "JSON inválido." }, { status: 400 });
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return NextResponse.json({ error: "Cuerpo inválido." }, { status: 400 });
  }
  const payload = (body as Record<string, unknown>).shift ?? body;
  try {
    const result = await closeCashShift(payload);
    return NextResponse.json(result, {
      headers: { "Cache-Control": "no-store" },
    });
  } catch (error) {
    if (error instanceof CashShiftValidationError) {
      return NextResponse.json({ errors: error.errors }, { status: 400 });
    }
    console.error("[api/cash-shifts] No se pudo cerrar el turno:", error);
    return NextResponse.json(
      { error: "No se pudo cerrar el turno." },
      { status: 500 },
    );
  }
}
