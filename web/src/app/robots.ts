import type { MetadataRoute } from "next";
import { absoluteUrl } from "@/lib/site";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: ["/", "/menu", "/llms.txt", "/sitemap.xml"],
        disallow: ["/api/", "/cart", "/checkout", "/cuenta", "/order/"],
      },
      {
        userAgent: ["GPTBot", "ChatGPT-User", "PerplexityBot", "Google-Extended"],
        allow: ["/", "/menu", "/llms.txt"],
      },
    ],
    sitemap: absoluteUrl("/sitemap.xml"),
    host: absoluteUrl("/"),
  };
}
