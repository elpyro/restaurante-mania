"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  CircleCheck,
  MapPin,
  ReceiptText,
  ShoppingBag,
  Truck,
  UserRound,
  UtensilsCrossed,
  Wallet,
  type LucideIcon,
} from "lucide-react";
import { useCart } from "./CartProvider";
import { DEFAULT_TENANT_ID, withTenant } from "@/lib/tenants";
import {
  getClientTenantId,
  tenantFetchHeaders,
  tenantStorageKey,
} from "@/lib/client-tenant";
import { formatMoney } from "@/lib/format";
import {
  DEFAULT_RESTAURANT_CONFIG,
  toPublicRestaurantConfig,
  type PublicRestaurantConfig,
} from "@/lib/restaurant-config";
import type { Order, OrderType, PaymentMethod } from "@/lib/types";

const typeOptions: Array<{ value: OrderType; label: string; icon: LucideIcon }> = [
  { value: "pickup", label: "Para recoger", icon: ShoppingBag },
  { value: "delivery", label: "Domicilio", icon: Truck },
  { value: "table", label: "En mesa", icon: UtensilsCrossed },
];

const paymentOptions: Array<{ value: PaymentMethod; label: string }> = [
  { value: "cash", label: "Efectivo" },
  { value: "card", label: "Tarjeta" },
  { value: "nequi", label: "Nequi" },
  { value: "daviplata", label: "Daviplata" },
];

function customerProfileKey(): string {
  return tenantStorageKey(getClientTenantId(), "rm_customer_profile_v1");
}
function ordersKey(): string {
  return tenantStorageKey(getClientTenantId(), "rm_orders_v1");
}
function lastOrderKey(): string {
  return tenantStorageKey(getClientTenantId(), "rm_last_order_id");
}
function orderKey(id: string): string {
  return tenantStorageKey(getClientTenantId(), `rm_order_${id}`);
}

type InsufficientItem = {
  menuItemId: string;
  name: string;
  requested: number;
  available: number;
};

