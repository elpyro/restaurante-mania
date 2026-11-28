import type { MetadataRoute } from "next";
import { getPublicMenu } from "@/lib/menu";
import { getRestaurantConfig } from "@/lib/restaurant-config";
import { absoluteUrl } from "@/lib/site";
import { getServerTenantId } from "@/lib/tenant-server";
import { getTenantDirectory } from "@/lib/tenant-directory";
import { withTenant } from "@/lib/tenants";

export const dynamic = "force-dynamic";

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const [tenantId, tenants] = await Promise.all([
    getServerTenantId(),
    getTenantDirectory(),
  ]);
  const [{ items }, { config }] = await Promise.all([
    getPublicMenu(tenantId),
    getRestaurantConfig(tenantId),
  ]);
  const now = new Date();
  const configuredAt = config.updatedAt ? new Date(config.updatedAt) : null;
  const homeModified =
    configuredAt && !Number.isNaN(configuredAt.getTime()) ? configuredAt : now;

  return [
    {
      url: absoluteUrl("/"),
      lastModified: now,
      changeFrequency: "weekly",
      priority: 1,
    },
    ...tenants.flatMap((tenant) => [
      {
        url: absoluteUrl(withTenant("/", tenant.id)),
        lastModified: homeModified,
        changeFrequency: "weekly" as const,
        priority: tenant.isDefault ? 0.9 : 0.8,
      },
      {
        url: absoluteUrl(withTenant("/menu", tenant.id)),
        lastModified: now,
        changeFrequency: "daily" as const,
        priority: 0.7,
      },
    ]),
    ...items.map((item) => ({
      url: absoluteUrl(withTenant(`/menu/${item.slug}`, tenantId)),
      lastModified: now,
      changeFrequency: "weekly" as const,
      priority: 0.7,
    })),
  ];
}
