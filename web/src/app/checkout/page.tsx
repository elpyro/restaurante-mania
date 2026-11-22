import type { Metadata } from "next";
import { CheckoutForm } from "@/components/CheckoutForm";

export const metadata: Metadata = {
  title: "Confirmar pedido",
  description: "Completa tus datos para confirmar el pedido.",
  robots: { index: false, follow: false },
};

export default function CheckoutPage() {
  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6 sm:py-14">
      <header className="mb-8">
        <p className="text-xs font-bold uppercase tracking-widest text-brand-700">
          Último paso
        </p>
        <h1 className="section-title mt-1">Confirma tu pedido</h1>
        <p className="mt-2 text-sm text-ink-500">
          Solo necesitamos tus datos para avisarte cuando esté listo.
        </p>
      </header>
      <CheckoutForm />
    </div>
  );
}
