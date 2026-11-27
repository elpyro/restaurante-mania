"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import {
  CircleCheck,
  Clock,
  House,
  MapPin,
  MessageCircle,
  ReceiptText,
  Search,
  Star,
  Wallet,
} from "lucide-react";
import { formatCOP, formatDateTime } from "@/lib/format";
import {
  ORDER_STATUS_LABELS,
  ORDER_TYPE_LABELS,
  PAYMENT_METHOD_LABELS,
  type Order,
  type OrderStatus,
} from "@/lib/types";
import { whatsappUrl } from "@/lib/site";
import { DEFAULT_TENANT_ID, withTenant } from "@/lib/tenants";
import {
  getClientTenantId,
  tenantFetchHeaders,
  tenantStorageKey,
} from "@/lib/client-tenant";

function timelineFor(type: Order["type"]): OrderStatus[] {
  return type === "delivery"
    ? ["pending", "confirmed", "preparing", "ready", "sent"]
    : ["pending", "confirmed", "preparing", "ready", "delivered"];
}

function readStoredOrder(id: string): Order | null {
  try {
    const direct = window.sessionStorage.getItem(
      tenantStorageKey(getClientTenantId(), `rm_order_${id}`),
    );
    if (direct) return JSON.parse(direct) as Order;
    const raw = window.localStorage.getItem(
      tenantStorageKey(getClientTenantId(), "rm_orders_v1"),
    );
    if (!raw) return null;
    const orders = JSON.parse(raw) as Order[];
    return orders.find((order) => order.id === id) ?? null;
  } catch {
    return null;
  }
}

interface Props {
  id: string;
  whatsapp: string;
  restaurantName: string;
  googlePlaceUrl?: string | null;
}

