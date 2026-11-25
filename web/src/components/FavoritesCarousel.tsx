"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";

/** Carrusel de favoritos: avanza solo y se detiene al pasar el mouse o al enfocar una tarjeta. */
export function FavoritesCarousel({ children }: { children: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const [paused, setPaused] = useState(false);
  const [reducedMotion, setReducedMotion] = useState(false);

  useEffect(() => {
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    const sync = () => setReducedMotion(query.matches);
    sync();
    query.addEventListener?.("change", sync);
    return () => query.removeEventListener?.("change", sync);
  }, []);

  useEffect(() => {
    if (paused || reducedMotion) return;
    const timer = window.setInterval(() => {
      const node = ref.current;
      if (!node || node.scrollWidth <= node.clientWidth) return;
      const first = node.firstElementChild as HTMLElement | null;
      const step = first
        ? first.getBoundingClientRect().width + 16
        : node.clientWidth * 0.8;
      const atEnd =
        node.scrollLeft + node.clientWidth >= node.scrollWidth - 4;
      node.scrollTo({
        left: atEnd ? 0 : node.scrollLeft + step,
        behavior: "smooth",
      });
    }, 3200);
    return () => window.clearInterval(timer);
  }, [paused, reducedMotion]);

  return (
    <div
      ref={ref}
      className="mt-8 flex snap-x snap-mandatory gap-4 overflow-x-auto pb-5"
      aria-label="Carrusel de platos favoritos"
      onMouseEnter={() => setPaused(true)}
      onMouseLeave={() => setPaused(false)}
      onFocusCapture={() => setPaused(true)}
      onBlurCapture={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget as Node | null)) {
          setPaused(false);
        }
      }}
    >
      {children}
    </div>
  );
}
