import { NextResponse } from "next/server";
import { getPublicMenu } from "@/lib/menu";

export const revalidate = 60;

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
    { headers: { "Cache-Control": "public, s-maxage=60, stale-while-revalidate=300" } },
  );
}
