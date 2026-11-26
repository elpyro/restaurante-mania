import Link from "next/link";
import { ArrowLeft, UtensilsCrossed } from "lucide-react";
import { getServerTenantId } from "@/lib/tenant-server";
import { withTenant } from "@/lib/tenants";

export default async function NotFound() {
  const tenantId = await getServerTenantId();
  return (
    <div className="mx-auto flex max-w-xl flex-col items-center px-4 py-20 text-center sm:px-6">
      <div className="surface-card w-full animate-fade-up p-8 sm:p-10">
        <span className="mx-auto grid h-14 w-14 place-items-center rounded-2xl bg-brand-50 text-brand-strong">
          <UtensilsCrossed size={26} aria-hidden />
        </span>
        <p className="eyebrow mt-6">Error 404</p>
        <h1 className="section-title mt-2 text-2xl">No encontramos ese plato</h1>
        <p className="mt-3 text-sm leading-relaxed text-ink-muted">
          Es posible que el enlace haya cambiado o que el plato ya no esté en el
          menú. Explora el catálogo para seguir pidiendo.
        </p>
        <div className="mt-7 flex flex-wrap justify-center gap-3">
          <Link href={withTenant("/menu", tenantId)} className="btn-primary">
            Ver el menú <ArrowLeft size={16} aria-hidden className="rotate-180" />
          </Link>
          <Link href={withTenant("/", tenantId)} className="btn-secondary">
            Volver al inicio
          </Link>
        </div>
      </div>
    </div>
  );
}
