import { NextResponse } from "next/server";
import { getPublicMenu } from "@/lib/menu";
import { getRestaurantConfig } from "@/lib/restaurant-config";

export const dynamic = "force-dynamic";

export async function GET() {
  const [menu, { config }] = await Promise.all([
    getPublicMenu(),
    getRestaurantConfig(),
  ]);
  return NextResponse.json(
    {
      restaurant: config.name,
      slogan: config.slogan,
      currency: "COP",
      source: menu.source,
      categories: menu.categories,
      items: menu.items,
    },
    { headers: { "Cache-Control": "no-store" } },
  );
}
