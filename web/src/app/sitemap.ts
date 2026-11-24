import type { MetadataRoute } from "next";
import { getPublicMenu } from "@/lib/menu";
import { absoluteUrl } from "@/lib/site";

export const dynamic = "force-dynamic";

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const { items } = await getPublicMenu();
  const now = new Date();

  return [
    {
      url: absoluteUrl("/"),
      lastModified: now,
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
