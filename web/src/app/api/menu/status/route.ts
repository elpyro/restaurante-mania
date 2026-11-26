import { NextResponse } from "next/server";
import { getDemoState } from "@/lib/demo-store";
import {
  isFirestoreConfigured,
  listDocuments,
  tenantPath,
} from "@/lib/firebase/rest";
import { getMenu } from "@/lib/menu";
import { resolveTenantFromRequest } from "@/lib/tenants";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Estado de todos los platos, incluidos los agotados, para reconciliar la app. */
export async function GET(request: Request) {
  const tenantId = resolveTenantFromRequest(request);
  const menu = await getMenu(tenantId);

  type Detail = { manualStatus: string | null; statusReason: string | null };
  let details = new Map<string, Detail>();
  if (!isFirestoreConfigured()) {
    for (const item of getDemoState(tenantId).items) {
      const extra = item as typeof item & Partial<Detail>;
      details.set(item.id, {
        manualStatus: extra.manualStatus ?? null,
        statusReason: extra.statusReason ?? null,
      });
    }
  } else {
    const documents = await listDocuments(
      tenantPath(tenantId, "menuItems"),
      (doc) => ({
        id: doc.id,
        manualStatus: doc.data.manualStatus === "unavailable" ? "unavailable" : null,
        statusReason:
          typeof doc.data.statusReason === "string" ? doc.data.statusReason : null,
      }),
      0,
    );
    details = new Map(documents.map((doc) => [doc.id, doc]));
  }

  return NextResponse.json(
    {
      tenantId,
      items: menu.items.map((item) => ({
        id: item.id,
        status: item.status,
        manualStatus: details.get(item.id)?.manualStatus ?? null,
        statusReason: details.get(item.id)?.statusReason ?? null,
      })),
    },
    { headers: { "Cache-Control": "no-store" } },
  );
}
