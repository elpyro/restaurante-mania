import type { MetadataRoute } from "next";
import { absoluteUrl } from "@/lib/site";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: ["/", "/menu", "/llms.txt", "/sitemap.xml"],
        disallow: [
          "/api/",
          "/menu/cart",
          "/menu/checkout",
          "/menu/cuenta",
          "/menu/order",
          "/menu/*/cart",
          "/menu/*/checkout",
          "/menu/*/cuenta",
          "/menu/*/order",
        ],
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
