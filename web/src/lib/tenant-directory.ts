import { listDocuments } from "./firebase/rest";
import {
  DEFAULT_TENANT_ID,
  TENANTS,
  isValidTenantId,
  normalizeTenantId,
  registerTenantDefinition,
} from "./tenants";

export interface TenantDirectoryEntry {
  id: string;
  name: string;
  emoji: string;
  city: string;
  isDefault: boolean;
}

interface TenantDocument {
  name?: string;
  label?: string;
  emoji?: string;
  city?: string;
  preset?: string;
}

const PRESET_EMOJI: Record<string, string> = {
  mania: "🍽️",
  fuego: "🔥",
  verde: "🌿",
  noche: "🌙",
  custom: "🍴",
};

/**
 * Directorio público de restaurantes para la portada neutra. Los tenants fijos
 * siempre están disponibles; el resto se descubre desde `tenants/{id}` en
 * Firestore (lectura pública según firestore.rules).
 */
export async function getTenantDirectory(): Promise<TenantDirectoryEntry[]> {
  const entries = new Map<string, TenantDirectoryEntry>();

  for (const [id, definition] of Object.entries(TENANTS)) {
    entries.set(id, {
      id,
      name: definition.label,
      emoji: PRESET_EMOJI[definition.preset] ?? "🍽️",
      city: definition.city,
      isDefault: id === DEFAULT_TENANT_ID,
    });
  }

  let docs: Array<{ id: string } & TenantDocument> = [];
  try {
    docs = await listDocuments<{ id: string } & TenantDocument>(
      "tenants",
      (doc) => ({ ...(doc.data as TenantDocument), id: doc.id }),
      60,
    );
  } catch {
    // Sin Firestore (tests/desarrollo) se muestra solo el directorio fijo.
  }

  for (const doc of docs) {
    const id = normalizeTenantId(doc.id);
    if (!id || !isValidTenantId(id)) continue;
    const name =
      doc.name?.trim() || doc.label?.trim() || entries.get(id)?.name || id;
    const city = doc.city?.trim() ?? entries.get(id)?.city ?? "";
    const emoji = doc.emoji?.trim() || PRESET_EMOJI[doc.preset ?? ""] || "🍴";

    registerTenantDefinition({ id, label: name, city });
    entries.set(id, {
      id,
      name,
      emoji,
      city,
      isDefault: id === DEFAULT_TENANT_ID,
    });
  }

  return [...entries.values()].sort((a, b) => {
    if (a.isDefault) return -1;
    if (b.isDefault) return 1;
    return a.name.localeCompare(b.name, "es");
  });
}
