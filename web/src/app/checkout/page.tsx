import type { Metadata } from "next";
import { CircleCheck, ReceiptText } from "lucide-react";
import { CheckoutForm } from "@/components/CheckoutForm";

export const metadata: Metadata = {
  title: "Confirmar pedido",
  description: "Completa tus datos para confirmar el pedido.",
  robots: { index: false, follow: false },
};

export default function CheckoutPage() {
  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6 sm:py-14">
      <header className="mb-8 animate-fade-up">
        <span className="chip text-brand-strong">
          <ReceiptText size={14} aria-hidden /> Último paso
        </span>
        <h1 className="section-title mt-4">Confirma tu pedido</h1>
        <p className="mt-2 flex items-center gap-1.5 text-sm text-ink-muted">
          <CircleCheck size={14} className="text-accent" aria-hidden />
          Solo necesitamos tus datos para avisarte cuando esté listo.
        </p>
      </header>
      <CheckoutForm />
    </div>
  );
}
