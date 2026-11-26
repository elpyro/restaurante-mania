"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import {
  House,
  Menu as MenuIcon,
  MessageCircle,
  ShoppingBag,
  UserRound,
  UtensilsCrossed,
  X,
} from "lucide-react";
import type { RestaurantConfig } from "@/lib/restaurant-config";
import { whatsappUrl } from "@/lib/site";
import { useCart } from "./CartProvider";
import { getClientTenantId, tenantStorageKey } from "@/lib/client-tenant";
import { DEFAULT_TENANT_ID, withTenant } from "@/lib/tenants";

const links = [
  { href: "/", label: "Inicio", icon: House },
  { href: "/menu", label: "Menú", icon: UtensilsCrossed },
  { href: "/cart", label: "Carrito", icon: ShoppingBag },
  { href: "/cuenta", label: "Mi cuenta", icon: UserRound },
];

export function Header({ config }: { config: RestaurantConfig }) {
  const pathname = usePathname();
  const { count, ready } = useCart();
  const [hasProfile, setHasProfile] = useState(false);
  const [open, setOpen] = useState(false);
  const [tenantId, setTenantId] = useState(DEFAULT_TENANT_ID);
  const logoUrl = config.appearance.logoUrl;
  const waUrl = whatsappUrl(undefined, config.whatsapp, config.name);

  useEffect(() => {
    setTenantId(getClientTenantId());
  }, []);

  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(
        tenantStorageKey(getClientTenantId(), "rm_customer_profile_v1"),
      );
      if (!raw) return;
      const p = JSON.parse(raw) as { customerPhone?: string; customerName?: string };
      const phone = (p.customerPhone ?? "").replace(/\D/g, "");
      if (phone.length >= 7 || (p.customerName ?? "").trim().length >= 2) setHasProfile(true);
    } catch {
      /* ignore */
    }
  }, [pathname]);

  useEffect(() => setOpen(false), [pathname]);

  const isActive = (href: string) =>
    href === "/" ? pathname === "/" : pathname.startsWith(href);

  return (
    <>
      <header className="sticky top-0 z-40 border-b border-line/70 bg-surface/85 backdrop-blur-xl">
        <div className="mx-auto flex h-[4.5rem] max-w-6xl items-center justify-between gap-4 px-4 sm:px-6">
          <Link href={withTenant("/", tenantId)} className="group flex min-w-0 items-center gap-3">
            {logoUrl ? (
              <Image
                src={logoUrl}
                alt={`Logo de ${config.name}`}
                width={44}
                height={44}
                unoptimized
                className="h-10 w-10 shrink-0 rounded-2xl border border-line bg-surface-raised object-contain p-1 shadow-glow transition duration-300 group-hover:-rotate-6 group-hover:scale-105"
              />
            ) : (
              <span className="grid h-10 w-10 shrink-0 place-items-center rounded-2xl bg-brand text-white shadow-glow transition duration-300 group-hover:-rotate-6 group-hover:scale-105">
                <UtensilsCrossed size={20} aria-hidden />
              </span>
            )}
            <span className="truncate font-display text-lg font-bold leading-tight tracking-tight text-ink">
              {config.name}
              <span className="block text-[10px] font-semibold uppercase tracking-[0.18em] text-brand-strong">
                {config.city}
              </span>
            </span>
          </Link>

          <nav
            className="hidden items-center gap-1 rounded-full border border-line bg-surface-raised/80 p-1 text-sm font-semibold text-ink-soft md:flex"
            aria-label="Navegación principal"
          >
            {links.map((link) => {
              const active = isActive(link.href);
              const Icon = link.icon;
              return (
                <Link
                  key={link.href}
                  href={withTenant(link.href, tenantId)}
                  aria-current={active ? "page" : undefined}
                  className={`inline-flex items-center gap-2 rounded-full px-3.5 py-2 transition ${
                    active
                      ? "bg-brand text-white shadow-sm"
                      : "hover:bg-brand-50 hover:text-brand-strong"
                  }`}
                >
                  <Icon size={16} aria-hidden />
                  {link.label}
                  {link.href === "/cart" && ready && count > 0 ? (
                    <span className="grid h-5 min-w-5 place-items-center rounded-full bg-accent px-1 text-[11px] font-bold text-white">
                      {count}
                    </span>
                  ) : null}
                  {link.href === "/cuenta" && hasProfile ? (
                    <span
                      className="h-2 w-2 rounded-full bg-accent"
                      aria-label="Cliente registrado"
                    />
                  ) : null}
                </Link>
              );
            })}
          </nav>

          <div className="flex items-center gap-2">
            <a
              href={waUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="hidden items-center gap-2 rounded-full bg-accent px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:-translate-y-0.5 hover:bg-accent-strong sm:inline-flex"
            >
              <MessageCircle size={16} aria-hidden />
              WhatsApp
            </a>
            <Link
              href={withTenant("/cart", tenantId)}
              className="relative grid h-10 w-10 place-items-center rounded-full border border-line bg-surface-raised text-ink transition hover:border-brand-300 md:hidden"
              aria-label={`Carrito, ${ready ? count : 0} productos`}
            >
              <ShoppingBag size={18} aria-hidden />
              {ready && count > 0 ? (
                <span className="absolute -right-1 -top-1 grid h-5 min-w-5 place-items-center rounded-full bg-brand px-1 text-[11px] font-bold text-white">
                  {count}
                </span>
              ) : null}
            </Link>
            <button
              type="button"
              onClick={() => setOpen((value) => !value)}
              className="grid h-10 w-10 place-items-center rounded-full border border-line bg-surface-raised text-ink md:hidden"
              aria-expanded={open}
              aria-controls="mobile-nav"
              aria-label={open ? "Cerrar menú" : "Abrir menú"}
            >
              {open ? <X size={18} /> : <MenuIcon size={18} />}
            </button>
          </div>
        </div>

        {open ? (
          <nav
            id="mobile-nav"
            className="border-t border-line bg-surface-raised px-4 pb-4 pt-2 md:hidden"
            aria-label="Navegación móvil"
          >
            <div className="grid gap-1">
              {links.map((link) => {
                const active = isActive(link.href);
                const Icon = link.icon;
                return (
                  <Link
                    key={link.href}
                    href={withTenant(link.href, tenantId)}
                    className={`flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-semibold transition ${
                      active ? "bg-brand-50 text-brand-strong" : "text-ink-soft"
                    }`}
                  >
                    <Icon size={17} aria-hidden />
                    {link.label}
                    {link.href === "/cart" && ready && count > 0 ? (
                      <span className="ml-auto rounded-full bg-brand px-2 py-0.5 text-[11px] text-white">
                        {count}
                      </span>
                    ) : null}
                  </Link>
                );
              })}
              <a
                href={waUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="mt-2 flex items-center gap-3 rounded-xl bg-accent px-3 py-2.5 text-sm font-semibold text-white"
              >
                <MessageCircle size={17} aria-hidden />
                Pedir por WhatsApp
              </a>
            </div>
          </nav>
        ) : null}
      </header>

      <a
        href={waUrl}
        target="_blank"
        rel="noopener noreferrer"
        aria-label={`Pedir por WhatsApp a ${config.name}`}
        className="fixed bottom-24 right-4 z-40 grid h-14 w-14 place-items-center rounded-full bg-[#25D366] text-white shadow-glow transition hover:scale-105 md:bottom-6 md:right-6"
      >
        <span
          aria-hidden
          className="absolute inset-0 rounded-full bg-[#25D366]/40 motion-safe:animate-ping"
        />
        <MessageCircle size={24} aria-hidden className="relative" />
      </a>
    </>
  );
}
