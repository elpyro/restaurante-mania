import { absoluteUrl, siteConfig } from "./site";
import type { Category, MenuItem } from "./types";

type JsonLd = Record<string, unknown>;

export function restaurantJsonLd(): JsonLd {
  return {
    "@context": "https://schema.org",
    "@type": "Restaurant",
    "@id": absoluteUrl("/#restaurant"),
    name: siteConfig.name,
    description: siteConfig.description,
    url: absoluteUrl("/"),
    telephone: siteConfig.phone,
    servesCuisine: ["Colombiana", "Latinoamericana"],
    priceRange: "$$",
    currenciesAccepted: siteConfig.currency,
    paymentAccepted: "Efectivo, Tarjeta, Nequi, Daviplata",
    address: {
      "@type": "PostalAddress",
      streetAddress: siteConfig.address,
      addressLocality: siteConfig.city,
      addressCountry: siteConfig.country,
    },
    openingHoursSpecification: {
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
      opens: siteConfig.hours.split("-")[0]?.trim() ?? "11:00",
      closes: siteConfig.hours.split("-")[1]?.trim() ?? "22:00",
    },
    hasMenu: absoluteUrl("/menu"),
    acceptsReservations: true,
  };
}

export function websiteJsonLd(): JsonLd {
  return {
    "@context": "https://schema.org",
    "@type": "WebSite",
    name: siteConfig.name,
    url: absoluteUrl("/"),
    inLanguage: "es-CO",
    potentialAction: {
      "@type": "SearchAction",
      target: `${absoluteUrl("/menu")}?q={search_term_string}`,
      "query-input": "required name=search_term_string",
    },
  };
}

export function menuJsonLd(categories: Category[], items: MenuItem[]): JsonLd {
  return {
    "@context": "https://schema.org",
    "@type": "Menu",
    "@id": absoluteUrl("/menu#menu"),
    name: `Menú de ${siteConfig.name}`,
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
            item.allergens.length === 0 ? "https://schema.org/VegetarianDiet" : undefined,
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

export function menuItemJsonLd(item: MenuItem, category: Category): JsonLd {
  return {
    "@context": "https://schema.org",
    "@type": "MenuItem",
    "@id": absoluteUrl(`/menu/${item.slug}#menuitem`),
    name: item.name,
    description: item.description,
    url: absoluteUrl(`/menu/${item.slug}`),
    menuAddOn: item.ingredients,
    suitableForDiet:
      item.allergens.length === 0 ? "https://schema.org/VegetarianDiet" : undefined,
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
