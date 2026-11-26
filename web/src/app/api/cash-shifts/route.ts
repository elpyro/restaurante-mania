import { NextResponse } from "next/server";

import { getCurrentCashShift, listCashShifts } from "@/lib/cash-shifts";
import { resolveTenantFromRequest } from "@/lib/tenants";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const tenantId = resolveTenantFromRequest(request);
  const [currentShift, shifts] = await Promise.all([
    getCurrentCashShift(tenantId),
    listCashShifts(tenantId),
  ]);
  return NextResponse.json(
    { tenantId, currentShift, shifts },
    { headers: { "Cache-Control": "no-store" } },
  );
}
