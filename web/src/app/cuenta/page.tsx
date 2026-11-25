import type { Metadata } from "next";
import { Clock, UserRound } from "lucide-react";
import { AccountView } from "@/components/AccountView";
import { getRestaurantConfig } from "@/lib/restaurant-config";

export async function generateMetadata(): Promise<Metadata> {
  const { config } = await getRestaurantConfig();
  return {
    title: "Mi cuenta",
    description: `Consulta tu perfil y el historial de pedidos en ${config.name}.`,
    robots: { index: false, follow: false },
  };
}

export default function AccountPage() {
  return (
    <div className="mx-auto max-w-5xl px-4 py-10 sm:px-6">
      <span className="chip text-brand-strong">
        <UserRound size={14} aria-hidden /> Mi cuenta
      </span>
      <h1 className="mt-4 font-display text-4xl font-bold text-ink">
        Tu perfil y pedidos
      </h1>
      <p className="mt-2 flex items-center gap-1.5 text-sm text-ink-muted">
        <Clock size={14} aria-hidden />
        Datos guardados en este dispositivo para agilizar tus próximos pedidos.
      </p>
      <div className="mt-8">
        <AccountView />
      </div>
    </div>
  );
}
