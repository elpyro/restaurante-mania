import {
  cert,
  getApps,
  initializeApp,
  type App,
} from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getDocument, listDocuments, tenantPath } from "@/lib/firebase/rest";
import { DEFAULT_TENANT_ID } from "@/lib/tenants";

/**
 * Helper exclusivo de servidor: verifica ID tokens con Firebase Admin.
 * Nunca se importa desde componentes cliente.
 */
export class AdminUnavailableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AdminUnavailableError";
  }
}

export interface AdminIdentity {
  uid: string;
  email?: string;
  role: unknown;
  roleSource: "claim" | "firestore" | "none";
}

interface ServiceAccount {
  clientEmail: string;
  privateKey: string;
  projectId?: string;
}

interface StoredUserRole {
  uid?: string;
  email?: string;
  role?: unknown;
}

/**
 * El service account del proyecto tiene permisos de Firestore, no de Firebase
 * Auth Admin, así que no siempre es posible escribir custom claims. El rol se
 * acepta desde el claim `role` o, en su defecto, desde
 * `tenants/{tenantId}/users/{uid}` (o por email). Ambos mecanismos son datos
 * controlados por el servidor y aislados por restaurante.
 */
async function resolveStoredRole(
  uid: string,
  tenantId: string,
  email?: string,
): Promise<unknown> {
  try {
    const direct = await getDocument<StoredUserRole>(
      tenantPath(tenantId, "users"),
      uid,
      0,
    );
    if (direct?.role) return direct.role;
  } catch {
    // Se intenta por email si el documento por uid no existe o falla.
  }

  if (!email) return undefined;
  try {
    const matches = await listDocuments<StoredUserRole>(
      tenantPath(tenantId, "users"),
      ({ data }) => data as StoredUserRole,
      0,
    );
    const normalized = email.trim().toLowerCase();
    return matches.find(
      (user) =>
        user.role &&
        (user.email?.trim().toLowerCase() === normalized ||
          user.uid?.trim().toLowerCase() === normalized),
    )?.role;
  } catch {
    return undefined;
  }
}

let appPromise: Promise<App | null> | null = null;

function readServiceAccount(): ServiceAccount | null {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as {
      client_email?: string;
      private_key?: string;
      project_id?: string;
    };
    if (!parsed.client_email || !parsed.private_key) return null;
    return {
      clientEmail: parsed.client_email,
      privateKey: parsed.private_key,
      projectId: parsed.project_id,
    };
  } catch {
    return null;
  }
}

function resolveApp(): Promise<App | null> {
  if (!appPromise) {
    appPromise = (async () => {
      const current = getApps();
      if (current.length > 0) return current[0]!;

      const account = readServiceAccount();
      if (account) {
        return initializeApp({
          credential: cert({
            clientEmail: account.clientEmail,
            privateKey: account.privateKey,
            projectId: account.projectId,
          }),
          ...(account.projectId ? { projectId: account.projectId } : {}),
        });
      }

      if (process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim()) {
        // Application Default Credentials del entorno (Netlify, GCP, etc.).
        return initializeApp();
      }
      return null;
    })().catch((error) => {
      appPromise = null;
      throw error;
    });
  }
  return appPromise;
}

export async function verifyAdminIdToken(
  token: string,
  tenantId = DEFAULT_TENANT_ID,
): Promise<AdminIdentity> {
  const app = await resolveApp();
  if (!app) {
    throw new AdminUnavailableError("Firebase Admin no está configurado en el servidor.");
  }
  const decoded = await getAuth(app).verifyIdToken(token);
  if (decoded.role === "admin") {
    return {
      uid: decoded.uid,
      email: decoded.email,
      role: decoded.role,
      roleSource: "claim",
    };
  }

  const storedRole = await resolveStoredRole(decoded.uid, tenantId, decoded.email);
  return {
    uid: decoded.uid,
    email: decoded.email,
    role: storedRole ?? decoded.role,
    roleSource: storedRole ? "firestore" : "none",
  };
}
