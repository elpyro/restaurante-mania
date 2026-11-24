import { NextResponse } from "next/server";
import { getMenu } from "@/lib/menu";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Estado de todos los platos, incluidos los agotados, para reconciliar la app. */
export async function GET() {
  const { items } = await getMenu();
  return NextResponse.json(
    {
      items: items.map((item) => ({ id: item.id, status: item.status })),
    },
    { headers: { "Cache-Control": "no-store" } },
  );
}
