import type { Metadata } from "next";
import { AccountView } from "@/components/AccountView";

export const metadata: Metadata = {
  title: "Mi cuenta | Restaurante Manía",
  description: "Consulta tu perfil y el historial de pedidos en Restaurante Manía.",
  robots: { index: false, follow: false },
};

export default function AccountPage() {
  return (
    <div className="mx-auto max-w-5xl px-4 py-10 sm:px-6">
      <p className="text-sm font-semibold uppercase tracking-[0.2em] text-brand-600">Mi cuenta</p>
      <h1 className="mt-2 font-display text-4xl font-bold text-ink-900">Tu perfil y pedidos</h1>
      <p className="mt-2 text-sm text-ink-500">
        Aquí puedes ver tus datos guardados, direcciones usadas y el historial de pedidos realizados desde este dispositivo.
      </p>
      <div className="mt-8">
        <AccountView />
      </div>
    </div>
  );
}
