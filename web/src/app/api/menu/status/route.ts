import { NextResponse } from "next/server";
import { listDocuments } from "@/lib/firebase/rest";
import { getMenu } from "@/lib/menu";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Estado de todos los platos, incluidos los agotados, para reconciliar la app. */
export async function GET() {
  const [menu, documents] = await Promise.all([
    getMenu(),
    listDocuments(
      "menuItems",
      (doc) => ({
        id: doc.id,
        manualStatus:
          doc.data.manualStatus === "unavailable" ? "unavailable" : null,
        statusReason:
          typeof doc.data.statusReason === "string"
            ? doc.data.statusReason
            : null,
      }),
      0,
    ),
  ]);
  const details = new Map(documents.map((doc) => [doc.id, doc]));
  return NextResponse.json(
    {
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
