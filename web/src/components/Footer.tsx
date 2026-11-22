import Link from "next/link";
import { siteConfig, whatsappUrl } from "@/lib/site";

export function Footer() {
  return (
    <footer className="mt-20 border-t border-stone-200 bg-white">
      <div className="mx-auto grid max-w-6xl gap-8 px-4 py-12 sm:px-6 md:grid-cols-3">
        <div>
          <p className="font-display text-lg font-bold text-ink-900">
            {siteConfig.name}
          </p>
          <p className="mt-2 max-w-xs text-sm leading-relaxed text-ink-500">
            Cocina colombiana hecha con calma, ingredientes frescos y el sabor
            de casa.
          </p>
        </div>
        <div className="text-sm text-ink-700">
          <p className="font-semibold text-ink-900">Visítanos</p>
          <p className="mt-2">{siteConfig.address}</p>
          <p>{siteConfig.city}, Colombia</p>
          <p className="mt-2">Todos los días · {siteConfig.hours}</p>
        </div>
        <div className="text-sm text-ink-700">
          <p className="font-semibold text-ink-900">Pedidos y reservas</p>
          <p className="mt-2">{siteConfig.phone}</p>
          <a
            className="mt-2 inline-block font-semibold text-emerald-700 hover:underline"
            href={whatsappUrl()}
            target="_blank"
            rel="noopener noreferrer"
          >
            Escríbenos por WhatsApp →
          </a>
          <div className="mt-4 flex gap-4">
            <Link className="hover:text-brand-700" href="/menu">
              Menú
            </Link>
            <Link className="hover:text-brand-700" href="/cart">
              Carrito
            </Link>
            <Link className="hover:text-brand-700" href="/llms.txt">
              llms.txt
            </Link>
          </div>
        </div>
      </div>
      <div className="border-t border-stone-200 py-5 text-center text-xs text-ink-500">
        © {new Date().getFullYear()} {siteConfig.name}. Hecho en Colombia 🇨🇴
      </div>
    </footer>
  );
}
