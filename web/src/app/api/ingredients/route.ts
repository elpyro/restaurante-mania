import { NextResponse } from "next/server";
import { getDemoState } from "@/lib/demo-store";
import {
  isFirestoreConfigured,
  listDocuments,
  tenantPath,
} from "@/lib/firebase/rest";
import { resolveTenantFromRequest } from "@/lib/tenants";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function demoIngredients(tenantId: string) {
  return Object.entries(getDemoState(tenantId).stocks).map(([id, stock]) => ({
    id,
    name: id.replace(/-/g, " ").replace(/^./, (c) => c.toUpperCase()),
    unit: "und",
    stock,
    minStock: 0,
    updatedAt: null,
  }));
}

/** Inventario compartido: la app offline-first lo sincroniza con este feed. */
export async function GET(request: Request) {
  const tenantId = resolveTenantFromRequest(request);
  if (!isFirestoreConfigured()) {
    return NextResponse.json(
      { tenantId, ingredients: demoIngredients(tenantId), configured: false },
      { headers: { "Cache-Control": "no-store" } },
    );
  }
  try {
    const ingredients = await listDocuments(
      tenantPath(tenantId, "ingredients"),
      (doc) => {
        const data = doc.data as Record<string, unknown>;
        return {
          id: doc.id,
          name: typeof data.name === "string" ? data.name : doc.id,
          unit: typeof data.unit === "string" ? data.unit : "",
          stock:
            typeof data.stock === "number" && Number.isFinite(data.stock)
              ? data.stock
              : 0,
          minStock:
            typeof data.minStock === "number" && Number.isFinite(data.minStock)
              ? data.minStock
              : 0,
          updatedAt: typeof data.updatedAt === "string" ? data.updatedAt : null,
        };
      },
      0,
    );
    return NextResponse.json(
      { tenantId, ingredients, configured: true },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch (error) {
    console.error("[api/ingredients] GET", error);
    return NextResponse.json(
      { error: "No se pudo cargar el inventario" },
      { status: 500 },
    );
  }
}
