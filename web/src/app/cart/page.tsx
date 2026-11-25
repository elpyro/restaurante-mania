import type { Metadata } from "next";
import { ArrowRight, ShoppingBag } from "lucide-react";
import { CartView } from "@/components/CartView";

export const metadata: Metadata = {
  title: "Tu carrito",
  description: "Revisa los productos de tu pedido antes de confirmar.",
  robots: { index: false, follow: false },
};

export default function CartPage() {
  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6 sm:py-14">
      <header className="mb-8 animate-fade-up">
        <span className="chip text-brand-strong">
          <ShoppingBag size={14} aria-hidden /> Pedido
        </span>
        <h1 className="section-title mt-4">Tu carrito</h1>
        <p className="mt-2 flex items-center gap-1.5 text-sm text-ink-muted">
          Ajusta cantidades y continúa cuando estés listo.
          <ArrowRight size={14} aria-hidden />
        </p>
      </header>
      <CartView />
    </div>
  );
}
