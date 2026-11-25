import type { Metadata, Viewport } from "next";
import { Fraunces, Manrope } from "next/font/google";
import "./globals.css";
import { CartProvider } from "@/components/CartProvider";
import { FloatingCartBar } from "@/components/FloatingCartBar";
import { Footer } from "@/components/Footer";
import { Header } from "@/components/Header";
import { VisitTracker } from "@/components/VisitTracker";
import {
  getRestaurantConfig,
  presetThemeColor,
  tokensToCssVars,
} from "@/lib/restaurant-config";
import { siteConfig } from "@/lib/site";

const sans = Manrope({
  subsets: ["latin"],
  display: "swap",
  variable: "--font-sans",
});

const display = Fraunces({
  subsets: ["latin"],
  display: "swap",
  variable: "--font-display",
});

type RestaurantConfigFromWeb = Awaited<
  ReturnType<typeof getRestaurantConfig>
>["config"];

function socialImage(config: RestaurantConfigFromWeb) {
  const params = new URLSearchParams({
    title: config.heroTitle,
    description: config.slogan,
  });
  return `/api/og?${params.toString()}`;
}

function metadataDescription(config: RestaurantConfigFromWeb) {
  const aiDescription = config.aiSearch.description?.trim();
  return aiDescription || config.heroDescription;
}

function metadataKeywords(config: RestaurantConfigFromWeb) {
  const custom = [
    ...(config.aiSearch.keywords ?? "").split(","),
    config.aiSearch.serviceArea ?? "",
  ]
    .map((value) => value.trim())
    .filter(Boolean);
  return [...new Set([
    "restaurante",
    "comida colombiana",
    "pedidos en línea",
    "domicilio",
    config.city,
    "bandeja paisa",
    "ajiaco",
    "menú",
    ...custom,
  ])];
}

export async function generateMetadata(): Promise<Metadata> {
  const { config } = await getRestaurantConfig();
  const title = `${config.name} | ${config.slogan}`;
  const image = socialImage(config);
  const description = metadataDescription(config);

  return {
    metadataBase: new URL(siteConfig.siteUrl),
    title: {
      default: title,
      template: `%s | ${config.name}`,
    },
    description,
    applicationName: config.name,
    keywords: metadataKeywords(config),
    authors: [{ name: config.name }],
    creator: config.name,
    other: {
      ...(config.aiSearch.serviceArea
        ? { "restaurant:serviceArea": config.aiSearch.serviceArea }
        : {}),
      ...(config.aiSearch.highlights
        ? { "restaurant:highlights": config.aiSearch.highlights }
        : {}),
    },
    openGraph: {
      type: "website",
      locale: "es_CO",
      url: "/",
      siteName: config.name,
      title,
      description,
      images: [
        {
          url: image,
          width: 1200,
          height: 630,
          alt: `${config.name} — ${config.slogan}`,
        },
      ],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: [image],
    },
    robots: {
      index: true,
      follow: true,
      googleBot: { index: true, follow: true, "max-image-preview": "large" },
    },
    alternates: { canonical: "/" },
    icons: { icon: "/favicon.svg", apple: "/favicon.svg" },
  };
}

export async function generateViewport(): Promise<Viewport> {
  const { config } = await getRestaurantConfig();
  return {
    themeColor: presetThemeColor(config),
    width: "device-width",
    initialScale: 1,
  };
}

export default async function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const { config } = await getRestaurantConfig();

  return (
    <html lang="es-CO" className={`${sans.variable} ${display.variable}`}>
      <head>
        <style dangerouslySetInnerHTML={{ __html: tokensToCssVars(config) }} />
      </head>
      <body>
        <CartProvider>
          <VisitTracker />
          <Header config={config} />
          <main className="min-h-[70vh] pb-28 md:pb-24">{children}</main>
          <Footer config={config} />
          <FloatingCartBar />
        </CartProvider>
      </body>
    </html>
  );
}
