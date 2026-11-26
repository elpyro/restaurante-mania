import { NextResponse } from "next/server";
import { getPublicMenu } from "@/lib/menu";
import { getRestaurantConfig } from "@/lib/restaurant-config";
import { resolveTenantFromRequest } from "@/lib/tenants";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const tenantId = resolveTenantFromRequest(request);
  const [menu, { config }] = await Promise.all([
    getPublicMenu(tenantId),
    getRestaurantConfig(tenantId),
  ]);
  return NextResponse.json(
    {
      tenantId,
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
