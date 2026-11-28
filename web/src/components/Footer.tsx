import Image from "next/image";
import Link from "next/link";
import {
  ArrowRight,
  Camera,
  Clock,
  MapPin,
  MapPinned,
  MessageCircle,
  Music2,
  Phone,
  Share2,
  UtensilsCrossed,
  type LucideIcon,
} from "lucide-react";
import {
  formatOpeningHours,
  SOCIAL_NETWORKS,
  type RestaurantConfig,
  type SocialNetwork,
} from "@/lib/restaurant-config";
import { whatsappUrl } from "@/lib/site";
import { withTenant } from "@/lib/tenants";

// Lucide no publica iconos de marca; usamos glifos genéricos con etiqueta textual.
const socialMeta: Record<SocialNetwork, { label: string; icon: LucideIcon }> = {
  instagram: { label: "Instagram", icon: Camera },
  tiktok: { label: "TikTok", icon: Music2 },
  facebook: { label: "Facebook", icon: Share2 },
};

export function Footer({
  config,
  tenantId,
}: {
  config: RestaurantConfig;
  tenantId: string;
}) {
  const logoUrl = config.appearance.logoUrl;
  const gpsUrl = config.appearance.gpsUrl;
  const socialLinks = SOCIAL_NETWORKS.map((network) => {
    const href = config.appearance.socialLinks?.[network];
    if (!href) return null;
    return { network, href, ...socialMeta[network] };
  }).filter(
    (
      link,
    ): link is {
      network: SocialNetwork;
      href: string;
      label: string;
      icon: LucideIcon;
    } => link !== null,
  );

  return (
    <footer className="mt-24 bg-footer text-footer-ink">
      <div className="mx-auto max-w-6xl px-4 py-14 sm:px-6">
        <div className="grid gap-10 md:grid-cols-[1.4fr_1fr_1fr]">
          <div>
            <div className="flex items-center gap-3">
              {logoUrl ? (
                <Image
                  src={logoUrl}
                  alt={`Logo de ${config.name}`}
                  width={56}
                  height={56}
                  unoptimized
                  className="h-14 w-14 rounded-2xl bg-white/95 p-1.5 object-contain"
                />
              ) : (
                <span className="grid h-10 w-10 place-items-center rounded-2xl bg-brand text-white">
                  <UtensilsCrossed size={20} aria-hidden />
                </span>
              )}
              <div>
                {!logoUrl && (
                  <p className="font-display text-xl font-bold">{config.name}</p>
                )}
                <p className="text-xs text-footer-ink/60">{config.city}</p>
              </div>
            </div>
            <p className="mt-4 max-w-sm text-sm leading-relaxed text-footer-ink/70">
              {config.slogan}
            </p>
            <a
              href={whatsappUrl(undefined, config.whatsapp, config.name)}
              target="_blank"
              rel="noopener noreferrer"
              className="mt-5 inline-flex items-center gap-2 rounded-full bg-accent px-4 py-2 text-sm font-semibold text-white transition hover:bg-accent-strong"
            >
              <MessageCircle size={16} aria-hidden />
              Escríbenos por WhatsApp
            </a>
            {socialLinks.length > 0 && (
              <div className="mt-4 flex flex-wrap gap-2">
                {socialLinks.map(({ network, href, label, icon: Icon }) => (
                  <a
                    key={network}
                    href={href}
                    target="_blank"
                    rel="noopener noreferrer"
                    aria-label={label}
                    className="inline-flex items-center gap-1.5 rounded-full border border-white/15 px-3 py-1.5 text-xs text-footer-ink/80 transition hover:border-brand-300 hover:text-white"
                  >
                    <Icon size={15} aria-hidden />
                    {label}
                  </a>
                ))}
              </div>
            )}
          </div>

          <div className="text-sm">
            <p className="font-semibold uppercase tracking-widest text-brand-300">
              Visítanos
            </p>
            <ul className="mt-4 space-y-3 text-footer-ink/75">
              <li className="flex items-start gap-2">
                <MapPin size={16} className="mt-0.5 shrink-0 text-brand-300" aria-hidden />
                <span>{config.address}</span>
              </li>
              {gpsUrl && (
                <li>
                  <a
                    href={gpsUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-2 transition hover:text-brand-300"
                  >
                    <MapPinned size={16} className="shrink-0 text-brand-300" aria-hidden />
                    <span>Ver en el mapa</span>
                  </a>
                </li>
              )}
              <li className="flex items-center gap-2">
                <Clock size={16} className="shrink-0 text-brand-300" aria-hidden />
                <span>{formatOpeningHours(config)}</span>
              </li>
              <li className="flex items-center gap-2">
                <Phone size={16} className="shrink-0 text-brand-300" aria-hidden />
                <span>{config.phone}</span>
              </li>
            </ul>
          </div>

          <div className="text-sm">
            <p className="font-semibold uppercase tracking-widest text-brand-300">
              Explora
            </p>
            <ul className="mt-4 space-y-2 text-footer-ink/75">
              {[
                { href: "/menu", label: "Menú completo" },
                { href: "/cart", label: "Tu carrito" },
                { href: "/cuenta", label: "Mi cuenta" },
                { href: "/llms.txt", label: "Datos para IA" },
              ].map((link) => (
                <li key={link.href}>
                  <Link
                    href={
                      link.href === "/llms.txt"
                        ? link.href
                        : withTenant(link.href, tenantId)
                    }
                    className="inline-flex items-center gap-1.5 transition hover:text-brand-300"
                  >
                    <ArrowRight size={14} aria-hidden />
                    {link.label}
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        </div>
      </div>
      <div className="border-t border-white/10 py-5 text-center text-xs text-footer-ink/50">
        <a
          href={whatsappUrl(
            "Hola Software Mania, quiero adquirir el software.",
            "573125866072",
          )}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex flex-wrap items-center justify-center gap-1 transition hover:text-white"
        >
          © {new Date().getFullYear()} {config.name}. Otro software de Software
          Mania. Adquierelo:{" "}
          <span className="font-semibold text-white">+573125866072</span>
        </a>
      </div>
    </footer>
  );
}
