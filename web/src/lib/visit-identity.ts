const DAY_KEY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

/** Día natural en America/Bogota, independiente de la zona horaria del navegador. */
export function dayKeyFor(date: Date): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Bogota",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const get = (type: string) =>
    parts.find((part) => part.type === type)?.value ?? "";
  return `${get("year")}-${get("month")}-${get("day")}`;
}

export function normalizeDayKey(value: unknown, fallback: Date = new Date()): string {
  const key = String(value ?? "").trim();
  return DAY_KEY_PATTERN.test(key) ? key : dayKeyFor(fallback);
}

/**
 * ID determinista para una identidad de visitante en un día concreto.
 * Firestore reemplaza el documento si el mismo cliente vuelve a enviar la visita.
 */
export function visitDocumentId(visitorId: string, dayKey: string): string {
  const identity = visitorId.trim().slice(0, 120);
  const key = `${identity}|${normalizeDayKey(dayKey)}`;
  let hash = 0x811c9dc5;
  for (let index = 0; index < key.length; index += 1) {
    hash ^= key.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return `vis_${normalizeDayKey(dayKey)}_${(hash >>> 0).toString(16).padStart(8, "0")}`;
}