export function OrderConfirmation({ id, whatsapp, restaurantName, googlePlaceUrl }: Props) {
  const [tenantId, setTenantId] = useState(DEFAULT_TENANT_ID);
  const [order, setOrder] = useState<Order | null>(null);
  useEffect(() => { setTenantId(getClientTenantId()); }, []);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    const fetchOrder = async () => {
      try {
        const response = await fetch(`/api/orders/${encodeURIComponent(id)}`, {
          cache: "no-store",
          headers: tenantFetchHeaders(),
        });
        if (!response.ok) return;
        const payload = (await response.json()) as { order?: Order };
        if (!cancelled && payload.order) setOrder(payload.order);
      } catch {
        // Mantener el último estado conocido si falla el polling.
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    const stored = readStoredOrder(id);
    if (stored) {
      setOrder(stored);
      setLoading(false);
    }

    void fetchOrder();
    const timer = window.setInterval(() => {
      if (document.visibilityState === "visible") void fetchOrder();
    }, 8000);

    return () => {
      cancelled = true;
      window.clearInterval(timer);
    };
  }, [id]);

  if (loading && !order) {
    return <div className="skeleton h-72" />;
  }

  if (!order) {
    return (
      <div className="surface-card border-dashed p-12 text-center">
        <span className="mx-auto grid h-16 w-16 place-items-center rounded-3xl bg-brand-50 text-brand">
          <Search size={28} aria-hidden />
        </span>
        <h2 className="mt-4 font-display text-2xl font-bold text-ink">
          No encontramos ese pedido
        </h2>
        <p className="mt-2 text-sm text-ink-muted">
          Puede que el enlace haya expirado. Escríbenos por WhatsApp y lo
          revisamos contigo.
        </p>
        <div className="mt-6 flex flex-wrap justify-center gap-3">
          <Link
            href={withTenant("/menu", tenantId)}
            className="btn-primary"
          >
            Volver al menú
          </Link>
          <a
            href={whatsappUrl(undefined, whatsapp, restaurantName)}
            target="_blank"
            rel="noopener noreferrer"
            className="rounded-full border border-line px-5 py-2.5 text-sm font-semibold text-ink-soft hover:bg-surface-muted"
          >
            WhatsApp
          </a>
        </div>
      </div>
    );
  }

  const timeline = timelineFor(order.type);
  const currentIndex = timeline.indexOf(order.status);
  const cancelled = order.status === "cancelled";
  const allDone =
    !cancelled &&
    (order.status === "sent" ||
      order.status === "delivered" ||
      currentIndex === timeline.length - 1);
  const message = `Hola, acabo de hacer el pedido ${order.code} a nombre de ${order.customerName}. Total: ${formatCOP(order.total)}.`;

  return (
    <div className="space-y-6">
      <section className="relative overflow-hidden rounded-4xl border border-accent-soft bg-gradient-to-br from-accent-soft to-surface-raised p-6 sm:p-8">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <p className="inline-flex items-center gap-2 rounded-full bg-accent px-3 py-1 text-xs font-bold uppercase tracking-wide text-white">
              <CircleCheck size={13} aria-hidden /> Pedido recibido
            </p>
            <h2 className="mt-3 font-display text-3xl font-bold text-ink">
              ¡Gracias, {order.customerName.split(" ")[0]}!
            </h2>
            <p className="mt-2 text-sm text-ink-soft">
              Tu pedido <strong>{order.code}</strong> quedó registrado. La cocina
              lo verá en tiempo real en la app administrativa.
            </p>
          </div>
          <div className="rounded-2xl border border-accent-soft bg-surface-raised p-4 text-sm">
            <p className="text-ink-muted">Total del pedido</p>
            <p className="text-2xl font-bold text-brand-700">
              {formatCOP(order.total)}
            </p>
            <p className="mt-1 text-xs text-ink-muted">
              {PAYMENT_METHOD_LABELS[order.paymentMethod]} · {ORDER_TYPE_LABELS[order.type]}
            </p>
          </div>
        </div>

        <a
          href={whatsappUrl(message, whatsapp, restaurantName)}
          target="_blank"
          rel="noopener noreferrer"
          className="btn-primary mt-5"
        >
          <MessageCircle size={16} aria-hidden /> Enviar comprobante por WhatsApp
        </a>
      </section>

      <section className="surface-card p-5">
        <h3 className="inline-flex items-center gap-2 font-display text-lg font-bold text-ink">
          <Clock size={17} className="text-brand" aria-hidden /> Estado del pedido
        </h3>
        {cancelled ? (
          <p className="mt-3 rounded-xl bg-rose-50 px-4 py-3 text-sm font-medium text-rose-700">
            Este pedido fue cancelado. Contáctanos si necesitas ayuda.
          </p>
        ) : (
          <ol className="mt-4 grid gap-3 sm:grid-cols-5">
            {timeline.map((status, index) => {
              const done = allDone || index <= currentIndex;
              return (
                <li key={status} className="flex items-center gap-2 sm:flex-col sm:text-center">
                  <span
                    className={`grid h-8 w-8 shrink-0 place-items-center rounded-full text-xs font-bold ${
                      done
                        ? "bg-accent text-white"
                        : "bg-surface-muted text-ink-400"
                    }`}
                  >
                    {done ? "✓" : index + 1}
                  </span>
                  <span
                    className={`text-xs font-medium ${
                      done ? "text-ink" : "text-ink-muted"
                    }`}
                  >
                    {ORDER_STATUS_LABELS[status]}
                  </span>
                </li>
              );
            })}
          </ol>
        )}
        <p className="mt-4 text-xs text-ink-muted">
          Creado el {formatDateTime(order.createdAt)}. Estado actual:{" "}
          <strong>{ORDER_STATUS_LABELS[order.status]}</strong>.
        </p>
      </section>

      {googlePlaceUrl ? (
        <section className="surface-card flex flex-col items-start gap-4 p-5 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h3 className="inline-flex items-center gap-2 font-display text-lg font-bold text-ink">
              <Star size={17} className="text-brand" aria-hidden /> Mientras esperas
            </h3>
            <p className="mt-1 text-sm text-ink-muted">
              ¿Te gusta nuestro servicio? Puedes calificar nuestro restaurante en Google.
            </p>
          </div>
          <a
            href={googlePlaceUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="btn-primary shrink-0"
          >
            <Star size={16} aria-hidden /> Calificar en Google
          </a>
        </section>
      ) : null}

      <div className="grid gap-6 md:grid-cols-2">
        <section className="surface-card p-5">
          <h3 className="inline-flex items-center gap-2 font-display text-lg font-bold text-ink">
            <ReceiptText size={17} className="text-brand" aria-hidden /> Productos
          </h3>
          <ul className="mt-3 divide-y divide-stone-100 text-sm">
            {order.items.map((item) => (
              <li key={item.menuItemId} className="flex justify-between gap-3 py-2">
                <span className="flex items-center gap-2 text-ink-soft">
                  {item.imageUrl ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={item.imageUrl}
                      alt={item.name}
                      className="h-9 w-9 rounded-lg object-cover"
                    />
                  ) : (
                    <span className="text-xl">{item.emoji}</span>
                  )}
                  {item.quantity} × {item.name}
                </span>
                <span className="whitespace-nowrap font-medium text-ink">
                  {formatCOP(item.price * item.quantity)}
                </span>
              </li>
            ))}
          </ul>
          <div className="mt-3 flex justify-between border-t border-line pt-3 text-base font-bold">
            <span>Total</span>
            <span className="text-brand-700">{formatCOP(order.total)}</span>
          </div>
          {order.notes ? (
            <p className="mt-3 rounded-xl bg-surface-muted px-3 py-2 text-xs text-ink-soft">
              <strong>Notas:</strong> {order.notes}
            </p>
          ) : null}
        </section>

        <section className="surface-card p-5">
          <h3 className="inline-flex items-center gap-2 font-display text-lg font-bold text-ink">
            <MapPin size={17} className="text-brand" aria-hidden /> Entrega
          </h3>
          <dl className="mt-3 space-y-2 text-sm">
            <div className="flex justify-between gap-3">
              <dt className="text-ink-muted">Modalidad</dt>
              <dd className="font-medium text-ink">{ORDER_TYPE_LABELS[order.type]}</dd>
            </div>
            {order.tableNumber ? (
              <div className="flex justify-between gap-3">
                <dt className="text-ink-muted">Mesa</dt>
                <dd className="font-medium text-ink">{order.tableNumber}</dd>
              </div>
            ) : null}
            {order.deliveryAddress ? (
              <div className="flex justify-between gap-3">
                <dt className="text-ink-muted">Dirección</dt>
                <dd className="text-right font-medium text-ink">{order.deliveryAddress}</dd>
              </div>
            ) : null}
            <div className="flex justify-between gap-3">
              <dt className="text-ink-muted">Teléfono</dt>
              <dd className="font-medium text-ink">{order.customerPhone}</dd>
            </div>
            <div className="flex justify-between gap-3">
              <dt className="inline-flex items-center gap-1.5 text-ink-muted">
                <Wallet size={13} aria-hidden /> Pago
              </dt>
              <dd className="font-medium text-ink">
                {PAYMENT_METHOD_LABELS[order.paymentMethod]}
              </dd>
            </div>
            <div className="flex justify-between gap-3">
              <dt className="text-ink-muted">Código</dt>
              <dd className="font-mono text-xs font-semibold text-ink">
                {order.code}
              </dd>
            </div>
          </dl>
          <div className="mt-4 flex flex-wrap gap-2">
            <Link
              href={withTenant("/menu", tenantId)}
              className="btn-primary !px-4 !py-2 text-xs"
            >
              Pedir algo más
            </Link>
            <Link
              href={withTenant("/", tenantId)}
              className="rounded-full border border-line px-4 py-2 text-xs font-semibold text-ink-soft hover:bg-surface-muted"
            >
              <House size={14} aria-hidden /> Inicio
            </Link>
          </div>
        </section>
      </div>
    </div>
  );
}
