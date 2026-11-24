"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { formatCOP, formatDateTime } from "@/lib/format";
import type { Order } from "@/lib/types";

const PROFILE_KEY = "rm_customer_profile_v1";
const ORDERS_KEY = "rm_orders_v1";

type Profile = {
  customerName: string;
  customerPhone: string;
  deliveryAddress: string;
  addresses: string[];
  updatedAt?: string;
};

function loadProfile(): Profile | null {
  try {
    const raw = window.localStorage.getItem(PROFILE_KEY);
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
    const raw = window.localStorage.getItem(ORDERS_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((o): o is Order => !!o && typeof o === "object" && typeof (o as Order).id === "string");
  } catch {
    return [];
  }
}

export function AccountView() {
  const [profile, setProfile] = useState<Profile | null>(null);
  const [orders, setOrders] = useState<Order[]>([]);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    setProfile(loadProfile());
    setOrders(loadOrders());
    setReady(true);
  }, []);

  if (!ready) return <div className="h-64 animate-pulse rounded-2xl bg-stone-200" />;

  if (!profile) {
    return (
      <div className="rounded-3xl border border-dashed border-stone-300 bg-white p-12 text-center">
        <p className="text-5xl">👤</p>
        <h2 className="mt-4 font-display text-2xl font-bold text-ink-900">Aún no tienes perfil registrado</h2>
        <p className="mt-2 text-sm text-ink-500">
          Cuando hagas tu primer pedido, guardaremos tus datos en este dispositivo para reconocerte.
        </p>
        <Link href="/menu" className="mt-6 inline-flex rounded-full bg-brand-600 px-5 py-2.5 text-sm font-semibold text-white hover:bg-brand-700">
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
      <section className="rounded-2xl border border-stone-200 bg-white p-5">
        <div className="flex items-center gap-3">
          <div className="flex h-12 w-12 items-center justify-center rounded-full bg-brand-100 text-lg font-bold text-brand-700">
            {(profile.customerName || "C").trim().charAt(0).toUpperCase()}
          </div>
          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-brand-600">Cliente registrado</p>
            <h2 className="font-display text-xl font-bold text-ink-900">{profile.customerName || "Cliente"}</h2>
          </div>
        </div>
        <dl className="mt-5 space-y-3 text-sm">
          <div>
            <dt className="text-ink-500">Teléfono</dt>
            <dd className="font-medium text-ink-900">{profile.customerPhone || "No registrado"}</dd>
          </div>
          <div>
            <dt className="text-ink-500">Dirección principal</dt>
            <dd className="font-medium text-ink-900">{profile.deliveryAddress || "No registrada"}</dd>
          </div>
          <div>
            <dt className="text-ink-500">Direcciones usadas</dt>
            <dd className="mt-1 space-y-1">
              {profile.addresses.length > 0 ? (
                profile.addresses.map((a) => (
                  <div key={a} className="rounded-lg bg-stone-50 px-3 py-2 text-ink-700">{a}</div>
                ))
              ) : (
                <span className="text-ink-400">Sin direcciones guardadas</span>
              )}
            </dd>
            <p className="mt-2 text-xs text-ink-500">
              Por seguridad, la dirección solo se puede cambiar al hacer un nuevo pedido.
            </p>
          </div>
        </dl>
        <Link href="/menu" className="mt-6 inline-flex rounded-full bg-brand-600 px-4 py-2 text-sm font-semibold text-white hover:bg-brand-700">
          Hacer nuevo pedido
        </Link>
      </section>

      <section className="rounded-2xl border border-stone-200 bg-white p-5">
        <h2 className="font-display text-xl font-bold text-ink-900">Historial de pedidos</h2>
        <p className="mt-1 text-xs text-ink-500">
          {myOrders.length > 0 ? "Pedidos asociados a tu número telefónico." : "Pedidos guardados en este dispositivo."}
        </p>
        {displayOrders.length === 0 ? (
          <p className="mt-6 text-sm text-ink-500">Aún no hay pedidos registrados.</p>
        ) : (
          <ul className="mt-4 space-y-3">
            {displayOrders.map((order) => (
              <li key={order.id} className="rounded-xl border border-stone-200 p-4">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="font-semibold text-ink-900">{order.code}</p>
                    <p className="text-xs text-ink-500">{formatDateTime(order.createdAt)} · {order.status}</p>
                  </div>
                  <p className="font-semibold text-brand-700">{formatCOP(order.total)}</p>
                </div>
                <p className="mt-2 text-xs text-ink-500">
                  {order.items.map((i) => `${i.quantity}x ${i.name}`).join(", ")}
                </p>
                <Link href={`/order/${order.id}`} className="mt-3 inline-flex text-xs font-semibold text-brand-700 hover:text-brand-800">
                  Ver detalle →
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
