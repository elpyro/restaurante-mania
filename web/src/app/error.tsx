"use client";

import { useEffect } from "react";
import { RotateCcw, TriangleAlert } from "lucide-react";

export default function Error({
  error,
  retry,
}: {
  error: unknown;
  retry: () => void;
}) {
  useEffect(() => {
    console.error("[web] Error de renderizado:", error);
  }, [error]);

  return (
    <div className="mx-auto flex max-w-xl flex-col items-center px-4 py-20 text-center sm:px-6">
      <div className="surface-card w-full animate-fade-up p-8 sm:p-10">
        <span className="mx-auto grid h-14 w-14 place-items-center rounded-2xl bg-brand-50 text-brand-strong">
          <TriangleAlert size={26} aria-hidden />
        </span>
        <h1 className="section-title mt-6 text-2xl">Algo salió mal</h1>
        <p className="mt-3 text-sm leading-relaxed text-ink-muted">
          No pudimos cargar esta sección. Revisa tu conexión e inténtalo de
          nuevo; tu carrito se ha conservado.
        </p>
        <button type="button" onClick={retry} className="btn-primary mt-7">
          <RotateCcw size={16} aria-hidden /> Reintentar
        </button>
      </div>
    </div>
  );
}
