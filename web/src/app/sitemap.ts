import type { MetadataRoute } from "next";
import { getPublicMenu } from "@/lib/menu";
import { getRestaurantConfig } from "@/lib/restaurant-config";
import { absoluteUrl } from "@/lib/site";

export const dynamic = "force-dynamic";

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const [{ items }, { config }] = await Promise.all([
    getPublicMenu(),
    getRestaurantConfig(),
  ]);
  const now = new Date();
  const configuredAt = config.updatedAt ? new Date(config.updatedAt) : null;
  const homeModified =
    configuredAt && !Number.isNaN(configuredAt.getTime()) ? configuredAt : now;

  return [
    {
      url: absoluteUrl("/"),
      lastModified: homeModified,
      changeFrequency: "weekly",
      priority: 1,
    },
    {
      url: absoluteUrl("/menu"),
      lastModified: now,
      changeFrequency: "daily",
      priority: 0.9,
    },
    ...items.map((item) => ({
      url: absoluteUrl(`/menu/${item.slug}`),
      lastModified: now,
      changeFrequency: "weekly" as const,
      priority: 0.7,
    })),
  ];
}
