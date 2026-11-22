import type { Metadata } from "next";
import { CartView } from "@/components/CartView";

export const metadata: Metadata = {
  title: "Tu carrito",
  description: "Revisa los productos de tu pedido antes de confirmar.",
  robots: { index: false, follow: false },
};

export default function CartPage() {
  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6 sm:py-14">
      <header className="mb-8">
        <p className="text-xs font-bold uppercase tracking-widest text-brand-700">
          Pedido
        </p>
        <h1 className="section-title mt-1">Tu carrito</h1>
        <p className="mt-2 text-sm text-ink-500">
          Ajusta cantidades y continúa cuando estés listo.
        </p>
      </header>
      <CartView />
    </div>
  );
}
