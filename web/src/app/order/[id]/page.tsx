import type { Metadata } from "next";
import { Bell, QrCode } from "lucide-react";
import { OrderConfirmation } from "@/components/OrderConfirmation";
import { getRestaurantConfig } from "@/lib/restaurant-config";
import { getServerTenantId } from "@/lib/tenant-server";

export const metadata: Metadata = {
  title: "Estado del pedido",
  robots: { index: false, follow: false },
};

export default async function OrderPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const tenantId = await getServerTenantId();
  const [{ id }, { config }] = await Promise.all([
    params,
    getRestaurantConfig(tenantId),
  ]);
  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6 sm:py-14">
      <header className="mb-8 animate-fade-up">
        <span className="chip text-brand-strong">
          <QrCode size={14} aria-hidden /> Pedido en curso
        </span>
        <h1 className="section-title mt-4">Sigue tu pedido</h1>
        <p className="mt-2 flex items-center gap-1.5 text-sm text-ink-muted">
          <Bell size={14} aria-hidden /> Actualizamos el estado automáticamente.
        </p>
      </header>
      <OrderConfirmation
        id={id}
        whatsapp={config.whatsapp}
        restaurantName={config.name}
      />
    </div>
  );
}
