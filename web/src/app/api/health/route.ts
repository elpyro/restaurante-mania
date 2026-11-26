import { NextResponse } from "next/server";
import { isFirestoreConfigured } from "@/lib/firebase/rest";
import { resolveTenantFromRequest } from "@/lib/tenants";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const tenantId = resolveTenantFromRequest(request);
  return NextResponse.json({
    status: "ok",
    service: "restaurante-mania-web",
    tenantId,
    mode: isFirestoreConfigured() ? "firestore" : "demo",
    timestamp: new Date().toISOString(),
  });
}
