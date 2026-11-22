"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useCart } from "./CartProvider";
import { siteConfig } from "@/lib/site";

const links = [
  { href: "/", label: "Inicio" },
  { href: "/menu", label: "Menú" },
  { href: "/cart", label: "Carrito" },
];

export function Header() {
  const pathname = usePathname();
  const { count, ready } = useCart();

  return (
    <header className="sticky top-0 z-40 border-b border-stone-200/70 bg-stone-50/90 backdrop-blur">
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-4 sm:px-6">
        <Link href="/" className="flex items-center gap-2.5">
          <span className="grid h-9 w-9 place-items-center rounded-xl bg-brand-600 text-lg shadow-sm">
            🍽️
          </span>
          <span className="font-display text-lg font-bold tracking-tight text-ink-900">
            {siteConfig.name}
          </span>
        </Link>

        <nav className="flex items-center gap-1 text-sm font-medium text-ink-700">
          {links.map((link) => {
            const active =
              link.href === "/"
                ? pathname === "/"
                : pathname.startsWith(link.href);
            return (
              <Link
                key={link.href}
                href={link.href}
                className={`rounded-full px-3 py-2 transition hover:bg-brand-100 hover:text-brand-800 ${
                  active ? "bg-brand-100 text-brand-800" : ""
                }`}
              >
                {link.label}
                {link.href === "/cart" && ready && count > 0 ? (
                  <span className="ml-1.5 inline-grid h-5 min-w-5 place-items-center rounded-full bg-brand-600 px-1 text-[11px] font-bold text-white">
                    {count}
                  </span>
                ) : null}
              </Link>
            );
          })}
        </nav>

        <a
          href={`https://wa.me/${siteConfig.whatsapp}`}
          target="_blank"
          rel="noopener noreferrer"
          className="hidden rounded-full bg-emerald-600 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-emerald-700 sm:inline-flex"
        >
          WhatsApp
        </a>
      </div>
    </header>
  );
}
