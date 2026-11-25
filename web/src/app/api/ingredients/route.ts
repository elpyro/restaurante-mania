import { NextResponse } from "next/server";
import { isFirestoreConfigured, listDocuments } from "@/lib/firebase/rest";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Inventario compartido: la app offline-first lo sincroniza con este feed. */
export async function GET() {
  if (!isFirestoreConfigured()) {
    return NextResponse.json({ ingredients: [], configured: false });
  }
  try {
    const ingredients = await listDocuments(
      "ingredients",
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
      { ingredients, configured: true },
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
