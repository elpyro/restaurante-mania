import { ImageResponse } from "next/og";
import type { NextRequest } from "next/server";
import {
  formatOpeningHours,
  getRestaurantConfig,
  themeForPreset,
} from "@/lib/restaurant-config";
import { resolveTenantFromRequest } from "@/lib/tenants";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** El renderizador de OG no descarga fuentes para emoji: los elimina. */
function ogText(value: string): string {
  return value
    .replace(/[\p{Extended_Pictographic}\uFE0F\u200D]/gu, "")
    .replace(/\s+/g, " ")
    .trim();
}

export async function GET(request: NextRequest) {
  const tenantId = resolveTenantFromRequest(request);
  const { config } = await getRestaurantConfig(tenantId);
  const theme = themeForPreset(config.appearance.preset);
  const params = request.nextUrl.searchParams;
  const title = ogText(params.get("title") ?? config.heroTitle).slice(0, 120);
  const description = ogText(params.get("description") ?? config.slogan).slice(0, 200);

  return new ImageResponse(
    (
      <div
        style={{
          display: "flex",
          width: "100%",
          height: "100%",
          flexDirection: "column",
          justifyContent: "space-between",
          background: theme["surface"],
          color: theme["ink-900"],
          padding: 72,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", fontSize: 30 }}>
          <div
            style={{
              display: "flex",
              width: 54,
              height: 54,
              alignItems: "center",
              justifyContent: "center",
              borderRadius: 16,
              background: theme["brand-600"],
              color: theme["surface-raised"],
              marginRight: 20,
              fontSize: 30,
            }}
          >
            {ogText(config.name).slice(0, 1).toUpperCase() || "R"}
          </div>
          <div style={{ display: "flex", fontWeight: 700 }}>{ogText(config.name)}</div>
        </div>

        <div style={{ display: "flex", flexDirection: "column" }}>
          <div
            style={{
              display: "flex",
              fontSize: 24,
              color: theme["brand-700"],
              fontWeight: 600,
              marginBottom: 24,
            }}
          >
            {ogText(config.heroBadge)}
          </div>
          <div
            style={{
              display: "flex",
              fontSize: title.length > 60 ? 64 : 78,
              fontWeight: 800,
              lineHeight: 1.08,
              letterSpacing: -2,
            }}
          >
            {title}
          </div>
          <div
            style={{
              display: "flex",
              fontSize: 30,
              color: theme["ink-muted"],
              marginTop: 28,
              maxWidth: 920,
              lineHeight: 1.35,
            }}
          >
            {description}
          </div>
        </div>

        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            borderTop: `2px solid ${theme.line}`,
            paddingTop: 26,
            fontSize: 24,
            color: theme["ink-muted"],
          }}
        >
          <div style={{ display: "flex" }}>
            {config.city} · {formatOpeningHours(config)}
          </div>
          <div style={{ display: "flex", color: theme.accent }}>PEDIDOS EN LÍNEA</div>
        </div>
      </div>
    ),
    {
      width: 1200,
      height: 630,
      headers: { "Cache-Control": "public, max-age=3600, s-maxage=3600" },
    },
  );
}