export function CheckoutForm() {
  const router = useRouter();
  const [tenantId, setTenantId] = useState(DEFAULT_TENANT_ID);
  useEffect(() => { setTenantId(getClientTenantId()); }, []);
  const { lines, totals, ready, clear, adjustForStock } = useCart();
  const [customerName, setCustomerName] = useState("");
  const [customerPhone, setCustomerPhone] = useState("");
  const [deliveryAddress, setDeliveryAddress] = useState("");
  const [type, setType] = useState<OrderType>("pickup");
  const [tableNumber, setTableNumber] = useState("1");
  const [paymentMethod, setPaymentMethod] = useState<PaymentMethod>("cash");
  const [notes, setNotes] = useState("");
  const [errors, setErrors] = useState<string[]>([]);
  const [submitting, setSubmitting] = useState(false);
  const [profileLoaded, setProfileLoaded] = useState(false);
  const [savedAddresses, setSavedAddresses] = useState<string[]>([]);
  const [insufficientItems, setInsufficientItems] = useState<InsufficientItem[]>([]);
  const [stockInsufficient, setStockInsufficient] = useState<InsufficientItem[]>([]);
  const [stockErrors, setStockErrors] = useState<string[]>([]);
  const [stockChecking, setStockChecking] = useState(false);
  const [stockAlert, setStockAlert] = useState<InsufficientItem[] | null>(null);
  const [config, setConfig] = useState<PublicRestaurantConfig>(() =>
    toPublicRestaurantConfig(DEFAULT_RESTAURANT_CONFIG),
  );
  const alertButtonRef = useRef<HTMLButtonElement>(null);

  // La configuración la publica la APK; aquí solo leemos la política vigente.
  useEffect(() => {
    let active = true;
    fetch("/api/restaurant/config", { cache: "no-store", headers: tenantFetchHeaders() })
      .then((response) => (response.ok ? response.json() : null))
      .then((data: { config?: PublicRestaurantConfig } | null) => {
        if (!active || !data?.config) return;
        const next = data.config;
        setConfig(next);
        const enabledTypes = typeOptions.filter(
          (option) => next.deliveryOptions[option.value],
        );
        const firstType = enabledTypes[0]?.value ?? "pickup";
        setType((current) =>
          next.deliveryOptions[current] ? current : firstType,
        );
        const firstPayment = next.paymentMethods[0] ?? "cash";
        setPaymentMethod((current) =>
          next.paymentMethods.includes(current) ? current : firstPayment,
        );
      })
      .catch(() => {
        /* sin configuración: se conservan los valores por defecto */
      });
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(customerProfileKey());
      if (!raw) return;
      const profile = JSON.parse(raw) as {
        customerName?: string;
        customerPhone?: string;
        deliveryAddress?: string;
        addresses?: string[];
      };
      if (profile.customerName) setCustomerName(profile.customerName);
      if (profile.customerPhone) setCustomerPhone(profile.customerPhone);
      if (profile.deliveryAddress) setDeliveryAddress(profile.deliveryAddress);
      if (Array.isArray(profile.addresses)) {
        setSavedAddresses(
          profile.addresses.filter((a): a is string => typeof a === "string" && a.trim().length > 0),
        );
      } else if (profile.deliveryAddress?.trim()) {
        setSavedAddresses([profile.deliveryAddress.trim()]);
      }
      if (profile.customerPhone) setProfileLoaded(true);
    } catch {
      /* ignorar perfil inválido */
    }
  }, []);

  const applyInsufficientItems = useCallback(
    (items: InsufficientItem[]) => {
      if (items.length === 0) return;
      adjustForStock(
        items.map((item) => ({
          menuItemId: item.menuItemId,
          available: item.available,
        })),
      );
      setInsufficientItems(items);
      setStockAlert(items);
      setStockInsufficient([]);
      setStockErrors([]);
    },
    [adjustForStock],
  );

  useEffect(() => {
    if (!stockAlert) return;
    alertButtonRef.current?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setStockAlert(null);
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [stockAlert]);

  // Verificación temprana: bloquea el botón de confirmación en cuanto el
  // carrito cambia, sin esperar a que el cliente intente enviar el pedido.
  useEffect(() => {
    if (!ready || lines.length === 0) {
      setStockInsufficient([]);
      setStockErrors([]);
      setStockChecking(false);
      return;
    }
    const controller = new AbortController();
    const timer = window.setTimeout(async () => {
      setStockChecking(true);
      try {
        const response = await fetch("/api/orders/validate", {
          method: "POST",
          headers: { "Content-Type": "application/json", ...tenantFetchHeaders() },
          body: JSON.stringify({
            stockOnly: true,
            items: lines.map((line) => ({
              menuItemId: line.menuItemId,
              quantity: line.quantity,
            })),
          }),
          signal: controller.signal,
        });
        const data = (await response.json()) as {
          errors?: string[];
          insufficientItems?: InsufficientItem[];
        };
        if (controller.signal.aborted) return;
        const insufficient = data.insufficientItems ?? [];
        if (insufficient.length > 0) {
          applyInsufficientItems(insufficient);
        } else {
          setStockInsufficient([]);
          setStockErrors(data.errors ?? []);
        }
      } catch {
        if (!controller.signal.aborted) {
          setStockInsufficient([]);
          setStockErrors([]);
        }
      } finally {
        if (!controller.signal.aborted) setStockChecking(false);
      }
    }, 300);
    return () => {
      controller.abort();
      window.clearTimeout(timer);
    };
  }, [ready, lines, applyInsufficientItems]);

  const enabledTypeOptions = typeOptions.filter(
    (option) => config.deliveryOptions[option.value],
  );
  const visibleTypeOptions = config.showOrderTypeOptions
    ? enabledTypeOptions
    : enabledTypeOptions.slice(0, 1);
  const visiblePaymentOptions = paymentOptions.filter((option) =>
    config.paymentMethods.includes(option.value),
  );
  const money = (value: number) => formatMoney(value, config.currency);

  if (!ready) {
    return <div className="skeleton h-64" />;
  }

  if (lines.length === 0) {
    return (
      <div className="surface-card border-dashed p-12 text-center">
        <p className="text-5xl">🧾</p>
        <h2 className="mt-4 font-display text-2xl font-bold text-ink">
          No hay productos para confirmar
        </h2>
        <p className="mt-2 text-sm text-ink-muted">
          Agrega algo del menú antes de continuar con el pedido.
        </p>
        <Link
          href={withTenant("/menu", tenantId)}
          className="btn-primary mt-6"
        >
          Ir al menú
        </Link>
      </div>
    );
  }

  function validate(): string[] {
    const found: string[] = [];
    const isTable = type === "table";
    if (!isTable) {
      if (customerName.trim().length < 2) found.push("Escribe tu nombre completo.");
      if (customerPhone.replace(/\D/g, "").length < 7) {
        found.push("Escribe un teléfono válido (mínimo 7 dígitos).");
      }
    } else {
      if (customerName.trim() && customerName.trim().length < 2) {
        found.push("Escribe un nombre válido o déjalo vacío.");
      }
      if (customerPhone.trim() && customerPhone.replace(/\D/g, "").length < 7) {
        found.push("Escribe un teléfono válido o déjalo vacío.");
      }
    }
    if (type === "delivery") {
      const addr = deliveryAddress.trim();
      if (addr.length < 5) found.push("Escribe la dirección de entrega (mínimo 5 caracteres).");
      if (addr.length > 160) found.push("La dirección no puede superar 160 caracteres.");
    }
    if (type === "table") {
      const table = Number(tableNumber);
      if (!Number.isInteger(table) || table < 1 || table > 100) {
        found.push("El número de mesa debe estar entre 1 y 100.");
      }
    }
    return found;
  }

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const clientErrors = validate();
    if (clientErrors.length > 0) {
      setErrors(clientErrors);
      return;
    }
    setErrors([]);
    setInsufficientItems([]);
    setSubmitting(true);
    const payloadBody = {
      customerName,
      customerPhone,
      deliveryAddress: type === "delivery" ? deliveryAddress : "",
      type,
      tableNumber: type === "table" ? Number(tableNumber) : null,
      paymentMethod,
      notes,
      items: lines.map((line) => ({
        menuItemId: line.menuItemId,
        quantity: line.quantity,
      })),
    };
    try {
      const checkResponse = await fetch("/api/orders/validate", {
        method: "POST",
        headers: { "Content-Type": "application/json", ...tenantFetchHeaders() },
        body: JSON.stringify(payloadBody),
      });
      const checkPayload = (await checkResponse.json()) as {
        ok?: boolean;
        errors?: string[];
        insufficientItems?: Array<{
          menuItemId: string;
          name: string;
          requested: number;
          available: number;
        }>;
      };
      if (!checkResponse.ok || !checkPayload.ok) {
        const insufficient = checkPayload.insufficientItems ?? [];
        if (insufficient.length > 0) {
          applyInsufficientItems(insufficient);
        } else {
          setErrors(checkPayload.errors ?? ["No pudimos validar el pedido."]);
        }
        return;
      }

      const response = await fetch("/api/orders", {
        method: "POST",
        headers: { "Content-Type": "application/json", ...tenantFetchHeaders() },
        body: JSON.stringify(payloadBody),
      });
      const payload = (await response.json()) as {
        order?: Order;
        errors?: string[];
        insufficientItems?: Array<{
          menuItemId: string;
          name: string;
          requested: number;
          available: number;
        }>;
      };
      if (!response.ok || !payload.order) {
        const insufficient = payload.insufficientItems ?? [];
        if (insufficient.length > 0) {
          applyInsufficientItems(insufficient);
        } else {
          setErrors(payload.errors ?? ["No pudimos crear el pedido. Intenta de nuevo."]);
        }
        return;
      }
      const order = payload.order;
      try {
        window.sessionStorage.setItem(orderKey(order.id), JSON.stringify(order));
        const raw = window.localStorage.getItem(ordersKey());
        const stored = raw ? (JSON.parse(raw) as Order[]) : [];
        window.localStorage.setItem(
          ordersKey(),
          JSON.stringify([order, ...stored].slice(0, 50)),
        );
        window.localStorage.setItem(lastOrderKey(), order.id);
        const phoneDigits = customerPhone.replace(/\D/g, "");
        if (phoneDigits.length >= 7 || customerName.trim().length >= 2) {
          const addr = deliveryAddress.trim();
          const nextAddresses = addr
            ? [addr, ...savedAddresses.filter((a) => a.toLowerCase() !== addr.toLowerCase())].slice(0, 10)
            : savedAddresses;
          window.localStorage.setItem(
            customerProfileKey(),
            JSON.stringify({
              customerName: customerName.trim(),
              customerPhone: customerPhone.trim(),
              deliveryAddress: addr,
              addresses: nextAddresses,
              updatedAt: new Date().toISOString(),
            }),
          );
          setSavedAddresses(nextAddresses);
        }
      } catch {
        /* el pedido ya fue creado en el servidor */
      }
      setStockInsufficient([]);
      setStockErrors([]);
      setStockAlert(null);
      clear();
      router.push(`/order/${order.id}`);
    } catch {
      setErrors(["Error de red. Revisa tu conexión e intenta de nuevo."]);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="grid gap-8 lg:grid-cols-[1.5fr_1fr]">
      <div className="space-y-6">
        <section className="surface-card p-5">
          <h2 className="inline-flex items-center gap-2 font-display text-xl font-bold text-ink">
            <UserRound size={18} className="text-brand" aria-hidden /> Tus datos
          </h2>
          {profileLoaded && (
            <p className="mt-2 rounded-xl bg-brand-50 px-3 py-2 text-xs font-medium text-brand-800">
              <CircleCheck size={14} className="mr-1 inline" aria-hidden />
              Reconocimos tu perfil por teléfono. Puedes editar tus datos antes de confirmar.
            </p>
          )}
          <div className="mt-4 grid gap-4 sm:grid-cols-2">
            <label className="block text-sm">
              <span className="mb-1.5 block font-medium text-ink-soft">
                Nombre completo {type === "table" ? "(opcional)" : "*"}
              </span>
              <input
                required={type !== "table"}
                value={customerName}
                onChange={(event) => setCustomerName(event.target.value)}
                className="field"
                placeholder="Ana Pérez"
                autoComplete="name"
              />
            </label>
            <label className="block text-sm">
              <span className="mb-1.5 block font-medium text-ink-soft">
                Teléfono / WhatsApp {type === "table" ? "(opcional)" : "*"}
              </span>
              <input
                required={type !== "table"}
                value={customerPhone}
                onChange={(event) => setCustomerPhone(event.target.value)}
                className="field"
                placeholder="300 123 4567"
                inputMode="tel"
                autoComplete="tel"
              />
            </label>
          </div>
        </section>

        <section className="surface-card p-5">
          <h2 className="inline-flex items-center gap-2 font-display text-xl font-bold text-ink">
            <MapPin size={18} className="text-brand" aria-hidden />
            {config.showOrderTypeOptions
              ? "¿Cómo quieres recibirlo?"
              : visibleTypeOptions[0]?.label ?? "Tipo de pedido"}
          </h2>
          <div className="mt-4 grid gap-3 sm:grid-cols-3">
            {visibleTypeOptions.map((option) => {
              const Icon = option.icon;
              return (
                <button
                  key={option.value}
                  type="button"
                  onClick={() => setType(option.value)}
                  className={`rounded-2xl border p-4 text-left transition ${
                    type === option.value
                      ? "border-brand bg-brand-50 ring-2 ring-brand-100"
                      : "border-line hover:border-brand-300"
                  }`}
                >
                  <span className="grid h-10 w-10 place-items-center rounded-xl bg-brand-100 text-brand-strong">
                    <Icon size={20} aria-hidden />
                  </span>
                  <span className="mt-2 block text-sm font-semibold text-ink">
                    {option.label}
                  </span>
                </button>
              );
            })}
          </div>
          {type === "table" ? (
            <label className="mt-4 block max-w-xs text-sm">
              <span className="mb-1.5 block font-medium text-ink-soft">
                Número de mesa
              </span>
              <input
                type="number"
                min={1}
                max={100}
                value={tableNumber}
                onChange={(event) => setTableNumber(event.target.value)}
                className="field"
              />
            </label>
          ) : null}
          {type === "delivery" ? (
            <label className="mt-4 block text-sm">
              <span className="mb-1.5 block font-medium text-ink-soft">
                Dirección de entrega *
              </span>
              <input
                required
                value={deliveryAddress}
                onChange={(event) => setDeliveryAddress(event.target.value)}
                className="field"
                placeholder="Calle 10 # 43-12, apto 301, Medellín"
                autoComplete="street-address"
                maxLength={160}
              />
              {savedAddresses.length > 0 ? (
                <div className="mt-2">
                  <p className="mb-1 text-xs font-medium text-ink-muted">Direcciones usadas:</p>
                  <div className="flex flex-wrap gap-2">
                    {savedAddresses.map((addr) => (
                      <button
                        key={addr}
                        type="button"
                        onClick={() => setDeliveryAddress(addr)}
                        className={`rounded-full border px-3 py-1 text-xs ${
                          deliveryAddress.trim().toLowerCase() === addr.toLowerCase()
                            ? "border-brand-500 bg-brand-50 text-brand-700"
                            : "border-line text-ink-soft hover:border-brand-300"
                        }`}
                      >
                        {addr}
                      </button>
                    ))}
                  </div>
                </div>
              ) : null}
            </label>
          ) : null}
        </section>

        <section className="surface-card p-5">
          <h2 className="inline-flex items-center gap-2 font-display text-xl font-bold text-ink">
            <Wallet size={18} className="text-brand" aria-hidden /> Pago
          </h2>
          <div className="mt-4 flex flex-wrap gap-2">
            {visiblePaymentOptions.map((option) => (
              <button
                key={option.value}
                type="button"
                onClick={() => setPaymentMethod(option.value)}
                className={`rounded-full border px-4 py-2 text-sm font-medium transition ${
                  paymentMethod === option.value
                    ? "border-brand bg-brand text-white"
                    : "border-line text-ink-soft hover:border-brand-400"
                }`}
              >
                {config.paymentMethodLabels[option.value] || option.label}
              </button>
            ))}
          </div>
          <label className="mt-4 block text-sm">
            <span className="mb-1.5 block font-medium text-ink-soft">
              Notas para la cocina (opcional)
            </span>
            <textarea
              value={notes}
              onChange={(event) => setNotes(event.target.value)}
              rows={3}
              maxLength={300}
              className="field"
              placeholder="Sin cebolla, salsa aparte..."
            />
          </label>
        </section>

        {stockErrors.length > 0 || stockInsufficient.length > 0 ? (
          <div
            role="alert"
            className="rounded-2xl border border-brand-200 bg-brand-50 p-4 text-sm text-brand-900"
          >
            <p className="font-semibold">Revisa la disponibilidad antes de confirmar</p>
            {stockErrors.length > 0 ? (
              <ul className="mt-2 list-inside list-disc">
                {stockErrors.map((error) => (
                  <li key={error}>{error}</li>
                ))}
              </ul>
            ) : null}
            <ul className="mt-2 space-y-1">
              {stockInsufficient.map((item) => (
                <li key={item.menuItemId}>
                  <span className="font-semibold">{item.name}</span>: pediste {item.requested},{" "}
                  {item.available > 0
                    ? `solo puedes pedir ${item.available}.`
                    : "no queda disponibilidad."}
                </li>
              ))}
            </ul>
            <button
              type="button"
              onClick={() => applyInsufficientItems(stockInsufficient)}
              className="btn-primary mt-3 !px-4 !py-2 text-xs"
            >
              Ajustar carrito automáticamente
            </button>
          </div>
        ) : null}

        {errors.length > 0 ? (
          <div
            role="alert"
            className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700"
          >
            <p className="font-semibold">Revisa estos puntos:</p>
            <ul className="mt-1 list-inside list-disc">
              {errors.map((error) => (
                <li key={error}>{error}</li>
              ))}
            </ul>
            {insufficientItems.length > 0 ? (
              <ul className="mt-3 space-y-1 rounded-lg bg-surface-raised/80 p-3 text-rose-800">
                {insufficientItems.map((item) => (
                  <li key={item.menuItemId}>
                    <span className="font-semibold">{item.name}</span>: pediste {item.requested},{" "}
                    {item.available > 0
                      ? `solo hay ${item.available} disponible(s); ajustamos la cantidad.`
                      : "no hay ingredientes disponibles; lo quitamos del carrito."}
                  </li>
                ))}
              </ul>
            ) : null}
          </div>
        ) : null}
      </div>

      <aside className="surface-card h-fit p-5 lg:sticky lg:top-24">
        <h2 className="inline-flex items-center gap-2 font-display text-xl font-bold text-ink">
          <ReceiptText size={18} className="text-brand" aria-hidden /> Tu pedido
        </h2>
        <ul className="mt-4 space-y-2 text-sm">
          {lines.map((line) => (
            <li key={line.menuItemId} className="flex justify-between gap-2">
              <span className="text-ink-soft">
                {line.quantity} × {line.name}
              </span>
              <span className="whitespace-nowrap font-medium text-ink">
                {money(line.price * line.quantity)}
              </span>
            </li>
          ))}
        </ul>
        <div className="mt-4 flex justify-between border-t border-line pt-3 text-base">
          <span className="font-bold text-ink">Total</span>
          <span className="font-bold text-brand-700">{money(totals.total)}</span>
        </div>
        <button
          type="submit"
          disabled={
            submitting ||
            stockChecking ||
            stockInsufficient.length > 0 ||
            stockErrors.length > 0
          }
          className="btn-primary mt-5 w-full disabled:cursor-not-allowed disabled:opacity-60"
        >
          {stockInsufficient.length > 0 || stockErrors.length > 0
            ? "Ajusta tu carrito"
            : stockChecking
              ? "Verificando ingredientes..."
              : submitting
                ? "Enviando pedido..."
                : "Confirmar pedido"}
        </button>
        <p className="mt-3 text-center text-xs text-ink-muted">
          Al confirmar aceptas que te contactemos por WhatsApp.
        </p>
      </aside>

      {stockAlert ? (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-ink/60 p-4"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) setStockAlert(null);
          }}
        >
          <div
            role="alertdialog"
            aria-modal="true"
            aria-labelledby="stock-alert-title"
            aria-describedby="stock-alert-desc"
            className="w-full max-w-md rounded-3xl bg-surface-raised p-6 shadow-2xl"
          >
            <p className="text-3xl" aria-hidden="true">⚠️</p>
            <h2
              id="stock-alert-title"
              className="mt-3 font-display text-xl font-bold text-ink"
            >
              No hay suficientes insumos
            </h2>
            <p id="stock-alert-desc" className="mt-2 text-sm text-ink-soft">
              Ajustamos tu carrito a la cantidad que sí se puede preparar. Revisa
              el resumen antes de confirmar.
            </p>
            <ul className="mt-4 space-y-1 rounded-2xl bg-brand-50 p-3 text-sm text-brand-900">
              {stockAlert.map((item) => (
                <li key={item.menuItemId}>
                  <span className="font-semibold">{item.name}</span>: pediste{" "}
                  {item.requested},{" "}
                  {item.available > 0
                    ? `solo se pueden preparar ${item.available}.`
                    : "no queda disponibilidad; lo quitamos del carrito."}
                </li>
              ))}
            </ul>
            <button
              ref={alertButtonRef}
              type="button"
              onClick={() => setStockAlert(null)}
              className="btn-primary mt-5 w-full"
            >
              Entendido
            </button>
          </div>
        </div>
      ) : null}
    </form>
  );
}
