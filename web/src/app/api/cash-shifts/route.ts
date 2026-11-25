import { NextResponse } from "next/server";

import { getCurrentCashShift, listCashShifts } from "@/lib/cash-shifts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  const [currentShift, shifts] = await Promise.all([
    getCurrentCashShift(),
    listCashShifts(),
  ]);
  return NextResponse.json(
    { currentShift, shifts },
    { headers: { "Cache-Control": "no-store" } },
  );
}
