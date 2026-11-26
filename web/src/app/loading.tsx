export default function Loading() {
  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6 sm:py-14" role="status" aria-live="polite">
      <span className="sr-only">Cargando contenido…</span>
      <div className="skeleton h-4 w-32" />
      <div className="skeleton mt-5 h-12 w-2/3 max-w-xl" />
      <div className="skeleton mt-4 h-4 w-full max-w-2xl" />
      <div className="skeleton mt-2 h-4 w-5/6 max-w-xl" />

      <div className="mt-10 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
        {Array.from({ length: 6 }).map((_, index) => (
          <div key={index} className="surface-card overflow-hidden p-0">
            <div className="skeleton h-44 rounded-none" />
            <div className="space-y-3 p-5">
              <div className="skeleton h-5 w-3/4" />
              <div className="skeleton h-4 w-full" />
              <div className="skeleton h-4 w-1/2" />
              <div className="skeleton h-10 w-full rounded-full" />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
