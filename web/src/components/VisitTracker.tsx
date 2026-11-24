"use client";

import { usePathname } from "next/navigation";
import { useEffect } from "react";

const PROFILE_KEY = "rm_customer_profile_v1";
const DEDUPE_KEY = "rm_web_visit_tracker_v1";
const DEDUPE_MS = 30_000;

type Profile = {
  customerName?: string;
  customerPhone?: string;
};

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

function newId(): string {
  const random = globalThis.crypto?.randomUUID?.();
  return `vis_${Date.now()}_${random ?? Math.random().toString(36).slice(2, 10)}`;
}

function alreadyTracked(url: string): boolean {
  try {
    const raw = window.sessionStorage.getItem(DEDUPE_KEY);
    const history = (raw ? JSON.parse(raw) : {}) as Record<string, number>;
    const last = history[url] ?? 0;
    if (Date.now() - last < DEDUPE_MS) return true;
    history[url] = Date.now();
    window.sessionStorage.setItem(DEDUPE_KEY, JSON.stringify(history));
    return false;
  } catch {
    return false;
  }
}

export function VisitTracker() {
  const pathname = usePathname();

  useEffect(() => {
    const referenceUrl = window.location.href;
    if (alreadyTracked(referenceUrl)) return;

    const profile = loadProfile();
    const phone = (profile?.customerPhone ?? "").replace(/\D/g, "");
    const body = JSON.stringify({
      id: newId(),
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
    }).catch(() => {
      // El contador es best-effort: no debe afectar la navegación del cliente.
    });
  }, [pathname]);

  return null;
}
