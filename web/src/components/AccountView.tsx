"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import {
  ArrowRight,
  Clock,
  MapPin,
  Phone,
  ReceiptText,
  ShoppingBag,
  UserRound,
} from "lucide-react";
import {
  DEFAULT_TENANT_ID,
  withTenant,
} from "@/lib/tenants";
import {
  getClientTenantId,
  tenantStorageKey,
} from "@/lib/client-tenant";
import { formatCOP, formatDateTime } from "@/lib/format";
import { ORDER_STATUS_LABELS, type Order } from "@/lib/types";

function profileKey(): string {
  return tenantStorageKey(getClientTenantId(), "rm_customer_profile_v1");
}
function ordersKey(): string {
  return tenantStorageKey(getClientTenantId(), "rm_orders_v1");
}

type Profile = {
  customerName: string;
  customerPhone: string;
  deliveryAddress: string;
  addresses: string[];
  updatedAt?: string;
};

function loadProfile(): Profile | null {
  try {
    const raw = window.localStorage.getItem(profileKey());
    if (!raw) return null;
    const p = JSON.parse(raw) as Partial<Profile>;
    const addresses = Array.isArray(p.addresses)
      ? p.addresses.filter((a): a is string => typeof a === "string" && a.trim().length > 0)
      : p.deliveryAddress?.trim()
        ? [p.deliveryAddress.trim()]
        : [];
    if (!p.customerPhone && !p.customerName) return null;
    return {
      customerName: String(p.customerName ?? ""),
      customerPhone: String(p.customerPhone ?? ""),
      deliveryAddress: String(p.deliveryAddress ?? ""),
      addresses,
      updatedAt: typeof p.updatedAt === "string" ? p.updatedAt : undefined,
    };
  } catch {
    return null;
  }
}

function loadOrders(): Order[] {
  try {
    const raw = window.localStorage.getItem(ordersKey());
    if (!raw) return [];
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((o): o is Order => !!o && typeof o === "object" && typeof (o as Order).id === "string");
  } catch {
    return [];
  }
}

export function AccountView() {
  const [tenantId, setTenantId] = useState(DEFAULT_TENANT_ID);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [orders, setOrders] = useState<Order[]>([]);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    setTenantId(getClientTenantId());
    setProfile(loadProfile());
    setOrders(loadOrders());
    setReady(true);
  }, []);

  if (!ready) return <div className="skeleton h-64" />;

  if (!profile) {
    return (
      <div className="surface-card border-dashed p-12 text-center">
        <span className="mx-auto grid h-16 w-16 place-items-center rounded-3xl bg-brand-50 text-brand">
          <UserRound size={28} aria-hidden />
        </span>
        <h2 className="mt-4 font-display text-2xl font-bold text-ink">Aún no tienes perfil registrado</h2>
        <p className="mt-2 text-sm text-ink-muted">
          Cuando hagas tu primer pedido, guardaremos tus datos en este dispositivo para reconocerte.
        </p>
        <Link href={withTenant("/menu", tenantId)} className="btn-primary mt-6">
          Ver menú
        </Link>
      </div>
    );
  }

  const phoneDigits = profile.customerPhone.replace(/\D/g, "");
  const myOrders = orders.filter((o) => {
    const oPhone = (o.customerPhone || "").replace(/\D/g, "");
    return phoneDigits.length >= 7 && oPhone === phoneDigits;
  });
  const displayOrders = myOrders.length > 0 ? myOrders : orders;

  return (
    <div className="grid gap-6 lg:grid-cols-[1fr_1.3fr]">
      <section className="surface-card p-5">
        <div className="flex items-center gap-3">
          <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-brand-100 text-lg font-bold text-brand-strong">
            {(profile.customerName || "C").trim().charAt(0).toUpperCase()}
          </div>
          <div>
            <p className="inline-flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-brand-strong">
              <UserRound size={12} aria-hidden /> Cliente registrado
            </p>
            <h2 className="font-display text-xl font-bold text-ink">{profile.customerName || "Cliente"}</h2>
          </div>
        </div>
        <dl className="mt-5 space-y-3 text-sm">
          <div>
            <dt className="inline-flex items-center gap-1.5 text-ink-muted">
              <Phone size={13} aria-hidden /> Teléfono
            </dt>
            <dd className="font-medium text-ink">{profile.customerPhone || "No registrado"}</dd>
          </div>
          <div>
            <dt className="inline-flex items-center gap-1.5 text-ink-muted">
              <MapPin size={13} aria-hidden /> Dirección principal
            </dt>
            <dd className="font-medium text-ink">{profile.deliveryAddress || "No registrada"}</dd>
          </div>
          <div>
            <dt className="text-ink-muted">Direcciones usadas</dt>
            <dd className="mt-1 space-y-1">
              {profile.addresses.length > 0 ? (
                profile.addresses.map((a) => (
                  <div key={a} className="rounded-lg bg-surface-muted px-3 py-2 text-ink-soft">{a}</div>
                ))
              ) : (
                <span className="text-ink-400">Sin direcciones guardadas</span>
              )}
            </dd>
            <p className="mt-2 text-xs text-ink-muted">
              Por seguridad, la dirección solo se puede cambiar al hacer un nuevo pedido.
            </p>
          </div>
        </dl>
        <Link href={withTenant("/menu", tenantId)} className="btn-primary mt-6 !px-4 !py-2">
          Hacer nuevo pedido
        </Link>
      </section>

      <section className="surface-card p-5">
        <h2 className="inline-flex items-center gap-2 font-display text-xl font-bold text-ink">
          <ReceiptText size={18} className="text-brand" aria-hidden /> Historial de pedidos
        </h2>
        <p className="mt-1 text-xs text-ink-muted">
          {myOrders.length > 0 ? "Pedidos asociados a tu número telefónico." : "Pedidos guardados en este dispositivo."}
        </p>
        {displayOrders.length === 0 ? (
          <p className="mt-6 text-sm text-ink-muted">Aún no hay pedidos registrados.</p>
        ) : (
          <ul className="mt-4 space-y-3">
            {displayOrders.map((order) => (
              <li key={order.id} className="rounded-2xl border border-line p-4">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="font-semibold text-ink">{order.code}</p>
                    <p className="inline-flex items-center gap-1.5 text-xs text-ink-muted">
                      <Clock size={12} aria-hidden />
                      {formatDateTime(order.createdAt)} · {ORDER_STATUS_LABELS[order.status] ?? order.status}
                    </p>
                  </div>
                  <p className="font-semibold text-brand-strong">{formatCOP(order.total)}</p>
                </div>
                <p className="mt-2 inline-flex items-start gap-1.5 text-xs text-ink-muted">
                  <ShoppingBag size={12} className="mt-0.5 shrink-0" aria-hidden />
                  {order.items.map((i) => `${i.quantity}x ${i.name}`).join(", ")}
                </p>
                <Link href={withTenant(`/order/${order.id}`, tenantId)} className="mt-3 inline-flex text-xs font-semibold text-brand-strong hover:text-brand-800">
                  Ver detalle <ArrowRight size={12} aria-hidden />
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
