import type { Metadata, Viewport } from "next";
import "./globals.css";
import { CartProvider } from "@/components/CartProvider";
import { Footer } from "@/components/Footer";
import { Header } from "@/components/Header";
import { VisitTracker } from "@/components/VisitTracker";
import { siteConfig } from "@/lib/site";

export const metadata: Metadata = {
  metadataBase: new URL(siteConfig.siteUrl),
  title: {
    default: `${siteConfig.name} | Cocina colombiana y pedidos en línea`,
    template: `%s | ${siteConfig.name}`,
  },
  description: siteConfig.description,
  applicationName: siteConfig.name,
  keywords: [
    "restaurante",
    "comida colombiana",
    "pedidos en línea",
    "domicilio",
    "Medellín",
    "bandeja paisa",
    "ajiaco",
    "menú",
  ],
  authors: [{ name: siteConfig.name }],
  creator: siteConfig.name,
  openGraph: {
    type: "website",
    locale: "es_CO",
    url: "/",
    siteName: siteConfig.name,
    title: `${siteConfig.name} | Cocina colombiana y pedidos en línea`,
    description: siteConfig.description,
    images: [
      {
        url: "/og.svg",
        width: 1200,
        height: 630,
        alt: `${siteConfig.name} — cocina colombiana`,
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: `${siteConfig.name} | Cocina colombiana`,
    description: siteConfig.description,
    images: ["/og.svg"],
  },
  robots: {
    index: true,
    follow: true,
    googleBot: { index: true, follow: true, "max-image-preview": "large" },
  },
  alternates: { canonical: "/" },
  icons: { icon: "/favicon.svg", apple: "/favicon.svg" },
};

export const viewport: Viewport = {
  themeColor: "#c64b09",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="es-CO">
      <body>
        <CartProvider>
          <VisitTracker />
          <Header />
          <main className="min-h-[70vh]">{children}</main>
          <Footer />
        </CartProvider>
      </body>
    </html>
  );
}
