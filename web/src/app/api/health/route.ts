import { NextResponse } from "next/server";
import { isFirestoreConfigured } from "@/lib/firebase/rest";

export const dynamic = "force-dynamic";

export async function GET() {
  return NextResponse.json({
    status: "ok",
    service: "restaurante-mania-web",
    mode: isFirestoreConfigured() ? "firestore" : "demo",
    timestamp: new Date().toISOString(),
  });
}
