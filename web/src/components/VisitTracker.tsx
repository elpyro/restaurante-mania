"use client";

import { usePathname } from "next/navigation";
import { useEffect } from "react";
import { dayKeyFor, visitDocumentId } from "@/lib/visit-identity";

const PROFILE_KEY = "rm_customer_profile_v1";
const VISITOR_KEY = "rm_web_visitor_id_v1";
const STATE_KEY = "rm_web_visit_state_v1";

type Profile = {
  customerName?: string;
  customerPhone?: string;
};

type VisitState = {
  dayKey: string;
  identityKey: string;
  trackedAt?: string;
};

let fallbackVisitorId = "";

function readJson<T>(key: string): T | null {
  try {
    const raw = window.localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : null;
  } catch {
    return null;
  }
}

function writeJson(key: string, value: unknown): void {
  try {
    window.localStorage.setItem(key, JSON.stringify(value));
  } catch {
    /* almacenamiento bloqueado: el conteo sigue siendo best-effort */
  }
}

function loadProfile(): Profile | null {
  try {
    const raw = window.localStorage.getItem(PROFILE_KEY);
    if (!raw) return null;
    const profile = JSON.parse(raw) as Profile;
    const phone = (profile.customerPhone ?? "").replace(/\D/g, "");
    const name = (profile.customerName ?? "").trim();
    if (phone.length < 7 && name.length < 2) return null;
    return {
      customerName: name,
      customerPhone: (profile.customerPhone ?? "").trim(),
    };
  } catch {
    return null;
  }
}

function getVisitorId(): string {
  try {
    const stored = window.localStorage.getItem(VISITOR_KEY) ?? "";
    if (/^visitor_[a-zA-Z0-9_-]{8,}$/.test(stored)) return stored;
    const random = globalThis.crypto?.randomUUID?.();
    const created = `visitor_${random ?? `${Date.now()}_${Math.random().toString(36).slice(2, 10)}`}`;
    window.localStorage.setItem(VISITOR_KEY, created);
    return created;
  } catch {
    if (!fallbackVisitorId) {
      fallbackVisitorId = `visitor_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    }
    return fallbackVisitorId;
  }
}

function identityKeyFor(profile: Profile | null, dayKey: string): string {
  const state = readJson<VisitState>(STATE_KEY);
  if (
    state?.dayKey === dayKey &&
    typeof state.identityKey === "string" &&
    state.identityKey.length >= 8
  ) {
    return state.identityKey;
  }
  const digits = (profile?.customerPhone ?? "").replace(/\D/g, "");
  const identityKey = digits.length >= 7 ? `phone:${digits}` : getVisitorId();
  writeJson(STATE_KEY, { dayKey, identityKey } satisfies VisitState);
  return identityKey;
}

function markTracked(dayKey: string, identityKey: string): boolean {
  const state = readJson<VisitState>(STATE_KEY);
  if (
    state?.dayKey === dayKey &&
    state.identityKey === identityKey &&
    typeof state.trackedAt === "string"
  ) {
    return false;
  }
  writeJson(STATE_KEY, {
    ...state,
    dayKey,
    identityKey,
    trackedAt: new Date().toISOString(),
  } satisfies VisitState);
  return true;
}

function unmarkTracked(dayKey: string, identityKey: string): void {
  const state = readJson<VisitState>(STATE_KEY);
  if (state?.dayKey !== dayKey || state.identityKey !== identityKey) return;
  writeJson(STATE_KEY, { dayKey, identityKey } satisfies VisitState);
}

export function VisitTracker() {
  const pathname = usePathname();

  useEffect(() => {
    const dayKey = dayKeyFor(new Date());
    const profile = loadProfile();
    const identityKey = identityKeyFor(profile, dayKey);
    if (!markTracked(dayKey, identityKey)) return;

    const referenceUrl = window.location.href;
    const phone = (profile?.customerPhone ?? "").replace(/\D/g, "");
    const body = JSON.stringify({
      id: visitDocumentId(identityKey, dayKey),
      visitorId: identityKey,
      dayKey,
      occurredAt: new Date().toISOString(),
      registered: !!profile,
      customerName: profile?.customerName ?? "",
      customerPhone: profile?.customerPhone ?? "",
      normalizedPhone: phone,
      referenceLabel: pathname,
      referenceUrl,
      referrer: document.referrer,
    });

    void fetch("/api/visits", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
      keepalive: true,
    })
      .then((response) => {
        if (!response.ok) unmarkTracked(dayKey, identityKey);
      })
      .catch(() => {
        unmarkTracked(dayKey, identityKey);
      });
  }, [pathname]);

  return null;
}
