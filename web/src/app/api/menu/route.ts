import { NextResponse } from "next/server";
import { getPublicMenu } from "@/lib/menu";

export const dynamic = "force-dynamic";

export async function GET() {
  const menu = await getPublicMenu();
  return NextResponse.json(
    {
      restaurant: "Restaurante Manía",
      currency: "COP",
      source: menu.source,
      categories: menu.categories,
      items: menu.items,
    },
    { headers: { "Cache-Control": "no-store" } },
  );
}
