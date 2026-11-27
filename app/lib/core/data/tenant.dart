import 'package:shared_preferences/shared_preferences.dart';

/// Tenants operativos. Los tres iniciales viven en Firestore bajo
/// `tenants/{tenantId}`; las preferencias locales solo son caché offline, no la
/// fuente de verdad. Los restaurantes creados desde la APK se registran en
/// caliente con `registerTenant` (y se redescubren al arrancar desde Firestore).
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

final tenants = <String, TenantDefinition>{
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

/// IDs permitidos para instancias creadas por el usuario.
bool isValidTenantId(String value) =>
    RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(value);

/// Registra (o actualiza) una instancia creada en tiempo de ejecución.
void registerTenant(TenantDefinition definition) {
  if (isValidTenantId(definition.id)) tenants[definition.id] = definition;
}

/// Convierte el nombre visible de un restaurante en un ID estable.
String tenantIdFromName(String name) {
  final base = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9áéíóúñü ]'), ' ')
      .replaceAll(RegExp(r'[áàä]'), 'a')
      .replaceAll(RegExp(r'[éèë]'), 'e')
      .replaceAll(RegExp(r'[íìï]'), 'i')
      .replaceAll(RegExp(r'[óòö]'), 'o')
      .replaceAll(RegExp(r'[úùü]'), 'u')
      .replaceAll(RegExp(r'ñ'), 'n')
      .trim()
      .replaceAll(RegExp(r'\s+'), '-');
  final cleaned = base.replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  if (cleaned.isEmpty) return 'restaurante';
  return cleaned.length > 56 ? cleaned.substring(0, 56) : cleaned;
}

String normalizeTenantId(String? value) {
  final candidate = value?.trim().toLowerCase() ?? '';
  if (candidate.isEmpty) return defaultTenantId;
  return tenants.containsKey(candidate) ? candidate : defaultTenantId;
}

bool isDemoTenant(String tenantId) => tenantId != defaultTenantId;

/// Instancias fijas: conservan sus datos y comportamiento históricos.
const fixedTenantIds = <String>{defaultTenantId, 'fuego', 'verde'};

bool isFixedTenant(String tenantId) => fixedTenantIds.contains(tenantId);

/// Restaurantes creados por el usuario: arrancan con la plantilla genérica.
bool isTemplateTenant(String tenantId) =>
    isValidTenantId(tenantId) && !isFixedTenant(tenantId);

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
