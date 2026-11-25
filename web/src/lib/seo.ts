import {
  DEFAULT_RESTAURANT_CONFIG,
  SOCIAL_NETWORKS,
  type RestaurantConfig,
} from "./restaurant-config";
import { absoluteUrl, siteConfig } from "./site";
import type { Category, MenuItem } from "./types";

type JsonLd = Record<string, unknown>;

function openingHours(config: RestaurantConfig) {
  const [opens, closes] = config.hours.split("-").map((part) => part.trim());
  return {
    "@type": "OpeningHoursSpecification",
    dayOfWeek: [
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday",
      "Sunday",
    ],
    opens: opens || "11:00",
    closes: closes || "22:00",
  };
}

export function restaurantJsonLd(
  config: RestaurantConfig = DEFAULT_RESTAURANT_CONFIG,
): JsonLd {
  const socialProfiles = SOCIAL_NETWORKS.map(
    (network) => config.appearance.socialLinks?.[network],
  ).filter((url): url is string => Boolean(url));
  const aiKeywords = [
    config.aiSearch.keywords ?? "",
    config.aiSearch.highlights ?? "",
  ]
    .map((value) => value.trim())
    .filter(Boolean)
    .join(", ");

  return {
    "@context": "https://schema.org",
    "@type": "Restaurant",
    "@id": absoluteUrl("/#restaurant"),
    name: config.name,
    description: config.aiSearch.description?.trim() || config.slogan,
    slogan: config.heroBadge,
    url: absoluteUrl("/"),
    telephone: config.phone,
    servesCuisine: ["Colombiana", "Latinoamericana"],
    priceRange: "$$",
    currenciesAccepted: siteConfig.currency,
    paymentAccepted: "Efectivo, Tarjeta, Nequi, Daviplata",
    ...(aiKeywords ? { keywords: aiKeywords } : {}),
    ...(config.aiSearch.serviceArea?.trim()
      ? { areaServed: config.aiSearch.serviceArea.trim() }
      : {}),
    ...(socialProfiles.length > 0 ? { sameAs: socialProfiles } : {}),
    ...(config.appearance.gpsUrl ? { hasMap: config.appearance.gpsUrl } : {}),
    address: {
      "@type": "PostalAddress",
      streetAddress: config.address,
      addressLocality: config.city,
      addressCountry: siteConfig.country,
    },
    openingHoursSpecification: openingHours(config),
    hasMenu: absoluteUrl("/menu"),
    acceptsReservations: true,
  };
}

export function websiteJsonLd(
  config: RestaurantConfig = DEFAULT_RESTAURANT_CONFIG,
): JsonLd {
  return {
    "@context": "https://schema.org",
    "@type": "WebSite",
    name: config.name,
    url: absoluteUrl("/"),
    inLanguage: "es-CO",
    potentialAction: {
      "@type": "SearchAction",
      target: `${absoluteUrl("/menu")}?q={search_term_string}`,
      "query-input": "required name=search_term_string",
    },
  };
}

export function menuJsonLd(
  categories: Category[],
  items: MenuItem[],
  config: RestaurantConfig = DEFAULT_RESTAURANT_CONFIG,
): JsonLd {
  return {
    "@context": "https://schema.org",
    "@type": "Menu",
    "@id": absoluteUrl("/menu#menu"),
    name: `Menú de ${config.name}`,
    url: absoluteUrl("/menu"),
    inLanguage: "es-CO",
    hasMenuSection: categories.map((category) => ({
      "@type": "MenuSection",
      name: category.name,
      description: category.description,
      hasMenuItem: items
        .filter((item) => item.categoryId === category.id)
        .map((item) => ({
          "@type": "MenuItem",
          name: item.name,
          description: item.description,
          url: absoluteUrl(`/menu/${item.slug}`),
          suitableForDiet:
            item.allergens.length === 0
              ? "https://schema.org/VegetarianDiet"
              : undefined,
          offers: {
            "@type": "Offer",
            price: item.price,
            priceCurrency: siteConfig.currency,
            availability:
              item.status === "available"
                ? "https://schema.org/InStock"
                : "https://schema.org/LimitedAvailability",
          },
        })),
    })),
  };
}

export function menuItemJsonLd(
  item: MenuItem,
  category: Category,
  config: RestaurantConfig = DEFAULT_RESTAURANT_CONFIG,
): JsonLd {
  return {
    "@context": "https://schema.org",
    "@type": "MenuItem",
    "@id": absoluteUrl(`/menu/${item.slug}#menuitem`),
    name: item.name,
    description: item.description,
    url: absoluteUrl(`/menu/${item.slug}`),
    menuAddOn: item.ingredients,
    suitableForDiet:
      item.allergens.length === 0
        ? "https://schema.org/VegetarianDiet"
        : undefined,
    offers: {
      "@type": "Offer",
      price: item.price,
      priceCurrency: siteConfig.currency,
      availability:
        item.status === "available"
          ? "https://schema.org/InStock"
          : "https://schema.org/LimitedAvailability",
      url: absoluteUrl(`/menu/${item.slug}`),
    },
    isPartOf: {
      "@type": "MenuSection",
      name: category.name,
      url: absoluteUrl(`/menu#${category.slug}`),
    },
    nutrition: {
      "@type": "NutritionInformation",
      calories: `${item.calories} calories`,
    },
    seller: {
      "@type": "Restaurant",
      name: config.name,
      url: absoluteUrl("/"),
    },
  };
}

export function breadcrumbJsonLd(
  crumbs: Array<{ name: string; path: string }>,
): JsonLd {
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: crumbs.map((crumb, index) => ({
      "@type": "ListItem",
      position: index + 1,
      name: crumb.name,
      item: absoluteUrl(crumb.path),
    })),
  };
}
