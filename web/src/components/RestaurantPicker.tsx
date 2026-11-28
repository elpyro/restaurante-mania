import Link from "next/link";
import { ArrowUpRight } from "lucide-react";

import type { TenantDirectoryEntry } from "@/lib/tenant-directory";
import { withTenant } from "@/lib/tenants";

export function RestaurantPicker({
  tenants,
}: {
  tenants: TenantDirectoryEntry[];
}) {
  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {tenants.map((tenant) => (
        <Link
          key={tenant.id}
          href={withTenant("/", tenant.id)}
          className="group flex min-h-36 flex-col justify-between rounded-3xl border border-line bg-surface-raised/80 p-5 shadow-card transition duration-300 hover:-translate-y-1 hover:border-brand-300 hover:shadow-glow"
        >
          <div className="flex items-start justify-between gap-3">
            <span className="grid h-12 w-12 place-items-center rounded-2xl bg-brand-50 text-2xl">
              {tenant.emoji}
            </span>
            <ArrowUpRight
              size={18}
              aria-hidden
              className="text-ink-muted transition group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-brand-strong"
            />
          </div>
          <div className="mt-5">
            <span className="block font-display text-lg font-bold leading-tight text-ink">
              {tenant.name}
            </span>
            <span className="mt-1 block text-xs font-semibold uppercase tracking-[0.14em] text-ink-muted">
              {tenant.isDefault ? "Casa principal" : tenant.city || "Menú digital"}
            </span>
          </div>
        </Link>
      ))}
    </div>
  );
}
