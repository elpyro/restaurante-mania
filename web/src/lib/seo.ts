import {
  DEFAULT_RESTAURANT_CONFIG,
  SOCIAL_NETWORKS,
  WEEKDAYS,
  type RestaurantConfig,
  type Weekday,
} from "./restaurant-config";
import { absoluteUrl, siteConfig } from "./site";
import { DEFAULT_TENANT_ID, withTenant } from "./tenants";
import type { Category, MenuItem } from "./types";

type JsonLd = Record<string, unknown>;

function tenantUrl(path: string, tenantId: string): string {
  return absoluteUrl(withTenant(path, tenantId));
}

const FULL_WEEKDAYS: Record<Weekday, string> = {
  mon: "Monday",
  tue: "Tuesday",
  wed: "Wednesday",
  thu: "Thursday",
  fri: "Friday",
  sat: "Saturday",
  sun: "Sunday",
};

function openingHours(config: RestaurantConfig) {
  const days = config.openingDays.length > 0 ? config.openingDays : WEEKDAYS;
  return {
    "@type": "OpeningHoursSpecification",
    dayOfWeek: WEEKDAYS.filter((day) => days.includes(day)).map(
      (day) => FULL_WEEKDAYS[day],
    ),
    opens: config.openTime,
    closes: config.closeTime,
  };
}

export function restaurantJsonLd(
  config: RestaurantConfig = DEFAULT_RESTAURANT_CONFIG,
  tenantId = DEFAULT_TENANT_ID,
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
    "@id": tenantUrl("/#restaurant", tenantId),
    name: config.name,
    description: config.aiSearch.description?.trim() || config.slogan,
    slogan: config.heroBadge,
    url: tenantUrl("/", tenantId),
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
    hasMenu: tenantUrl("/menu", tenantId),
    acceptsReservations: true,
  };
}

export function websiteJsonLd(
  config: RestaurantConfig = DEFAULT_RESTAURANT_CONFIG,
  tenantId = DEFAULT_TENANT_ID,
): JsonLd {
  return {
    "@context": "https://schema.org",
    "@type": "WebSite",
    name: config.name,
    url: tenantUrl("/", tenantId),
    inLanguage: "es-CO",
    potentialAction: {
      "@type": "SearchAction",
      target: `${tenantUrl("/menu", tenantId)}?q={search_term_string}`,
      "query-input": "required name=search_term_string",
    },
  };
}

export function menuJsonLd(
  categories: Category[],
  items: MenuItem[],
  config: RestaurantConfig = DEFAULT_RESTAURANT_CONFIG,
  tenantId = DEFAULT_TENANT_ID,
): JsonLd {
  return {
    "@context": "https://schema.org",
    "@type": "Menu",
    "@id": tenantUrl("/menu#menu", tenantId),
    name: `Menú de ${config.name}`,
    url: tenantUrl("/menu", tenantId),
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
          url: tenantUrl(`/menu/${item.slug}`, tenantId),
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
  tenantId = DEFAULT_TENANT_ID,
): JsonLd {
  return {
    "@context": "https://schema.org",
    "@type": "MenuItem",
    "@id": tenantUrl(`/menu/${item.slug}#menuitem`, tenantId),
    name: item.name,
    description: item.description,
    url: tenantUrl(`/menu/${item.slug}`, tenantId),
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
      url: tenantUrl(`/menu/${item.slug}`, tenantId),
    },
    isPartOf: {
      "@type": "MenuSection",
      name: category.name,
      url: tenantUrl(`/menu#${category.slug}`, tenantId),
    },
    nutrition: {
      "@type": "NutritionInformation",
      calories: `${item.calories} calories`,
    },
    seller: {
      "@type": "Restaurant",
      name: config.name,
      url: tenantUrl("/", tenantId),
    },
  };
}

export function breadcrumbJsonLd(
  crumbs: Array<{ name: string; path: string }>,
  tenantId = DEFAULT_TENANT_ID,
): JsonLd {
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: crumbs.map((crumb, index) => ({
      "@type": "ListItem",
      position: index + 1,
      name: crumb.name,
      item: tenantUrl(crumb.path, tenantId),
    })),
  };
}
