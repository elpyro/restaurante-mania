import 'package:shared_preferences/shared_preferences.dart';

/// Tenants operativos. Los tres viven en Firestore bajo `tenants/{tenantId}`;
/// las preferencias locales solo son caché offline, no la fuente de verdad.
const defaultTenantId = 'mania';

/// Preferencia global (no prefijada): selecciona el tenant activo de la app.
const tenantPreferenceKey = 'rm_tenant_id_v1';

/// Header enviado en todas las peticiones a la web pública.
const tenantHeader = 'X-Tenant-Id';

class TenantDefinition {
  const TenantDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.emoji,
  });

  final String id;
  final String label;
  final String description;
  final String emoji;
}

const tenants = <String, TenantDefinition>{
  defaultTenantId: TenantDefinition(
    id: defaultTenantId,
    label: 'Restaurante Manía',
    description: 'Datos reales del restaurante. Sin cambios en esta fase.',
    emoji: '🍽️',
  ),
  'fuego': TenantDefinition(
    id: 'fuego',
    label: 'Fuego · Parrilla & Brasa',
    description: 'Carta de brasa, stock propio y pedidos aislados.',
    emoji: '🔥',
  ),
  'verde': TenantDefinition(
    id: 'verde',
    label: 'Verde · Cocina fresca',
    description: 'Carta fresca, horarios propios y pedidos aislados.',
    emoji: '🌿',
  ),
};

String normalizeTenantId(String? value) {
  final candidate = value?.trim().toLowerCase() ?? '';
  if (candidate.isEmpty) return defaultTenantId;
  return tenants.containsKey(candidate) ? candidate : defaultTenantId;
}

bool isDemoTenant(String tenantId) => tenantId != defaultTenantId;

/// `mania` mantiene las claves legacy; los demás usan
/// `rm_{tenantId}_...` para aislar la caché local de cada restaurante.
String tenantStorageKey(String tenantId, String legacyKey) {
  if (!isDemoTenant(tenantId)) return legacyKey;
  if (legacyKey.startsWith('rm_')) {
    return 'rm_${tenantId}_${legacyKey.substring(3)}';
  }
  return 'rm_${tenantId}_$legacyKey';
}

/// Vista de `SharedPreferences` que aplica el prefijo del tenant activo a
/// todas las claves `rm_*_v1` sin tocar las claves globales.
class TenantPreferences {
  TenantPreferences(this._inner, this.tenantId);

  final SharedPreferences _inner;
  final String tenantId;

  String scope(String key) => tenantStorageKey(tenantId, key);

  String? getString(String key) => _inner.getString(scope(key));

  Future<bool> setString(String key, String value) =>
      _inner.setString(scope(key), value);

  Future<bool> remove(String key) => _inner.remove(scope(key));

  bool containsKey(String key) => _inner.containsKey(scope(key));
}
