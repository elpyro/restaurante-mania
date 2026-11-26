import {
  WEEKDAYS,
  type RestaurantConfig,
  type Weekday,
} from "./restaurant-config";

const WEEKDAY_NAMES: Record<Weekday, string> = {
  mon: "lunes",
  tue: "martes",
  wed: "miércoles",
  thu: "jueves",
  fri: "viernes",
  sat: "sábado",
  sun: "domingo",
};

export interface OpeningStatus {
  /** `true` cuando está dentro del horario y no hay cierre manual. */
  isOpen: boolean;
  label: "Abierto" | "Cerrado";
  detail: string;
  /** Texto listo para la ficha de la portada. */
  full: string;
}

interface ZonedTime {
  day: Weekday;
  minutes: number;
}

/** Extrae día y minuto del día en la zona horaria del restaurante. */
export function zonedTime(now: Date, timeZone: string): ZonedTime {
  let zone = timeZone;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: zone });
  } catch {
    zone = "UTC";
  }
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: zone,
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(now);
  const value = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((part) => part.type === type)?.value ?? "";
  const shortDay = value("weekday");
  const englishDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  const index = englishDays.indexOf(shortDay);
  const day = index >= 0 ? WEEKDAYS[index]! : "mon";
  const hour = Math.min(23, Number(value("hour")) || 0);
  const minute = Number(value("minute")) || 0;
  return { day, minutes: hour * 60 + minute };
}

function minutesOf(time: string): number {
  const [hour = "0", minute = "0"] = time.split(":");
  return Number(hour) * 60 + Number(minute);
}

function nextOpening(
  local: ZonedTime,
  config: Pick<
    RestaurantConfig,
    "openingDays" | "openTime" | "closeTime"
  >,
): { day: Weekday; time: string } {
  const opens = minutesOf(config.openTime);
  const closes = minutesOf(config.closeTime);
  const todayIndex = WEEKDAYS.indexOf(local.day);

  if (
    config.openingDays.includes(local.day) &&
    local.minutes < opens
  ) {
    return { day: local.day, time: config.openTime };
  }

  for (let offset = 1; offset <= WEEKDAYS.length; offset++) {
    const day = WEEKDAYS[(todayIndex + offset) % WEEKDAYS.length]!;
    if (config.openingDays.includes(day)) {
      return { day, time: config.openTime };
    }
  }

  // Sin días activos: se muestra el horario configurado como referencia.
  return { day: local.day, time: opens < closes ? config.openTime : config.closeTime };
}

/**
 * Estado de la portada. `pending` no bloquea pedidos: esta función solo calcula
 * lo que se muestra, usando siempre la zona horaria configurada desde la APK.
 */
export function openingStatus(
  config: Pick<
    RestaurantConfig,
    | "isOpen"
    | "timeZone"
    | "openingDays"
    | "openTime"
    | "closeTime"
  >,
  now: Date = new Date(),
): OpeningStatus {
  const local = zonedTime(now, config.timeZone);
  const opens = minutesOf(config.openTime);
  const closes = minutesOf(config.closeTime);
  const withinHours =
    config.openingDays.includes(local.day) &&
    local.minutes >= opens &&
    local.minutes < closes;
  const isOpen = config.isOpen !== false && withinHours;

  if (isOpen) {
    return {
      isOpen: true,
      label: "Abierto",
      detail: "recibiendo pedidos",
      full: "Abierto: recibiendo pedidos",
    };
  }

  // Un cierre manual es decisión del local, no un cambio de horario: se anuncia
  // siempre la misma hora de apertura, sin mencionar el día siguiente.
  const manualClose = config.isOpen === false;
  const next = manualClose
    ? { day: local.day, time: config.openTime }
    : nextOpening(local, config);
  const sameDay = manualClose || next.day === local.day;
  const detail = sameDay
    ? `abre a las ${next.time}`
    : `abre el ${WEEKDAY_NAMES[next.day]} a las ${next.time}`;
  return {
    isOpen: false,
    label: "Cerrado",
    detail,
    full: `Cerrado: ${detail}`,
  };
}
