"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { formatCOP, formatDateTime } from "@/lib/format";
import {
  ORDER_STATUS_LABELS,
  ORDER_TYPE_LABELS,
  PAYMENT_METHOD_LABELS,
  type Order,
  type OrderStatus,
} from "@/lib/types";
import { whatsappUrl } from "@/lib/site";

function timelineFor(type: Order["type"]): OrderStatus[] {
  return type === "delivery"
    ? ["pending", "confirmed", "preparing", "ready", "sent"]
    : ["pending", "confirmed", "preparing", "ready", "delivered"];
}

function readStoredOrder(id: string): Order | null {
  try {
    const direct = window.sessionStorage.getItem(`rm_order_${id}`);
    if (direct) return JSON.parse(direct) as Order;
    const raw = window.localStorage.getItem("rm_orders_v1");
    if (!raw) return null;
    const orders = JSON.parse(raw) as Order[];
    return orders.find((order) => order.id === id) ?? null;
  } catch {
    return null;
  }
}

export function OrderConfirmation({ id }: { id: string }) {
  const [order, setOrder] = useState<Order | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    const fetchOrder = async () => {
      try {
        const response = await fetch(`/api/orders/${encodeURIComponent(id)}`, {
          cache: "no-store",
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
    return <div className="h-72 animate-pulse rounded-3xl bg-stone-200" />;
  }

  if (!order) {
    return (
      <div className="rounded-3xl border border-dashed border-stone-300 bg-white p-12 text-center">
        <p className="text-5xl">🔎</p>
        <h2 className="mt-4 font-display text-2xl font-bold text-ink-900">
          No encontramos ese pedido
        </h2>
        <p className="mt-2 text-sm text-ink-500">
          Puede que el enlace haya expirado. Escríbenos por WhatsApp y lo
          revisamos contigo.
        </p>
        <div className="mt-6 flex flex-wrap justify-center gap-3">
          <Link
            href="/menu"
            className="rounded-full bg-brand-600 px-5 py-2.5 text-sm font-semibold text-white hover:bg-brand-700"
          >
            Volver al menú
          </Link>
          <a
            href={whatsappUrl()}
            target="_blank"
            rel="noopener noreferrer"
            className="rounded-full border border-stone-300 px-5 py-2.5 text-sm font-semibold text-ink-700 hover:bg-stone-100"
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
      <section className="overflow-hidden rounded-3xl border border-emerald-200 bg-gradient-to-br from-emerald-50 to-white p-6 sm:p-8">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <p className="inline-flex items-center gap-2 rounded-full bg-emerald-100 px-3 py-1 text-xs font-bold uppercase tracking-wide text-emerald-800">
              ✓ Pedido recibido
            </p>
            <h2 className="mt-3 font-display text-3xl font-bold text-ink-900">
              ¡Gracias, {order.customerName.split(" ")[0]}!
            </h2>
            <p className="mt-2 text-sm text-ink-700">
              Tu pedido <strong>{order.code}</strong> quedó registrado. La cocina
              lo verá en tiempo real en la app administrativa.
            </p>
          </div>
          <div className="rounded-2xl border border-emerald-200 bg-white p-4 text-sm">
            <p className="text-ink-500">Total del pedido</p>
            <p className="text-2xl font-bold text-brand-700">
              {formatCOP(order.total)}
            </p>
            <p className="mt-1 text-xs text-ink-500">
              {PAYMENT_METHOD_LABELS[order.paymentMethod]} · {ORDER_TYPE_LABELS[order.type]}
            </p>
          </div>
        </div>

        <a
          href={whatsappUrl(message)}
          target="_blank"
          rel="noopener noreferrer"
          className="mt-5 inline-flex rounded-full bg-emerald-600 px-5 py-2.5 text-sm font-semibold text-white hover:bg-emerald-700"
        >
          Enviar comprobante por WhatsApp
        </a>
      </section>

      <section className="rounded-2xl border border-stone-200 bg-white p-5">
        <h3 className="font-display text-lg font-bold text-ink-900">
          Estado del pedido
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
                        ? "bg-emerald-600 text-white"
                        : "bg-stone-200 text-stone-500"
                    }`}
                  >
                    {done ? "✓" : index + 1}
                  </span>
                  <span
                    className={`text-xs font-medium ${
                      done ? "text-ink-900" : "text-ink-500"
                    }`}
                  >
                    {ORDER_STATUS_LABELS[status]}
                  </span>
                </li>
              );
            })}
          </ol>
        )}
        <p className="mt-4 text-xs text-ink-500">
          Creado el {formatDateTime(order.createdAt)}. Estado actual:{" "}
          <strong>{ORDER_STATUS_LABELS[order.status]}</strong>.
        </p>
      </section>

      <div className="grid gap-6 md:grid-cols-2">
        <section className="rounded-2xl border border-stone-200 bg-white p-5">
          <h3 className="font-display text-lg font-bold text-ink-900">Productos</h3>
          <ul className="mt-3 divide-y divide-stone-100 text-sm">
            {order.items.map((item) => (
              <li key={item.menuItemId} className="flex justify-between gap-3 py-2">
                <span className="flex items-center gap-2 text-ink-700">
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
                <span className="whitespace-nowrap font-medium text-ink-900">
                  {formatCOP(item.price * item.quantity)}
                </span>
              </li>
            ))}
          </ul>
          <div className="mt-3 flex justify-between border-t border-stone-200 pt-3 text-base font-bold">
            <span>Total</span>
            <span className="text-brand-700">{formatCOP(order.total)}</span>
          </div>
          {order.notes ? (
            <p className="mt-3 rounded-xl bg-stone-50 px-3 py-2 text-xs text-ink-700">
              <strong>Notas:</strong> {order.notes}
            </p>
          ) : null}
        </section>

        <section className="rounded-2xl border border-stone-200 bg-white p-5">
          <h3 className="font-display text-lg font-bold text-ink-900">Entrega</h3>
          <dl className="mt-3 space-y-2 text-sm">
            <div className="flex justify-between gap-3">
              <dt className="text-ink-500">Modalidad</dt>
              <dd className="font-medium text-ink-900">{ORDER_TYPE_LABELS[order.type]}</dd>
            </div>
            {order.tableNumber ? (
              <div className="flex justify-between gap-3">
                <dt className="text-ink-500">Mesa</dt>
                <dd className="font-medium text-ink-900">{order.tableNumber}</dd>
              </div>
            ) : null}
            {order.deliveryAddress ? (
              <div className="flex justify-between gap-3">
                <dt className="text-ink-500">Dirección</dt>
                <dd className="text-right font-medium text-ink-900">{order.deliveryAddress}</dd>
              </div>
            ) : null}
            <div className="flex justify-between gap-3">
              <dt className="text-ink-500">Teléfono</dt>
              <dd className="font-medium text-ink-900">{order.customerPhone}</dd>
            </div>
            <div className="flex justify-between gap-3">
              <dt className="text-ink-500">Pago</dt>
              <dd className="font-medium text-ink-900">
                {PAYMENT_METHOD_LABELS[order.paymentMethod]}
              </dd>
            </div>
            <div className="flex justify-between gap-3">
              <dt className="text-ink-500">Código</dt>
              <dd className="font-mono text-xs font-semibold text-ink-900">
                {order.code}
              </dd>
            </div>
          </dl>
          <div className="mt-4 flex flex-wrap gap-2">
            <Link
              href="/menu"
              className="rounded-full bg-brand-600 px-4 py-2 text-xs font-semibold text-white hover:bg-brand-700"
            >
              Pedir algo más
            </Link>
            <Link
              href="/"
              className="rounded-full border border-stone-300 px-4 py-2 text-xs font-semibold text-ink-700 hover:bg-stone-100"
            >
              Inicio
            </Link>
          </div>
        </section>
      </div>
    </div>
  );
}
