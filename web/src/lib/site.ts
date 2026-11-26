export const siteConfig = {
  name: process.env.NEXT_PUBLIC_RESTAURANT_NAME ?? "Restaurante Manía",
  description:
    "Cocina colombiana de autor, pedidos en línea y reservas. Pide tu mesa o domicilio en minutos.",
  phone: process.env.NEXT_PUBLIC_RESTAURANT_PHONE ?? "+57 300 123 4567",
  whatsapp: process.env.NEXT_PUBLIC_RESTAURANT_WHATSAPP ?? "573001234567",
  address:
    process.env.NEXT_PUBLIC_RESTAURANT_ADDRESS ?? "Calle 10 # 43-12, Medellín",
  city: process.env.NEXT_PUBLIC_RESTAURANT_CITY ?? "Medellín",
  hours: process.env.NEXT_PUBLIC_RESTAURANT_HOURS ?? "11:00 - 22:00",
  siteUrl:
    process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/$/, "") ??
    "http://localhost:3000",
  currency: "COP",
  country: "CO",
};

export function whatsappUrl(
  message?: string,
  whatsapp = siteConfig.whatsapp,
  name = siteConfig.name,
): string {
  const text =
    message ?? `Hola ${name}, quiero hacer un pedido o una reserva.`;
  return `https://wa.me/${whatsapp}?text=${encodeURIComponent(text)}`;
}

export function absoluteUrl(path = "/"): string {
  return `${siteConfig.siteUrl}${path.startsWith("/") ? path : `/${path}`}`;
}
