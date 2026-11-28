// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import '../models/cash_shift.dart';
import '../models/category.dart';
import '../models/customer.dart';
import '../models/ingredient.dart';
import '../models/inventory_loss.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../models/restaurant_appearance.dart';
import '../models/restaurant_settings.dart';
import '../models/restaurant_table.dart';
import '../models/role.dart';
import '../models/web_visit.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/media_upload_service.dart';
import '../services/notification_service.dart';
import 'api_transport.dart';
import '../utils/formatters.dart';
import 'seed_data.dart';
import 'tenant.dart';

class ProductSales {
  const ProductSales({
    required this.name,
    required this.quantity,
    required this.total,
  });

  final String name;
  final int quantity;
  final double total;
}

class DailySales {
  const DailySales({required this.day, required this.total});

  final DateTime day;
  final double total;
}

/// Granularidad del gráfico de ventas. Un turno se ve por horas; los rangos
/// largos se agrupan para no dibujar 90 barras en una pantalla de teléfono.
enum SalesBucket { hour, day, week, month }

/// Reconcilia el inventario local con el feed publicado por la web.
///
/// La web es la fuente de verdad de `stock`, `minStock`, `name` y `unit`.
/// Los insumos con cambios pendientes de subir ganan (offline-first) y no se
/// borran aunque ya no estén en el servidor. El `cost` es local: la web no lo
/// publica, así que se conserva.
@visibleForTesting
List<Ingredient> mergeServerIngredients(
  List<Ingredient> local,
  List<Ingredient> remote,
  Set<String> pendingIds,
) {
  final remoteById = <String, Ingredient>{
    for (final ingredient in remote) ingredient.id: ingredient,
  };
  final merged = <Ingredient>[];

  for (final ingredient in local) {
    if (pendingIds.contains(ingredient.id)) {
      merged.add(ingredient);
      continue;
    }
    final server = remoteById[ingredient.id];
    if (server == null) continue;
    merged.add(
      ingredient.copyWith(
        name: server.name,
        unit: server.unit,
        stock: server.stock,
        minStock: server.minStock,
      ),
    );
  }

  final localIds = merged.map((ingredient) => ingredient.id).toSet();
  for (final ingredient in remote) {
    if (localIds.contains(ingredient.id)) continue;
    merged.add(ingredient);
  }
  return merged;
}

/// Repositorio offline-first.
///
/// Persiste todo en SharedPreferences y mantiene una cola de pedidos sin
/// sincronizar. Cuando el dispositivo recupera la conexión, la cola se envía
/// (en la demo se marca como sincronizada; el adaptador de Firestore puede
/// conectarse en [syncPendingOrders]).
class TenantMembership {
  const TenantMembership({
    required this.tenantId,
    required this.role,
    this.name = '',
    this.email = '',
  });
  final String tenantId;
  final String role;
  final String name;
  final String email;
}

class TenantSelectionRequiredException implements Exception {
  TenantSelectionRequiredException(this.memberships);
  final List<TenantMembership> memberships;
}

class RestaurantRepository extends ChangeNotifier {
  RestaurantRepository._({
    required TenantPreferences prefs,
    required String tenantId,
    required ConnectivityService connectivity,
    required bool ownsConnectivity,
    required List<Category> categories,
    required List<MenuItem> items,
    required List<Ingredient> ingredients,
    required List<Order> orders,
    required List<InventoryLoss> inventoryLosses,
    required List<RestaurantTable> tables,
    required List<CustomerRecord> customers,
    required List<WebVisit> webVisits,
    required Map<String, Map<String, dynamic>> pendingMenuStatuses,
    required Set<String> dirtyMenuItemIds,
    required Map<String, Map<String, dynamic>> pendingIngredientStocks,
    required CashShift activeShift,
    required List<CashShift> closedShifts,
    required Map<String, Map<String, dynamic>> pendingCashShiftClosures,
    required RestaurantSettings settings,
    required RestaurantAppearance restaurantAppearance,
    required RestaurantAppearance? pendingRestaurantConfig,
    required Map<String, dynamic>? pendingConfigPatch,
    required Map<String, bool> pendingFeaturedItems,
    required bool firebaseSignedIn,
    required AuthService authService,
    required AppUser? currentUser,
    required List<AppUser> users,
    required DateTime? lastSync,
    required String serverUrl,
    required bool webSyncEnabled,
    required ApiTransport api,
    required String deviceId,
    NotificationPreferences? notificationPreferences,
  }) : _prefs = prefs,
       _api = api,
       _deviceId = deviceId,
       _notificationPreferences =
           notificationPreferences ?? const NotificationPreferences(),
       tenantId = tenantId,
       _connectivity = connectivity,
       _ownsConnectivity = ownsConnectivity,
       _categories = categories,
       _items = items,
       _ingredients = ingredients,
       _orders = orders,
       _inventoryLosses = inventoryLosses,
       _tables = tables,
       _customers = customers,
       _webVisits = webVisits,
       _pendingMenuStatuses = pendingMenuStatuses,
       _dirtyMenuItemIds = dirtyMenuItemIds,
       _pendingIngredientStocks = pendingIngredientStocks,
       _activeShift = activeShift,
       _closedShifts = closedShifts,
       _pendingCashShiftClosures = pendingCashShiftClosures,
       _settings = settings,
       _restaurantAppearance = restaurantAppearance,
       _pendingRestaurantConfig = pendingRestaurantConfig,
       _pendingConfigPatch = pendingConfigPatch,
       _pendingFeaturedItems = pendingFeaturedItems,
       _firebaseSignedIn = firebaseSignedIn,
       _authService = authService,
       _currentUser = currentUser,
       _users = users,
       _lastSync = lastSync,
       _serverUrl = serverUrl,
       _webSyncEnabled = webSyncEnabled {
    _connectivity.online.addListener(_onConnectivityChanged);
  }

  /// Identificador estable del dispositivo, global (no por tenant): se usa
  /// para registrar el dispositivo en `all_user` y enviar notificaciones push.
  static const _kDeviceId = 'rm_device_id_v1';

  static const _kCategories = 'rm_categories_v1';
  static const _kItems = 'rm_menu_items_v1';
  static const _kIngredients = 'rm_ingredients_v1';
  static const _kOrders = 'rm_orders_v1';
  static const _kInventoryLosses = 'rm_inventory_losses_v1';
  static const _kTables = 'rm_tables_v1';
  static const _kSettings = 'rm_settings_v1';
  static const _kSession = 'rm_session_v1';
  static const _kUsers = 'rm_users_v1';
  static const _kLastSync = 'rm_last_sync_v1';
  static const _kServerUrl = 'rm_server_url_v1';
  static const _kCustomers = 'rm_customers_v1';
  static const _kWebVisits = 'rm_web_visits_v1';
  static const _kPendingMenuStatuses = 'rm_pending_menu_statuses_v1';
  static const _kPendingMenuItemPatches = 'rm_pending_menu_item_patches_v1';
  static const _kPendingIngredientStocks = 'rm_pending_ingredient_stocks_v1';
  static const _kActiveCashShift = 'rm_active_cash_shift_v1';
  static const _kCashShifts = 'rm_cash_shifts_v1';
  static const _kPendingCashShiftClosures = 'rm_pending_cash_shift_closures_v1';
  static const _kAppearance = 'rm_restaurant_appearance_v1';
  static const _kPendingRestaurantConfig = 'rm_pending_restaurant_config_v1';
  static const _kPendingConfigPatch = 'rm_pending_config_patch_v1';
  static const _kPendingFeaturedItems = 'rm_pending_featured_items_v1';

  /// URL de la web pública para importar los pedidos creados en línea (solo
  /// transporte web/QA; en producción se usa Firestore directo).
  /// `--dart-define=WEB_API_URL=http://mi-servidor:3000`.
  static const defaultServerUrl = String.fromEnvironment(
    'WEB_API_URL',
    defaultValue: '',
  );

  /// En producción la APK habla directamente con Firestore REST con el idToken
  /// del usuario; el adaptador web queda para QA y tests.
  /// `--dart-define=DIRECT_FIRESTORE=false` fuerza el transporte web.
  static const _directFirestoreByDefault = bool.fromEnvironment(
    'DIRECT_FIRESTORE',
    defaultValue: true,
  );

  /// Transporte activo: `true` cuando se habla directo con Firestore REST.
  bool get useDirectFirestore => _api is FirestoreTransport;

  static const _pollInterval = Duration(seconds: 12);

  /// Tenant activo. `mania` usa las claves históricas; los demás prefijan la
  /// caché local. En producción los datos vienen de Firestore por tenant.
  String tenantId;
  TenantPreferences _prefs;
  final ConnectivityService _connectivity;
  final bool _ownsConnectivity;

  List<Category> _categories;
  List<MenuItem> _items;
  List<Ingredient> _ingredients;
  List<Order> _orders;
  List<InventoryLoss> _inventoryLosses;
  List<RestaurantTable> _tables;
  List<CustomerRecord> _customers;
  List<WebVisit> _webVisits;
  RestaurantSettings _settings;
  AppUser? _currentUser;
  List<AppUser> _users;
  DateTime? _lastSync;
  String _serverUrl;
  bool _syncing = false;
  bool _pullingServerOrders = false;
  bool _flushingMenuStatuses = false;
  bool _flushingIngredientStocks = false;
  bool _flushingInventoryLosses = false;
  bool _pullingInventoryLosses = false;
  bool _pullingServerIngredients = false;
  bool _pullingServerMenuStatuses = false;
  bool _pullingCashShifts = false;
  bool _flushingCashShifts = false;
  bool _flushingRestaurantConfig = false;
  bool _pullingRestaurantConfig = false;
  final AuthService _authService;
  final bool _webSyncEnabled;
  Map<String, Map<String, dynamic>> _pendingMenuStatuses = {};
  Set<String> _dirtyMenuItemIds = {};
  // Solo publicamos estados/favoritos de platos que existen en Firestore.
  // Sin esto, una semilla local crearía documentos parciales con solo `status`.
  bool _serverMenuCatalogLoaded = false;
  Set<String> _serverMenuCatalogIds = <String>{};
  Map<String, Map<String, dynamic>> _pendingIngredientStocks = {};
  Map<String, Map<String, dynamic>> _pendingCashShiftClosures = {};
  CashShift _activeShift;
  List<CashShift> _closedShifts;
  RestaurantAppearance _restaurantAppearance;
  RestaurantAppearance? _pendingRestaurantConfig;
  Map<String, dynamic>? _pendingConfigPatch;
  Map<String, bool> _pendingFeaturedItems;
  bool _firebaseSignedIn;
  bool _needsFirebaseReLogin = false;
  // No final: `switchTenant` debe reemplazarlo por el transporte del nuevo
  // tenant (si no, las lecturas siguen apuntando al tenant anterior).
  ApiTransport _api;
  final String _deviceId;
  NotificationPreferences _notificationPreferences;
  // Evita avisar sobre datos antiguos en la primera descarga del arranque.
  bool _ordersPrimed = false;
  bool _ingredientsPrimed = false;
  bool _shiftsPrimed = false;

  /// Notificación tocada por el usuario; `AppShell` la consume para navegar.
  final ValueNotifier<NotificationTarget?> notificationTarget =
      ValueNotifier<NotificationTarget?>(null);

  Future<void>? _syncFuture;
  Timer? _webPollTimer;

  /// Descubre instancias creadas desde la APK (`tenants/{id}` en Firestore)
  /// antes de resolver el tenant guardado. Sin esto, un restaurante nuevo se
  /// normalizaría a `mania` al reiniciar la app.
  static Future<void> _loadTenantRegistry(AuthService auth) async {
    if (!_directFirestoreByDefault || AuthService.firebaseApiKey.isEmpty)
      return;
    try {
      final transport = FirestoreTransport.fromEnvironment(
        auth: auth,
        tenantId: defaultTenantId,
      );
      final response = await transport.send(
        'GET',
        '/api/tenants',
        authorized: false,
      );
      if (!response.ok) return;
      final rows = response.json?['tenants'];
      if (rows is! List) return;
      for (final row in rows) {
        if (row is! Map<String, dynamic>) continue;
        final id = (row['id'] as String?)?.trim().toLowerCase() ?? '';
        if (!isValidTenantId(id)) continue;
        final name = (row['name'] as String?)?.trim();
        registerTenant(
          TenantDefinition(
            id: id,
            label: name?.isNotEmpty == true ? name! : id,
            description: (row['description'] as String?) ?? '',
            emoji: (row['emoji'] as String?) ?? '🍽️',
          ),
        );
      }
    } catch (_) {
      // Registro en caliente best-effort: los tenants fijos siguen funcionando.
    }
  }

  static Future<RestaurantRepository> load({
    ConnectivityService? connectivity,
    bool watchConnectivity = true,
    AuthService? authService,
    bool? requireFirebaseSignIn,
    String? tenantId,
    ApiTransport? transport,
  }) async {
    final rawPrefs = await SharedPreferences.getInstance();
    final notificationPreferences = await NotificationPreferences.load();
    final registryAuth = authService ?? AuthService();
    await _loadTenantRegistry(registryAuth);
    var deviceId = rawPrefs.getString(_kDeviceId)?.trim() ?? '';
    if (deviceId.isEmpty) {
      deviceId =
          'dev-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
          '${Random.secure().nextInt(0x7fffffff).toRadixString(36)}';
      await rawPrefs.setString(_kDeviceId, deviceId);
    }
    final activeTenantId = normalizeTenantId(
      tenantId ?? rawPrefs.getString(tenantPreferenceKey),
    );
    final prefs = TenantPreferences(rawPrefs, activeTenantId);
    final service = connectivity ?? ConnectivityService();
    if (watchConnectivity) {
      await service.init();
    }

    final serverUrl = _normalizeServerUrl(
      prefs.getString(_kServerUrl) ?? defaultServerUrl,
    );
    final auth = authService ?? AuthService();
    final api =
        transport ??
        (_directFirestoreByDefault && AuthService.firebaseApiKey.isNotEmpty
            ? FirestoreTransport.fromEnvironment(
                auth: auth,
                tenantId: activeTenantId,
              )
            : WebApiTransport(
                baseUrl: serverUrl,
                auth: auth,
                tenantId: activeTenantId,
              ));

    // Un tenant dinámico sin configuración es un restaurante nuevo y usa la
    // plantilla. Si ya publicó su configuración, conserva el catálogo
    // histórico que sirve la web (sin sobreescribirlo con la plantilla).
    final isDynamicTenant = isTemplateTenant(activeTenantId);
    var hasExistingServerConfig = false;
    if (isDynamicTenant) {
      try {
        final response = await api.send(
          'GET',
          '/api/restaurant/config',
          authorized: false,
        );
        if (response.ok) {
          final decoded = jsonDecode(response.body);
          final config = decoded is Map<String, dynamic>
              ? decoded['config']
              : null;
          final name = config is Map<String, dynamic> ? config['name'] : null;
          hasExistingServerConfig =
              name is String &&
              name.trim().isNotEmpty &&
              name.trim() != SeedData.genericSettings.name;
        }
      } catch (_) {
        // Sin servidor se mantiene la plantilla local del restaurante nuevo.
      }
    }
    final useHistoricalSeed = isDynamicTenant && hasExistingServerConfig;
    final useGenericSeed = isDynamicTenant && !hasExistingServerConfig;

    // En producción (API key Firebase compilada) no sembramos datos demo:
    // el dispositivo arranca limpio y se sincroniza desde Firestore. En
    // debug/tests sin API key se mantiene el seed para el modo demo.
    final seedDemo = AuthService.firebaseApiKey.isEmpty;
    // Los restaurantes creados por el usuario arrancan con la plantilla
    // genérica, nunca con los datos de Manía. Un tenant dinámico que ya tiene
    // configuración guardada (casos históricos como `taquitos-mexicanos`)
    // conserva el catálogo de siempre, igual que hace la web.
    final categories = _readList<Category>(
      prefs,
      _kCategories,
      Category.fromJson,
    );
    final storedItems = _readList<MenuItem>(prefs, _kItems, MenuItem.fromJson);
    final seedItems = useGenericSeed
        ? SeedData.genericMenuItems()
        : seedDemo || useHistoricalSeed
        ? SeedData.menuItemsFor(activeTenantId)
        : const <MenuItem>[];
    final migratedItems = _migrateRecipeIngredientIds(storedItems);
    final items = storedItems.isEmpty
        ? seedItems
        : (seedDemo
              ? _hydrateSeedExtras(migratedItems, seedItems)
              : migratedItems);
    final storedIngredients = _readList<Ingredient>(
      prefs,
      _kIngredients,
      Ingredient.fromJson,
    );
    final ingredients = _migrateIngredientIds(storedIngredients);
    final orders = _readList<Order>(prefs, _kOrders, Order.fromJson);
    final inventoryLosses = _readList<InventoryLoss>(
      prefs,
      _kInventoryLosses,
      InventoryLoss.fromJson,
    )..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final tablesFromPrefs = _readList<RestaurantTable>(
      prefs,
      _kTables,
      RestaurantTable.fromJson,
    );
    // Una mesa que quedó marcada como ocupada pero no tiene un pedido activo
    // es estado obsoleto de una versión anterior: se devuelve a libre para que
    // el POS siempre arranque con mesas coherentes.
    final activeOrderIds = orders.map((order) => order.id).toSet();
    var tablesNormalized = false;
    final tables = tablesFromPrefs.map((table) {
      if (table.status == TableStatus.libre) return table;
      final orderId = table.currentOrderId?.trim() ?? '';
      if (orderId.isNotEmpty && activeOrderIds.contains(orderId)) return table;
      tablesNormalized = true;
      return table.copyWith(status: TableStatus.libre, clearOrder: true);
    }).toList();
    final settingsRaw = prefs.getString(_kSettings);
    final settings = settingsRaw == null
        ? (useGenericSeed
              ? SeedData.genericSettings
              : seedDemo || useHistoricalSeed
              ? SeedData.settings
              : RestaurantSettings.defaults)
        : RestaurantSettings.fromJson(
            jsonDecode(settingsRaw) as Map<String, dynamic>,
          );
    final sessionRaw = prefs.getString(_kSession);
    AppUser? currentUser = sessionRaw == null
        ? null
        : AppUser.fromJson(jsonDecode(sessionRaw) as Map<String, dynamic>);
    final storedUsers = _readList(prefs, _kUsers, AppUser.fromJson);
    final users = storedUsers.isEmpty
        ? (useGenericSeed || useHistoricalSeed
              ? <AppUser>[]
              : seedDemo
              ? [...SeedData.users]
              : <AppUser>[])
        : storedUsers;
    final lastSyncRaw = prefs.getString(_kLastSync);
    final lastSync = lastSyncRaw == null
        ? null
        : DateTime.tryParse(lastSyncRaw);
    final customers = _readList(prefs, _kCustomers, CustomerRecord.fromJson);
    final webVisits = _readList(prefs, _kWebVisits, WebVisit.fromJson);
    final pendingMenuStatuses = _readPendingMenuStatuses(prefs);
    final pendingIngredientStocks = _readPendingIngredientStocks(prefs);
    final activeShiftRaw = prefs.getString(_kActiveCashShift);
    final activeShift = activeShiftRaw == null
        ? _newCashShift(DateTime.now(), user: currentUser)
        : CashShift.fromJson(
            jsonDecode(activeShiftRaw) as Map<String, dynamic>,
          );
    final closedShifts = _readList(prefs, _kCashShifts, CashShift.fromJson)
      ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    final pendingCashShiftClosures = _readPendingCashShiftClosures(prefs);
    final appearanceRaw = prefs.getString(_kAppearance);
    final appearance = appearanceRaw == null
        ? (useGenericSeed
              ? RestaurantAppearance.generic
              : RestaurantAppearance.defaults)
        : RestaurantAppearance.fromStoredJson(appearanceRaw);
    final pendingConfig = RestaurantAppearance.tryFromStoredJson(
      prefs.getString(_kPendingRestaurantConfig),
    );
    final pendingConfigPatch = _readPendingConfigPatch(prefs);
    final pendingFeaturedItems = _readPendingFeaturedItems(prefs);
    final dirtyMenuItemIds = _readDirtyMenuItemIds(prefs);
    var firebaseSignedIn = false;
    // Sin clave pública no puede existir una sesión Firebase: evita además
    // consultar el almacén seguro en tests y dispositivos sin el plugin.
    if (authService != null || AuthService.firebaseApiKey.isNotEmpty) {
      try {
        firebaseSignedIn = await auth.isSignedIn;
      } catch (_) {
        // Sin almacén seguro (tests/desktop) se mantiene el modo demo.
      }
    }
    // Con API key Firebase compilada, una sesión local sin idToken no puede
    // publicar nada: se fuerza el login sin borrar las colas offline.
    final mustHaveFirebaseSession =
        requireFirebaseSignIn ?? AuthService.firebaseApiKey.isNotEmpty;
    if (mustHaveFirebaseSession && !firebaseSignedIn && currentUser != null) {
      currentUser = null;
      await prefs.remove(_kSession);
    }

    final repository = RestaurantRepository._(
      prefs: prefs,
      tenantId: activeTenantId,
      connectivity: service,
      ownsConnectivity: connectivity == null,
      categories: categories.isEmpty
          ? (useGenericSeed
                ? [...SeedData.genericCategories]
                : seedDemo || useHistoricalSeed
                ? [...SeedData.categories]
                : <Category>[])
          : categories,
      items: items,
      ingredients: ingredients.isEmpty
          ? (useGenericSeed
                ? [...SeedData.genericIngredients]
                : seedDemo || useHistoricalSeed
                ? SeedData.ingredientsFor(activeTenantId)
                : <Ingredient>[])
          : ingredients,
      orders: _hydrateOrderExtras(
        orders.isEmpty
            ? (useGenericSeed
                  ? <Order>[]
                  : seedDemo || useHistoricalSeed
                  ? SeedData.ordersFor(activeTenantId)
                  : <Order>[])
            : orders,
        seedItems,
      )..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      inventoryLosses: inventoryLosses,
      tables: tables.isEmpty
          ? (useGenericSeed || useHistoricalSeed
                ? <RestaurantTable>[]
                : seedDemo
                ? SeedData.tables()
                : <RestaurantTable>[])
          : tables,
      customers: customers,
      webVisits: webVisits,
      pendingMenuStatuses: pendingMenuStatuses,
      dirtyMenuItemIds: dirtyMenuItemIds,
      pendingIngredientStocks: pendingIngredientStocks,
      activeShift: activeShift,
      closedShifts: closedShifts,
      pendingCashShiftClosures: pendingCashShiftClosures,
      settings: settings,
      restaurantAppearance: appearance,
      pendingRestaurantConfig: pendingConfig,
      pendingConfigPatch: pendingConfigPatch,
      pendingFeaturedItems: pendingFeaturedItems,
      firebaseSignedIn: firebaseSignedIn,
      authService: auth,
      currentUser: currentUser,
      users: users,
      lastSync: lastSync,
      serverUrl: serverUrl,
      webSyncEnabled: watchConnectivity,
      api: api,
      deviceId: deviceId,
      notificationPreferences: notificationPreferences,
    );

    repository._rebuildCustomersFromOrders(persist: customers.isEmpty);

    if (categories.isEmpty) await repository._persistCategories();
    if (storedItems.isEmpty ||
        _hasLegacyRecipeId(storedItems) ||
        !_sameItemExtras(storedItems, items)) {
      await repository._persistItems();
    }
    if (ingredients.isEmpty || _hasLegacyIngredientId(storedIngredients)) {
      await repository._persistIngredients();
    }
    if (orders.isEmpty) await repository._persistOrders();
    if (tables.isEmpty || tablesNormalized) await repository._persistTables();
    if (storedUsers.isEmpty) await repository._persistUsers();
    if (customers.isEmpty) await repository._persistCustomers();
    if (activeShiftRaw == null) await repository._persistActiveShift();
    if (appearanceRaw == null) await repository._persistAppearance();
    await repository._applyTableCount();

    if (watchConnectivity) {
      repository._startWebPolling();
    }

    return repository;
  }

  /// Cambia de instancia demo sin recrear el provider. El estado anterior
  /// queda guardado bajo su propio prefijo y el nuevo se carga desde sus
  /// claves; Manía nunca se mezcla con `fuego` ni `verde`.
  Future<void> switchTenant(String id) async {
    final nextId = normalizeTenantId(id);
    if (nextId == tenantId) return;
    _webPollTimer?.cancel();
    _webPollTimer = null;
    _connectivity.online.removeListener(_onConnectivityChanged);
    try {
      final next = await RestaurantRepository.load(
        connectivity: _connectivity,
        watchConnectivity: false,
        authService: _authService,
        requireFirebaseSignIn: nextId == defaultTenantId ? null : false,
        tenantId: nextId,
      );
      final rawPrefs = await SharedPreferences.getInstance();
      await rawPrefs.setString(tenantPreferenceKey, nextId);
      _copyTenantStateFrom(next);
    } finally {
      _connectivity.online.addListener(_onConnectivityChanged);
      if (_webSyncEnabled) _startWebPolling();
      notifyListeners();
    }
  }

  void _copyTenantStateFrom(RestaurantRepository other) {
    tenantId = other.tenantId;
    _api = other._api;
    _prefs = other._prefs;
    _categories = other._categories;
    _items = other._items;
    _ingredients = other._ingredients;
    _orders = other._orders;
    _inventoryLosses = other._inventoryLosses;
    _tables = other._tables;
    _customers = other._customers;
    _webVisits = other._webVisits;
    _settings = other._settings;
    _currentUser = other._currentUser;
    _users = other._users;
    _lastSync = other._lastSync;
    _serverUrl = other._serverUrl;
    _pendingMenuStatuses = other._pendingMenuStatuses;
    _dirtyMenuItemIds = other._dirtyMenuItemIds;
    _serverMenuCatalogLoaded = other._serverMenuCatalogLoaded;
    _serverMenuCatalogIds = other._serverMenuCatalogIds;
    _pendingIngredientStocks = other._pendingIngredientStocks;
    _pendingCashShiftClosures = other._pendingCashShiftClosures;
    _activeShift = other._activeShift;
    _closedShifts = other._closedShifts;
    _restaurantAppearance = other._restaurantAppearance;
    _pendingRestaurantConfig = other._pendingRestaurantConfig;
    _pendingConfigPatch = other._pendingConfigPatch;
    _pendingFeaturedItems = other._pendingFeaturedItems;
    _firebaseSignedIn = other._firebaseSignedIn;
    _needsFirebaseReLogin = false;
    _syncing = false;
    _pullingServerOrders = false;
    _flushingMenuStatuses = false;
    _flushingIngredientStocks = false;
    _flushingInventoryLosses = false;
    _pullingInventoryLosses = false;
    _pullingServerIngredients = false;
    _pullingServerMenuStatuses = false;
    _pullingCashShifts = false;
    _flushingCashShifts = false;
    _flushingRestaurantConfig = false;
    _pullingRestaurantConfig = false;
    _ordersPrimed = other._ordersPrimed;
    _ingredientsPrimed = other._ingredientsPrimed;
    _shiftsPrimed = other._shiftsPrimed;
    _syncFuture = null;
  }

  /// El insumo del café se llamaba `cafe-huila` en versiones anteriores; la
  /// web y Firestore usan `cafe`. Migrar evita que la app siga descontando un
  /// documento que no existe en el catálogo compartido.
  static const _legacyCafeIngredientId = 'cafe-huila';
  static const _cafeIngredientId = 'cafe';

  static bool _hasLegacyIngredientId(List<Ingredient> ingredients) =>
      ingredients.any((ingredient) => ingredient.id == _legacyCafeIngredientId);

  static bool _hasLegacyRecipeId(List<MenuItem> items) => items.any(
    (item) =>
        item.recipe.any((line) => line.ingredientId == _legacyCafeIngredientId),
  );

  static List<Ingredient> _migrateIngredientIds(List<Ingredient> stored) =>
      stored
          .map(
            (ingredient) => ingredient.id == _legacyCafeIngredientId
                ? ingredient.copyWith(id: _cafeIngredientId)
                : ingredient,
          )
          .toList();

  static List<MenuItem> _migrateRecipeIngredientIds(List<MenuItem> stored) =>
      stored.map((item) {
        final recipe = item.recipe
            .map(
              (line) => line.ingredientId == _legacyCafeIngredientId
                  ? line.copyWith(ingredientId: _cafeIngredientId)
                  : line,
            )
            .toList();
        return item.copyWith(recipe: recipe);
      }).toList();

  /// Agrega SKU, recetas y medios a los platos guardados por versiones
  /// anteriores de la app, sin sobrescribir cambios del administrador.
  static List<MenuItem> _hydrateSeedExtras(
    List<MenuItem> stored,
    List<MenuItem> seeds,
  ) {
    final seedById = {for (final item in seeds) item.id: item};
    return stored.map((item) {
      final seed = seedById[item.id];
      if (seed == null) return item;
      return item.copyWith(
        sku: item.sku.isEmpty ? seed.sku : item.sku,
        recipe: item.recipe.isEmpty ? seed.recipe : item.recipe,
        recipeSteps: item.recipeSteps.isEmpty
            ? seed.recipeSteps
            : item.recipeSteps,
        ingredients: item.ingredients.isEmpty
            ? seed.ingredients
            : item.ingredients,
        imageUrl: item.imageUrl.isEmpty ? seed.imageUrl : item.imageUrl,
      );
    }).toList();
  }

  /// Completa imágenes y auditoría inicial en pedidos guardados por versiones
  /// anteriores de la app.
  static List<Order> _hydrateOrderExtras(
    List<Order> orders,
    List<MenuItem> seedItems,
  ) {
    final imageById = {for (final item in seedItems) item.id: item.imageUrl};
    return orders.map((order) {
      final items = order.items
          .map(
            (item) => item.imageUrl.isEmpty
                ? OrderItem(
                    menuItemId: item.menuItemId,
                    name: item.name,
                    price: item.price,
                    quantity: item.quantity,
                    emoji: item.emoji,
                    imageUrl: imageById[item.menuItemId] ?? '',
                  )
                : item,
          )
          .toList();
      final audit = order.auditLog.isEmpty
          ? [
              OrderAuditEntry(
                action: 'Pedido registrado',
                timestamp: order.createdAt,
                actorName: order.createdByName ?? 'Sistema',
                detail: 'Historial inicial del pedido',
              ),
            ]
          : order.auditLog;
      return order.copyWith(
        items: items,
        auditLog: audit,
        paidAt:
            order.paidAt ??
            (order.paymentStatus == PaymentStatus.paid
                ? order.updatedAt
                : null),
        paidByName:
            order.paidByName ??
            (order.paymentStatus == PaymentStatus.paid
                ? (order.source == 'web'
                      ? 'Web pública'
                      : order.updatedByName ?? order.createdByName)
                : null),
      );
    }).toList();
  }

  static bool _sameItemExtras(List<MenuItem> a, List<MenuItem> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      final left = jsonEncode(a[index].toJson());
      final right = jsonEncode(b[index].toJson());
      if (left != right) return false;
    }
    return true;
  }

  static String _normalizeServerUrl(String value) {
    var url = value.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url.isEmpty ? defaultServerUrl : url;
  }

  static CashShift _newCashShift(
    DateTime openedAt, {
    String? id,
    AppUser? user,
  }) => CashShift(
    id: id ?? 'shift-${openedAt.microsecondsSinceEpoch}',
    label:
        'Turno ${twoDigits(openedAt.day)}/${twoDigits(openedAt.month)} '
        '${twoDigits(openedAt.hour)}:${twoDigits(openedAt.minute)}',
    openedAt: openedAt,
    openedBy: user?.id,
    openedByName: user?.name ?? 'Sistema',
  );

  static Map<String, Map<String, dynamic>> _readPendingCashShiftClosures(
    TenantPreferences prefs,
  ) {
    final raw = prefs.getString(_kPendingCashShiftClosures);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      return Map.fromEntries(
        decoded.entries
            .where((entry) => entry.value is Map<String, dynamic>)
            .map(
              (entry) => MapEntry(
                entry.key,
                Map<String, dynamic>.from(entry.value as Map<String, dynamic>),
              ),
            ),
      );
    } catch (_) {
      return {};
    }
  }

  static List<T> _readList<T>(
    TenantPreferences prefs,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<Map<String, dynamic>>().map(fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  static Map<String, Map<String, dynamic>> _readPendingMenuStatuses(
    TenantPreferences prefs,
  ) {
    final raw = prefs.getString(_kPendingMenuStatuses);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      final result = <String, Map<String, dynamic>>{};
      for (final entry in decoded.entries) {
        final status = entry.value is String
            ? entry.value as String
            : entry.value is Map<String, dynamic>
            ? entry.value['status'] as String?
            : null;
        if (status != 'available' && status != 'unavailable') continue;
        final manual = entry.value is Map<String, dynamic>
            ? entry.value['manual'] as bool? ?? status == 'unavailable'
            : status == 'unavailable';
        final reason = entry.value is Map<String, dynamic>
            ? entry.value['reason'] as String?
            : null;
        result[entry.key] = {
          'status': status,
          'manual': manual,
          'reason': reason == 'ingredients' ? 'ingredients' : 'manual',
        };
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  static Set<String> _readDirtyMenuItemIds(TenantPreferences prefs) {
    final raw = prefs.getString(_kPendingMenuItemPatches);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded.whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Map<String, Map<String, dynamic>> _readPendingIngredientStocks(
    TenantPreferences prefs,
  ) {
    final raw = prefs.getString(_kPendingIngredientStocks);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      return Map.fromEntries(
        decoded.entries.map((entry) {
          // Formato anterior: id -> stock. Se migra al patch completo.
          if (entry.value is num) {
            return MapEntry(entry.key, <String, dynamic>{
              'stock': (entry.value as num).toDouble(),
            });
          }
          if (entry.value is Map<String, dynamic>) {
            return MapEntry(
              entry.key,
              Map<String, dynamic>.from(entry.value as Map<String, dynamic>),
            );
          }
          return null;
        }).whereType<MapEntry<String, Map<String, dynamic>>>(),
      );
    } catch (_) {
      return {};
    }
  }

  static Map<String, dynamic>? _readPendingConfigPatch(
    TenantPreferences prefs,
  ) {
    final raw = prefs.getString(_kPendingConfigPatch);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, bool> _readPendingFeaturedItems(TenantPreferences prefs) {
    final raw = prefs.getString(_kPendingFeaturedItems);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is bool) entry.key: entry.value as bool,
      };
    } catch (_) {
      return {};
    }
  }

  // ---------------------------------------------------------------------------
  // Sesión y usuarios
  // ---------------------------------------------------------------------------

  AppUser? get currentUser => _currentUser;
  UserRole? get role => _currentUser?.role;
  bool get isAuthenticated => _currentUser != null;

  /// Cuentas guardadas en el dispositivo (semilla + altas del administrador).
  List<AppUser> get users => List.unmodifiable(_users);

  int get _adminCount =>
      _users.where((user) => user.role == UserRole.admin).length;

  AppUser? userById(String id) {
    final matches = _users.where((user) => user.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  bool isEmailTaken(String email, {String? excludeId}) {
    final normalized = email.trim().toLowerCase();
    return _users.any(
      (user) => user.email.toLowerCase() == normalized && user.id != excludeId,
    );
  }

  bool login(String email, String password) {
    final normalized = email.trim().toLowerCase();
    final matches = _users.where(
      (user) => user.email.toLowerCase() == normalized,
    );
    if (matches.isEmpty || password != SeedData.demoPassword) {
      return false;
    }
    _currentUser = matches.first;
    _prefs.setString(_kSession, jsonEncode(_currentUser!.toJson()));
    notifyListeners();
    return true;
  }

  void loginAs(UserRole role) {
    final matches = _users.where((user) => user.role == role);
    if (matches.isEmpty) return;
    _currentUser = matches.first;
    _prefs.setString(_kSession, jsonEncode(_currentUser!.toJson()));
    notifyListeners();
  }

  /// Inicia sesión con Firebase Auth (REST) y resuelve el rol desde
  /// `tenants/{tenantId}/users/{uid}` en Firestore (nunca exige un usuario
  /// local con el mismo correo ni una coincidencia en la lista local).
  Future<AppUser> loginWithFirebase(
    String email,
    String password, {
    String? tenantId,
  }) async {
    if (AuthService.firebaseApiKey.isEmpty) {
      throw StateError(
        'Firebase no está configurado. Define FIREBASE_WEB_API_KEY.',
      );
    }
    final normalized = email.trim().toLowerCase();
    await _authService.signIn(email, password);
    _firebaseSignedIn = true;
    _needsFirebaseReLogin = false;

    // Resolver tenant desde índice global all_user antes de buscar el perfil.
    if (tenantId != null && tenantId.isNotEmpty && tenantId != this.tenantId) {
      await switchTenant(tenantId);
    }
    if (tenantId == null || tenantId.isEmpty) {
      final memberships = await _resolveAllUserMemberships(normalized);
      if (memberships.length == 1) {
        final target = memberships.first.tenantId;
        if (target != this.tenantId) {
          await switchTenant(target);
        }
      } else if (memberships.length > 1) {
        await _authService.logout();
        _firebaseSignedIn = false;
        throw TenantSelectionRequiredException(memberships);
      }
      // Si 0 memberships, fallback al comportamiento anterior (tenant actual).
    }

    // 1) Rol real desde el documento del tenant (fuente de verdad).
    AppUser? resolved;
    if (useDirectFirestore && _webSyncEnabled && isOnline) {
      resolved = await _resolveFirebaseProfile(email: normalized);
    } else if (_webSyncEnabled && isOnline) {
      // Transporte web (QA): `/api/users` solo es admin; si 403 no pasa nada.
      await pullServerUsers();
      final serverMatch = _users.where(
        (user) => user.email.toLowerCase() == normalized,
      );
      if (serverMatch.isNotEmpty) resolved = serverMatch.first;
    }

    // 2) Fallback: coincidencia local por correo (offline / tests).
    if (resolved == null) {
      final localMatch = _users.where(
        (user) => user.email.toLowerCase() == normalized,
      );
      if (localMatch.isNotEmpty) resolved = localMatch.first;
    }

    if (resolved == null) {
      await _authService.logout();
      _firebaseSignedIn = false;
      throw ArgumentError(
        'Tu cuenta no tiene un rol asignado en la instancia «${this.tenantId}». '
        'Un administrador debe crearla en tenants/${this.tenantId}/users.',
      );
    }

    _currentUser = resolved;
    await _prefs.setString(_kSession, jsonEncode(_currentUser!.toJson()));
    notifyListeners();

    // El índice global ya existe (memberships), así que podemos anotar el
    // dispositivo que abre sesión para futuras notificaciones push.
    await registerDeviceId(email: normalized);

    if (_webSyncEnabled && isOnline) {
      await _flushPendingRestaurantConfig();
      await pullServerRestaurantConfig();
      if (_currentUser?.role == UserRole.admin) await pullServerUsers();
    }
    return _currentUser!;
  }

  /// Crea una instancia nueva de restaurante y deja la sesión lista para entrar.
  ///
  /// 1. Intenta iniciar sesión con el correo y la contraseña written por el
  ///    usuario. Si la cuenta no existe, la crea; si ya existía, exige la
  ///    contraseña actual (nunca crea una cuenta nueva con otro dueño).
  /// 2. Deriva un ID desde el nombre y busca un slug disponible en
  ///    `tenants/{id}` (añade `-2`, `-3`, … si ya está ocupado).
  /// 3. Escribe la instancia con la plantilla genérica: `tenants/{id}`,
  ///    configuración, categoría, dos platillos, insumos, usuario admin y la
  ///    membresía en `all_user/{email}`.
  /// 4. Cambia el repositorio al tenant nuevo y aplica la configuración para
  ///    que las mesas se creen antes de mostrar el POS.
  Future<String> createRestaurant({
    required String email,
    required String password,
    required String restaurantName,
    required String timeZone,
    required String openTime,
    required String closeTime,
    required int tableCount,
    required String countryCode,
    required String phone,
  }) async {
    if (AuthService.firebaseApiKey.isEmpty) {
      throw StateError(
        'Firebase no está configurado. Define FIREBASE_WEB_API_KEY.',
      );
    }
    final normalizedEmail = email.trim().toLowerCase();
    final name = restaurantName.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalizedEmail)) {
      throw ArgumentError('Escribe un correo válido.');
    }
    if (password.length < 6) {
      throw ArgumentError('La contraseña debe tener al menos 6 caracteres.');
    }
    if (name.isEmpty) {
      throw ArgumentError('Escribe el nombre del restaurante.');
    }
    if (!RestaurantSettings.isValidTimeZone(timeZone)) {
      throw ArgumentError('La zona horaria no es válida.');
    }
    if (!RestaurantSettings.isValidTimeOfDay(openTime) ||
        !RestaurantSettings.isValidTimeOfDay(closeTime)) {
      throw ArgumentError('El horario debe tener el formato HH:mm.');
    }
    if (tableCount < 0 || tableCount > RestaurantSettings.maxTableCount) {
      throw ArgumentError(
        'La cantidad de mesas debe estar entre 0 y ${RestaurantSettings.maxTableCount}.',
      );
    }

    // Credenciales: si la cuenta existe se usan las actuales; si no, se crea.
    try {
      await _authService.signIn(normalizedEmail, password);
    } on AuthException catch (error) {
      final code = error.code;
      final couldBeNewAccount =
          code == 'EMAIL_NOT_FOUND' ||
          code == 'INVALID_LOGIN_CREDENTIALS' ||
          code == 'INVALID_PASSWORD';
      if (!couldBeNewAccount) rethrow;
      try {
        await _authService.signUp(normalizedEmail, password);
      } on AuthException catch (signUpError) {
        if (signUpError.code == 'EMAIL_EXISTS') {
          throw const AuthException(
            'Ya existe una cuenta con ese correo. Usa tu contraseña actual.',
          );
        }
        rethrow;
      }
    }
    final uid = await _authService.currentUid();
    if (uid == null || uid.isEmpty) {
      throw StateError('Firebase no devolvió un identificador de usuario.');
    }

    final transport = FirestoreTransport(
      auth: _authService,
      projectId: FirestoreTransport.defaultProjectId,
      tenantId: defaultTenantId,
    );

    // Disponibilidad del slug: nunca sobrescribimos una instancia existente.
    final baseId = tenantIdFromName(name);
    var chosenId = baseId;
    var available = false;
    for (var attempt = 1; attempt <= 20; attempt++) {
      final candidate = attempt == 1 ? baseId : '$baseId-$attempt';
      final response = await transport.send('GET', '/api/tenants/$candidate');
      final existing = response.json?['tenant'];
      if (!response.ok || existing is! Map || existing.isEmpty) {
        chosenId = candidate;
        available = true;
        break;
      }
    }
    if (!available) {
      throw ArgumentError(
        'Ya hay muchas instancias con ese nombre. Elige otro restaurante.',
      );
    }

    final now = DateTime.now().toIso8601String();
    final digitsOnly = chosenId.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final prefix = digitsOnly.isEmpty
        ? 'RM'
        : digitsOnly
              .substring(0, digitsOnly.length < 3 ? digitsOnly.length : 3)
              .toUpperCase();
    final whatsapp = RestaurantSettings.compactNumber(countryCode, phone);
    final hours = RestaurantSettings.scheduleHours(
      days: RestaurantSettings.defaultOpeningDays,
      openTime: openTime,
      closeTime: closeTime,
    );

    await transport.send(
      'PATCH',
      '/api/tenants/$chosenId',
      body: {
        'id': chosenId,
        'name': name,
        'label': name,
        'description': 'Instancia creada desde la APK.',
        // Dueño bootstrap: permite crear el primer usuario admin antes de que
        // exista un perfil en `tenants/{id}/users` (reglas de Firestore).
        'ownerUid': uid,
        'preset': 'custom',
        'emoji': '🍽️',
        'orderPrefix': prefix,
        'currency': 'COP',
        'city': '',
        'address': '',
        'countryCode': countryCode,
        'phone': phone,
        'whatsapp': whatsapp,
        'hours': hours,
        'createdAt': now,
        'updatedAt': now,
      },
    );

    final tenantTransport = FirestoreTransport(
      auth: _authService,
      projectId: FirestoreTransport.defaultProjectId,
      tenantId: chosenId,
    );
    final settings = SeedData.genericSettings.copyWith(
      name: name,
      hours: hours,
      whatsapp: whatsapp,
      countryCode: countryCode,
      phone: phone,
      tableCount: tableCount,
      timeZone: timeZone,
      openTime: openTime,
      closeTime: closeTime,
    );
    final configResponse = await tenantTransport.send(
      'PATCH',
      '/api/restaurant/config',
      body: {
        ...settings.toWebConfigPatch(),
        ...RestaurantAppearance.generic.toJson(),
        'updatedAt': now,
      },
    );
    if (!configResponse.ok) {
      throw StateError(
        'No se pudo guardar la configuración del restaurante (${configResponse.statusCode}).',
      );
    }

    // Catálogo mínimo de la plantilla: las categorías fijas, dos platillos y
    // sus insumos con receta. La web y el POS leen los mismos documentos.
    Future<void> writeTemplateDoc({
      required String path,
      required Map<String, dynamic> body,
      required String label,
    }) async {
      final response = await tenantTransport.send('PATCH', path, body: body);
      if (!response.ok) {
        throw StateError('No se pudo guardar $label (${response.statusCode}).');
      }
    }

    for (final category in SeedData.genericCategories) {
      await writeTemplateDoc(
        path: '/api/menu/categories/${Uri.encodeComponent(category.id)}',
        body: category.toJson(),
        label: 'la categoría inicial',
      );
    }
    for (final item in SeedData.genericMenuItems()) {
      await writeTemplateDoc(
        path: '/api/menu/${Uri.encodeComponent(item.id)}',
        body: item.toJson(),
        label: 'el platillo ${item.name}',
      );
    }
    for (final ingredient in SeedData.genericIngredients) {
      await writeTemplateDoc(
        path: '/api/ingredients/${Uri.encodeComponent(ingredient.id)}',
        body: ingredient.toJson(),
        label: 'el insumo ${ingredient.name}',
      );
    }

    final userResponse = await tenantTransport.send(
      'POST',
      '/api/users',
      query: {'id': uid},
      body: {
        'id': uid,
        'uid': uid,
        'name': name,
        'email': normalizedEmail,
        'role': 'admin',
        'createdAt': now,
      },
    );
    if (!userResponse.ok) {
      throw StateError(
        'No se pudo crear el usuario administrador (${userResponse.statusCode}).',
      );
    }

    // Índice global: se conservan los dispositivos ya registrados para push.
    final existingAllUser = await transport.send(
      'GET',
      '/api/all-users/$normalizedEmail',
    );
    Map<String, dynamic> current = {};
    if (existingAllUser.ok) {
      final data = existingAllUser.json?['allUser'];
      if (data is Map<String, dynamic>)
        current = Map<String, dynamic>.from(data);
    }
    final memberships = <Map<String, dynamic>>[];
    final rawMemberships = current['memberships'];
    if (rawMemberships is List) {
      for (final membership in rawMemberships) {
        if (membership is! Map) continue;
        final map = Map<String, dynamic>.from(membership);
        if (map['tenantId']?.toString() == chosenId) continue;
        memberships.add(map);
      }
    }
    memberships.add({
      'tenantId': chosenId,
      'role': 'admin',
      'uid': uid,
      'name': name,
      'email': normalizedEmail,
    });
    final deviceIds = <String>[];
    final rawDeviceIds = current['deviceIds'];
    if (rawDeviceIds is List) {
      for (final value in rawDeviceIds) {
        final id = value?.toString().trim() ?? '';
        if (id.isNotEmpty && !deviceIds.contains(id)) deviceIds.add(id);
      }
    }
    final lastDevice = current['deviceId']?.toString().trim();
    if (lastDevice != null &&
        lastDevice.isNotEmpty &&
        !deviceIds.contains(lastDevice)) {
      deviceIds.add(lastDevice);
    }
    if (!deviceIds.contains(_deviceId)) deviceIds.add(_deviceId);
    final storedName = current['name']?.toString().trim() ?? '';
    final allUserResponse = await transport.send(
      'PATCH',
      '/api/all-users/$normalizedEmail',
      body: {
        'email': normalizedEmail,
        'name': storedName.isNotEmpty ? storedName : name,
        'memberships': memberships,
        'deviceId': _deviceId,
        'deviceIds': deviceIds,
        'updatedAt': now,
      },
    );
    if (!allUserResponse.ok) {
      throw StateError(
        'No se pudo registrar la cuenta global (${allUserResponse.statusCode}).',
      );
    }

    registerTenant(
      TenantDefinition(
        id: chosenId,
        label: name,
        description: 'Instancia creada desde la APK.',
        emoji: '🍽️',
      ),
    );

    _firebaseSignedIn = true;
    _needsFirebaseReLogin = false;
    if (tenantId != chosenId) await switchTenant(chosenId);

    // La configuración recién escrita es la fuente de verdad: la aplica antes
    // de abrir el POS para que las mesas se creen libres y exactamente en la
    // cantidad indicada al dar de alta el restaurante.
    _settings = settings;
    await _prefs.setString(_kSettings, jsonEncode(settings.toJson()));
    await _applyTableCount();

    final admin = AppUser(
      id: uid,
      name: name,
      email: normalizedEmail,
      role: UserRole.admin,
    );
    _currentUser = admin;
    _users = [..._users.where((user) => user.id != uid), admin];
    await _prefs.setString(_kSession, jsonEncode(admin.toJson()));
    await _persistUsers();
    await pullServerRestaurantConfig();
    await _pullWebCatalogState();
    await registerDeviceId(email: normalizedEmail);
    notifyListeners();
    return chosenId;
  }

  Future<List<TenantMembership>> _resolveAllUserMemberships(
    String email,
  ) async {
    if (!useDirectFirestore || !_webSyncEnabled || !isOnline) return const [];
    try {
      final docId = email.trim().toLowerCase();
      final response = await _request('GET', '/api/all-users/$docId');
      if (!response.ok) return const [];
      final data = response.json?['allUser'];
      if (data is! Map<String, dynamic>) return const [];
      final raw = data['memberships'];
      if (raw is! List) return const [];
      final out = <TenantMembership>[];
      for (final m in raw) {
        if (m is! Map) continue;
        final tenantId = m['tenantId']?.toString() ?? '';
        final role = m['role']?.toString() ?? '';
        if (tenantId.isEmpty || role.isEmpty) continue;
        out.add(
          TenantMembership(
            tenantId: tenantId,
            role: role,
            name: m['name']?.toString() ?? '',
            email: m['email']?.toString() ?? email,
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Lee `tenants/{tenantId}/users/{uid}` con el token del usuario (regla
  /// `request.auth.uid == userId`). `null` si no existe o el rol no es válido.
  Future<AppUser?> _resolveFirebaseProfile({required String email}) async {
    final uid = await _authService.currentUid();
    if (uid == null || uid.isEmpty) return null;
    final response = await _request(
      'GET',
      '/api/users/${Uri.encodeComponent(uid)}',
    );
    if (!response.ok) return null;
    final data = response.json?['user'];
    if (data is! Map<String, dynamic>) return null;
    final role = parseUserRole(data['role']?.toString());
    if (role == null) return null;
    final profileEmail = data['email']?.toString().toLowerCase();
    return AppUser(
      id: uid,
      name: data['name']?.toString() ?? profileEmail ?? email,
      email: profileEmail ?? email,
      role: role,
    );
  }

  /// Parseo estricto de rol: devuelve `null` para valores desconocidos en vez
  /// de `UserRole.fromName` (que por defecto es admin).
  static UserRole? parseUserRole(String? value) {
    for (final role in UserRole.values) {
      if (role.name == value) return role;
    }
    return null;
  }

  /// Quita el token de este dispositivo del índice global al cerrar sesión.
  /// Se llama antes de borrar el idToken para que la escritura siga autorizada.
  Future<void> _unregisterPushToken(String email) async {
    if (!useDirectFirestore || !_webSyncEnabled || !isOnline) return;
    try {
      final normalized = email.trim().toLowerCase();
      final existing = await _request('GET', '/api/all-users/$normalized');
      if (!existing.ok) return;
      final data = existing.json?['allUser'];
      if (data is! Map<String, dynamic>) return;
      final tokens = <String, String>{};
      final raw = data['fcmTokens'];
      if (raw is Map) {
        raw.forEach((key, value) {
          final device = key?.toString().trim() ?? '';
          final token = value?.toString().trim() ?? '';
          if (device.isNotEmpty &&
              device != _deviceId &&
              token.isNotEmpty) {
            tokens[device] = token;
          }
        });
      }
      await _request(
        'PATCH',
        '/api/all-users/$normalized',
        body: {
          'fcmTokens': tokens,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      );
    } catch (_) {
      // Best-effort: el logout nunca depende de la red.
    }
  }

  Future<void> logout() async {
    final email = _currentUser?.email;
    if (email != null) await _unregisterPushToken(email);
    await NotificationService.instance.cancelAll();
    await NotificationService.instance.deleteToken();
    _currentUser = null;
    await _prefs.remove(_kSession);
    _firebaseSignedIn = false;
    _needsFirebaseReLogin = false;
    // La UI debe volver al login aunque el almacén seguro tarde en responder.
    notifyListeners();
    await _authService.logout();
  }

  Future<AppUser> addUser({
    required String name,
    required String email,
    required UserRole role,
  }) async {
    final trimmedName = name.trim();
    final trimmedEmail = email.trim().toLowerCase();
    if (trimmedName.length < 2) {
      throw ArgumentError('Escribe el nombre del usuario.');
    }
    if (!trimmedEmail.contains('@') || !trimmedEmail.contains('.')) {
      throw ArgumentError('Escribe un correo válido.');
    }
    if (isEmailTaken(trimmedEmail)) {
      throw ArgumentError('Ya existe un usuario con ese correo.');
    }
    final user = AppUser(
      id: newId('u'),
      name: trimmedName,
      email: trimmedEmail,
      role: role,
    );
    _users = [user, ..._users];
    await _persistUsers();
    notifyListeners();
    await _pushUserToServer(user, delete: false);
    return user;
  }

  Future<AppUser> updateUser(
    String id, {
    String? name,
    String? email,
    UserRole? role,
  }) async {
    final index = _users.indexWhere((user) => user.id == id);
    if (index < 0) throw ArgumentError('Usuario no encontrado.');
    final current = _users[index];

    final nextName = name?.trim();
    if (nextName != null && nextName.length < 2) {
      throw ArgumentError('Escribe el nombre del usuario.');
    }
    final nextEmail = email?.trim().toLowerCase();
    if (nextEmail != null &&
        (!nextEmail.contains('@') || !nextEmail.contains('.'))) {
      throw ArgumentError('Escribe un correo válido.');
    }
    if (nextEmail != null && isEmailTaken(nextEmail, excludeId: id)) {
      throw ArgumentError('Ya existe un usuario con ese correo.');
    }
    final nextRole = role ?? current.role;
    if (current.role == UserRole.admin &&
        nextRole != UserRole.admin &&
        _adminCount <= 1) {
      throw ArgumentError('Debe quedar al menos un administrador.');
    }

    final updated = current.copyWith(
      name: nextName,
      email: nextEmail,
      role: nextRole,
    );
    _users[index] = updated;
    if (_currentUser?.id == id) {
      _currentUser = updated;
      await _prefs.setString(_kSession, jsonEncode(updated.toJson()));
    }
    await _persistUsers();
    notifyListeners();
    await _pushUserToServer(
      updated,
      delete: false,
      oldEmail: current.email != updated.email ? current.email : null,
    );
    return updated;
  }

  Future<void> deleteUser(String id) async {
    final user = userById(id);
    if (user == null) return;
    if (_currentUser?.id == id) {
      throw ArgumentError('No puedes eliminar tu propia cuenta.');
    }
    if (user.role == UserRole.admin && _adminCount <= 1) {
      throw ArgumentError('Debe quedar al menos un administrador.');
    }
    _users = _users.where((candidate) => candidate.id != id).toList();
    await _persistUsers();
    notifyListeners();
    await _pushUserToServer(user, delete: true);
  }

  /// Publica el alta, edición o baja de una cuenta en `tenants/{tenant}/users`
  /// a través de la web. El cambio ya quedó guardado en el dispositivo: sin
  /// sesión Firebase o sin conexión se conserva localmente y se reenvía en la
  /// siguiente operación.
  Future<void> _pushUserToServer(
    AppUser user, {
    required bool delete,
    String? oldEmail,
  }) async {
    if (!_webSyncEnabled || !isOnline) return;
    if (!useDirectFirestore && _serverUrl.isEmpty) return;
    final response = delete
        ? await _request('DELETE', '/api/users', query: {'id': user.id})
        : await _request(
            'POST',
            '/api/users',
            body: user.toJson(),
            query: {'id': user.id},
          );
    // Solo 401 (sesión) pide re-login; 403 es falta de permiso (no-admin).
    if (response.statusCode == 401) {
      _markNeedsFirebaseReLogin();
    }
    await _syncAllUserEntry(user, delete: delete, oldEmail: oldEmail);
  }

  /// Mantiene `all_user/{email}` en la raíz de Firestore como índice global
  /// de usuarios por tenant/rol para resolver el login sin dropdown de tenant.
  Future<void> _syncAllUserEntry(
    AppUser user, {
    required bool delete,
    String? oldEmail,
  }) async {
    if (!_webSyncEnabled || !isOnline) return;
    if (!useDirectFirestore && _serverUrl.isEmpty) return;
    final email = user.email.trim().toLowerCase();
    if (email.isEmpty) return;

    // El id del documento es el email normalizado sin codificar: la web API
    // usa el mismo criterio en `web/src/app/api/users/route.ts`.
    final docId = email;
    try {
      // Si cambió el correo, eliminar la membresía del tenant en el doc viejo.
      final old = oldEmail?.trim().toLowerCase();
      if (old != null && old.isNotEmpty && old != email) {
        await _syncAllUserEntryRemoveTenant(old, tenantId);
      }

      if (delete) {
        await _syncAllUserEntryRemoveTenant(email, tenantId);
        return;
      }

      final existing = await _request('GET', '/api/all-users/$docId');
      Map<String, dynamic> current = {};
      if (existing.ok) {
        final data = existing.json?['allUser'];
        if (data is Map<String, dynamic>)
          current = Map<String, dynamic>.from(data);
      }

      final rawMemberships = current['memberships'];
      final memberships = <Map<String, dynamic>>[];
      if (rawMemberships is List) {
        for (final m in rawMemberships) {
          if (m is Map) {
            final map = Map<String, dynamic>.from(m);
            if (map['tenantId']?.toString() == tenantId) continue;
            memberships.add(map);
          }
        }
      }
      memberships.add({
        'tenantId': tenantId,
        'role': user.role.name,
        'uid': user.id,
        'name': user.name,
        'email': email,
      });

      await _request(
        'PATCH',
        '/api/all-users/$docId',
        body: {
          'email': email,
          'name': user.name,
          'memberships': memberships,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      );
    } catch (_) {
      // Best-effort: no bloquear el flujo principal por el índice global.
    }
  }

  Future<void> _syncAllUserEntryRemoveTenant(
    String email,
    String tenant,
  ) async {
    final docId = email.trim().toLowerCase();
    try {
      final existing = await _request('GET', '/api/all-users/$docId');
      if (!existing.ok) return;
      final data = existing.json?['allUser'];
      if (data is! Map<String, dynamic>) return;
      final rawMemberships = data['memberships'];
      final memberships = <Map<String, dynamic>>[];
      if (rawMemberships is List) {
        for (final m in rawMemberships) {
          if (m is Map) {
            final map = Map<String, dynamic>.from(m);
            if (map['tenantId']?.toString() == tenant) continue;
            memberships.add(map);
          }
        }
      }
      if (memberships.isEmpty) {
        await _request('DELETE', '/api/all-users/$docId');
      } else {
        await _request(
          'PATCH',
          '/api/all-users/$docId',
          body: {
            'email': email,
            'name': data['name']?.toString() ?? '',
            'memberships': memberships,
            'updatedAt': DateTime.now().toIso8601String(),
          },
        );
      }
    } catch (_) {}
  }

  /// Trae las cuentas desde Firestore (directo o vía la web) y las fusiona con
  /// las del dispositivo usando `uid`/email como clave estable.
  ///
  /// `tenants/{tenantId}/users` solo puede listarlo un administrador del
  /// tenant (reglas de Firestore + rol en la web): para cualquier otro rol se
  /// omite silenciosamente, nunca se interpreta un 403 como sesión vencida.
  Future<int> pullServerUsers() async {
    if (!_webSyncEnabled || !isOnline) return 0;
    if (!useDirectFirestore && _serverUrl.isEmpty) return 0;
    if (_currentUser?.role != UserRole.admin) return 0;
    final response = await _request('GET', '/api/users');
    if (!response.ok) return 0;
    final raw = response.json?['users'];
    if (raw is! List) return 0;
    var changed = 0;
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      final id = (entry['uid'] ?? entry['id'])?.toString() ?? '';
      final email = entry['email']?.toString() ?? '';
      if (id.isEmpty && email.isEmpty) continue;
      // Rol inválido/ausente → se ignora; nunca se promueve a admin.
      final role = parseUserRole(entry['role']?.toString());
      if (role == null) continue;
      final incoming = AppUser(
        id: id.isNotEmpty ? id : email,
        name: entry['name']?.toString() ?? email,
        email: email,
        role: role,
      );
      final index = _users.indexWhere(
        (user) =>
            user.id == incoming.id ||
            (email.isNotEmpty &&
                user.email.toLowerCase() == email.toLowerCase()),
      );
      if (index < 0) {
        _users = [..._users, incoming];
        changed++;
      } else if (_users[index].name != incoming.name ||
          _users[index].role != incoming.role ||
          _users[index].email != incoming.email) {
        final next = [..._users];
        next[index] = incoming;
        _users = next;
        changed++;
      }
    }
    if (changed > 0) {
      await _persistUsers();
      notifyListeners();
    }
    return changed;
  }

  // ---------------------------------------------------------------------------
  // Conectividad y sincronización
  // ---------------------------------------------------------------------------

  bool get isOnline => _connectivity.online.value;
  bool get isSyncing => _syncing;
  DateTime? get lastSync => _lastSync;
  int get pendingSyncCount => _orders.where((order) => !order.synced).length;
  List<Order> get pendingSyncOrders =>
      _orders.where((order) => !order.synced).toList();

  void _onConnectivityChanged() {
    notifyListeners();
    // syncPendingOrders también vacía la cola de configuración; al reconectar
    // se llama siempre para que ese flush no dependa de haber pedidos nuevos.
    if (isOnline) unawaited(syncPendingOrders());
    if (isOnline && _webSyncEnabled) {
      unawaited(_flushInventoryLosses());
      unawaited(pullInventoryLosses());
      unawaited(_flushPendingMenuStatuses());
      unawaited(_flushPendingFeaturedItems());
      unawaited(_pullWebCatalogState());
      unawaited(_flushPendingCashShiftClosures());
      unawaited(pullCashShifts());
      unawaited(_syncRestaurantConfig());
      unawaited(pullServerUsers());
    }
  }

  /// Recarga todo desde la web: pedidos, clientes, visitas, inventario,
  /// estados del menú y turnos de caja. La usa el gesto de «actualizar».
  Future<void> refreshAll() async {
    await syncPendingOrders();
    await _pullWebCatalogState();
    await pullServerOrders();
    await pullServerCustomers();
    await pullServerVisits();
    await _flushPendingCashShiftClosures();
    await pullCashShifts();
    await _flushInventoryLosses();
    await pullInventoryLosses();
    await _syncRestaurantConfig();
    await pullServerUsers();
  }

  Future<void> setOnlineForDemo(bool value) async {
    _connectivity.setManual(value);
    notifyListeners();
    if (value) await syncPendingOrders();
  }

  Future<void> syncPendingOrders() {
    if (!isOnline) return Future<void>.value();
    // Si ya hay una sincronización en curso, devolvemos esa misma operación
    // para que quien espere (UI o test) se resuelva al terminar de verdad.
    final inFlight = _syncFuture;
    if (inFlight != null) return inFlight;

    final completer = Completer<void>();
    _syncFuture = completer.future;
    _runSync().then(
      (_) {
        _syncFuture = null;
        completer.complete();
      },
      onError: (Object error, StackTrace stackTrace) {
        _syncFuture = null;
        completer.completeError(error, stackTrace);
      },
    );
    return completer.future;
  }

  Future<void> _runSync() async {
    _syncing = true;
    notifyListeners();

    try {
      final now = DateTime.now();
      final acknowledged = <String>{};
      for (final order in pendingSyncOrders) {
        if (!isOnline) break;
        // Regla Firestore `isValidOrder`: la orden debe NACER en `pending`.
        // Un pedido offline avanzado antes de sincronizar se crea en `pending`
        // y después se hace PATCH con el estado real (staff `preservesIdentity`).
        final wasAdvanced =
            order.status != OrderStatus.pending ||
            order.paymentStatus != PaymentStatus.pending;
        final payload = order.toJson();
        payload['source'] = 'app';
        // La APK ya descontó el inventario en `pending`: Firestore debe nacer
        // con el flag en true para que el PATCH posterior no vuelva a descontar.
        payload['inventoryDeducted'] = true;
        payload['status'] = OrderStatus.pending.name;
        payload['paymentStatus'] = PaymentStatus.pending.name;
        // Sin seguimiento de conectividad (modo demo/tests) no hay backend al
        // que publicar: la cola se cierra localmente como antes.
        final response = !_webSyncEnabled
            ? const ApiResponse(200, '')
            : await _request(
                'POST',
                '/api/orders',
                body: payload,
                query: {'id': order.id},
              );
        if (!response.ok) continue;
        // Avanzar el estado real tras crearla en `pending`.
        if (wasAdvanced && _webSyncEnabled) {
          await _pushOrderUpdateToServer(order);
        }
        acknowledged.add(order.id);
      }
      if (acknowledged.isNotEmpty) {
        _orders = _orders
            .map(
              (order) => acknowledged.contains(order.id)
                  ? order.copyWith(
                      synced: true,
                      updatedAt: now,
                      inventoryDeducted: true,
                      auditLog: [
                        ...order.auditLog,
                        _audit(
                          'Pedido sincronizado',
                          detail: useDirectFirestore
                              ? 'Enviado a Firestore al restablecerse la conexión'
                              : 'Enviado al servidor al restablecerse la conexión',
                        ),
                      ],
                    )
                  : order,
            )
            .toList();
        await _persistOrders();
      }
      _lastSync = DateTime.now();
      await _prefs.setString(_kLastSync, _lastSync!.toIso8601String());

      // «Sincronizar ahora» también vacía la cola de apariencia/configuración
      // y la de pérdidas (incluida la foto pendiente de subir).
      if (_webSyncEnabled) {
        await _flushPendingRestaurantConfig();
        await _flushInventoryLosses();
      }
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Sincronización con la web pública
  // ---------------------------------------------------------------------------

  /// Punto único de acceso al backend. En QA usa la web pública; en producción
  /// usa Firestore REST directamente con el idToken del usuario.
  Future<ApiResponse> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool authorized = true,
  }) async {
    try {
      return await _api.send(
        method,
        path,
        body: body,
        query: query,
        authorized: authorized,
      );
    } on ApiAuthException {
      _markNeedsFirebaseReLogin();
      return ApiResponse(401, '');
    }
  }

  String get serverUrl => _serverUrl;

  Future<void> updateServerUrl(String value) async {
    _serverUrl = _normalizeServerUrl(value);
    await _prefs.setString(_kServerUrl, _serverUrl);
    notifyListeners();
  }

  /// Aplica primero el inventario y luego los estados publicados por la web.
  /// Así el estado remoto ya refleja el stock vigente y no se recalcula dos
  /// veces desde el dispositivo.
  Future<void> _pullWebCatalogState() async {
    if (!_webSyncEnabled || !isOnline) return;
    if (!useDirectFirestore && _serverUrl.isEmpty) return;
    await _flushPendingIngredientPatches();
    await pullServerIngredients();
    await pullServerCategories();
    await _flushDirtyMenuItems();
    await pullServerMenuCatalog();
    await _flushPendingMenuStatuses();
    await _flushPendingFeaturedItems();
    await pullServerMenuStatus();
  }

  void _startWebPolling() {
    _webPollTimer?.cancel();
    _webPollTimer = Timer.periodic(_pollInterval, (_) {
      if (isOnline) {
        unawaited(pullServerOrders());
        unawaited(pullServerCustomers());
        unawaited(pullServerVisits());
        unawaited(_pullWebCatalogState());
        unawaited(_flushPendingCashShiftClosures());
        unawaited(pullCashShifts());
        unawaited(_flushInventoryLosses());
        unawaited(pullInventoryLosses());
        unawaited(_flushPendingRestaurantConfig());
        unawaited(_syncRestaurantConfig());
      }
    });
    unawaited(pullServerOrders());
    unawaited(pullServerCustomers());
    unawaited(pullServerVisits());
    unawaited(_pullWebCatalogState());
    unawaited(_flushPendingCashShiftClosures());
    unawaited(pullCashShifts());
    unawaited(_flushInventoryLosses());
    unawaited(pullInventoryLosses());
    unawaited(_flushPendingRestaurantConfig());
    unawaited(_syncRestaurantConfig());
  }

  /// Prueba la conexión con la API de la web pública.
  Future<bool> testServerConnection() async {
    if (!useDirectFirestore && _serverUrl.isEmpty) return false;
    final response = await _request('GET', '/api/health', authorized: false);
    return response.ok;
  }

  /// Descarga los pedidos creados en la web y los agrega al repositorio.
  ///
  /// Devuelve cuántos pedidos nuevos se importaron. Los pedidos locales que
  /// ya existen no se sobrescriben para no perder cambios de estado hechos
  /// desde la app.
  Future<int> pullServerOrders() async {
    if (_pullingServerOrders) return 0;
    if (!useDirectFirestore && _serverUrl.isEmpty) return 0;
    _pullingServerOrders = true;
    try {
      final response = await _request('GET', '/api/orders');
      if (!response.ok) return 0;
      final decoded = jsonDecode(response.body);
      final rawList = decoded is List
          ? decoded
          : decoded is Map<String, dynamic>
          ? decoded['orders']
          : null;
      if (rawList is! List) return 0;
      final notifyChanges = _ordersPrimed;
      _ordersPrimed = true;
      final readyToNotify = <Order>[];

      final existingIds = _orders.map((order) => order.id).toSet();
      final imported = <Order>[];
      final webReconcileIds = <String>[];
      var updatedExisting = false;

      for (final raw in rawList) {
        if (raw is! Map<String, dynamic>) continue;
        var remote = Order.fromJson({
          ...raw,
          'source': 'web',
          'synced': true,
          'auditLog':
              raw['auditLog'] ??
              [
                {
                  'action': 'Pedido importado desde la web',
                  'timestamp':
                      raw['createdAt'] ?? DateTime.now().toIso8601String(),
                  'actorName': 'Web pública',
                  'detail': 'Pedido creado desde el catálogo en línea',
                },
              ],
        });
        if (remote.id.isEmpty) continue;

        if (!existingIds.contains(remote.id)) {
          existingIds.add(remote.id);
          // La web es la dueña del stock de sus pedidos. Si llega un pedido
          // heredado en estado superior sin flag, le pedimos que descuente
          // con un PATCH en vez de descontar dos veces desde la app.
          if (!remote.inventoryDeducted &&
              _isDeductibleStatus(remote.status) &&
              consumptionForOrder(remote).isNotEmpty) {
            webReconcileIds.add(remote.id);
          }
          imported.add(
            remote.copyWith(
              auditLog: remote.auditLog.isEmpty
                  ? [
                      OrderAuditEntry(
                        action: 'Pedido importado desde la web',
                        timestamp: remote.createdAt,
                        actorName: 'Web pública',
                        detail: 'Pedido creado desde el catálogo en línea',
                      ),
                    ]
                  : remote.auditLog,
            ),
          );
          continue;
        }

        final index = _orders.indexWhere((o) => o.id == remote.id);
        if (index < 0) continue;
        var local = _orders[index];
        if (local.source != 'web') continue;

        if (local.inventoryDeducted != remote.inventoryDeducted) {
          local = local.copyWith(inventoryDeducted: remote.inventoryDeducted);
          _orders[index] = local;
          updatedExisting = true;
        }
        if (!remote.inventoryDeducted &&
            _isDeductibleStatus(remote.status) &&
            consumptionForOrder(local).isNotEmpty) {
          webReconcileIds.add(remote.id);
        }

        final statusChanged =
            local.status != remote.status ||
            local.paymentStatus != remote.paymentStatus;
        if (notifyChanges &&
            local.status != OrderStatus.ready &&
            remote.status == OrderStatus.ready) {
          readyToNotify.add(remote);
        }
        // La web también puede cambiar quién cobró después de marcar el pago.
        // Sin esto, la app se queda con el cobrador genérico «Web pública».
        final payerChanged =
            (remote.paidAt != null && local.paidAt != remote.paidAt) ||
            (remote.paidBy != null && local.paidBy != remote.paidBy) ||
            (remote.paidByName != null &&
                local.paidByName != remote.paidByName);
        if (!statusChanged && !payerChanged) continue;

        final audit = [...local.auditLog];
        if (local.status != remote.status) {
          audit.add(
            OrderAuditEntry(
              action: 'Estado actualizado desde la web',
              timestamp: remote.updatedAt,
              actorName: 'Web pública',
              detail: '${local.status.label} → ${remote.status.label}',
            ),
          );
        }
        if (local.paymentStatus != remote.paymentStatus) {
          audit.add(
            OrderAuditEntry(
              action: 'Pago actualizado desde la web',
              timestamp: remote.updatedAt,
              actorName: 'Web pública',
              detail:
                  '${local.paymentStatus.label} → ${remote.paymentStatus.label}',
            ),
          );
        }
        if (payerChanged && remote.paidByName != null) {
          audit.add(
            OrderAuditEntry(
              action: 'Cobrador actualizado desde la web',
              timestamp: remote.updatedAt,
              actorName: 'Web pública',
              detail: remote.paidByName!,
            ),
          );
        }
        _orders[index] = local.copyWith(
          status: remote.status,
          paymentStatus: remote.paymentStatus,
          deliveryAddress: remote.deliveryAddress,
          paidAt: remote.paidAt ?? local.paidAt,
          paidBy: remote.paidBy ?? local.paidBy,
          paidByName: remote.paidByName ?? local.paidByName,
          updatedAt: remote.updatedAt,
          auditLog: audit,
        );
        updatedExisting = true;
      }

      if (imported.isEmpty && !updatedExisting) {
        _lastSync = DateTime.now();
        _prefs.setString(_kLastSync, _lastSync!.toIso8601String());
        return 0;
      }

      if (imported.isNotEmpty) {
        _orders = [...imported, ..._orders]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        for (final order in imported) {
          final table = order.tableNumber;
          if (table != null) {
            await _setTableForOrder(table, order.id);
          }
        }
      } else {
        _orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }

      _lastSync = DateTime.now();
      _prefs.setString(_kLastSync, _lastSync!.toIso8601String());
      await _rebuildCustomersFromOrders(persist: false);
      await _persistOrders();
      await _persistCustomers();

      // Avisos locales de respaldo cuando FCM no está disponible (modo web/QA).
      if (notifyChanges) {
        for (final order in imported) {
          unawaited(
            NotificationService.instance.showLocal(
              type: AppNotificationType.newOrder,
              tenantId: tenantId,
              title: 'Pedido nuevo ${order.code}',
              body: '${order.customerName} · \$${order.total.toStringAsFixed(0)}',
              orderId: order.id,
            ),
          );
        }
        for (final order in readyToNotify) {
          unawaited(
            NotificationService.instance.showLocal(
              type: AppNotificationType.orderReady,
              tenantId: tenantId,
              title: 'Pedido listo ${order.code}',
              body: '${order.customerName} · ${order.type.label}',
              orderId: order.id,
            ),
          );
        }
      }
      for (final id in webReconcileIds) {
        final synced = _orders.where((order) => order.id == id).toList();
        if (synced.isEmpty) continue;
        await _pushOrderUpdateToServer(synced.first);
      }
      notifyListeners();
      return imported.length;
    } catch (_) {
      return 0;
    } finally {
      _pullingServerOrders = false;
    }
  }

  Future<void> _pushOrderUpdateToServer(Order order) async {
    if (!useDirectFirestore && _serverUrl.isEmpty) return;
    final payload = <String, dynamic>{
      'status': order.status.name,
      'paymentStatus': order.paymentStatus.name,
      // En Firestore directo la APK es dueña del descuento; en modo web la web
      // decide con su valor persistido y devuelve el flag en la respuesta.
      if (useDirectFirestore) 'inventoryDeducted': order.inventoryDeducted,
      if (order.paymentStatus == PaymentStatus.paid) ...{
        'paidAt': (order.paidAt ?? order.updatedAt).toIso8601String(),
        'paidBy': order.paidBy,
        'paidByName': order.paidByName ?? order.updatedByName,
      },
      // El autor viaja con el cambio: Functions excluye sus dispositivos del
      // push para que no reciba su propia notificación.
      'lastChangedBy': order.updatedBy,
      'updatedBy': order.updatedBy,
      'updatedByName': order.updatedByName,
      // Pagos divididos y fecha de actualización (conservan datos en merge
      // parcial; `preservesIdentity` no toca code/customerName/createdAt).
      if (useDirectFirestore) ...{
        if (order.payments.isNotEmpty)
          'payments': order.payments.map((p) => p.toJson()).toList(),
        'updatedAt': order.updatedAt.toIso8601String(),
      },
    };
    final response = await _request(
      'PATCH',
      '/api/orders/${Uri.encodeComponent(order.id)}',
      body: payload,
    );
    if (response.ok && response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        final remote = decoded is Map ? decoded['order'] : null;
        final deducted = remote is Map ? remote['inventoryDeducted'] : null;
        if (deducted is bool) {
          final index = _orders.indexWhere((item) => item.id == order.id);
          if (index >= 0 &&
              _orders[index].source == 'web' &&
              _orders[index].inventoryDeducted != deducted) {
            _orders[index] = _orders[index].copyWith(
              inventoryDeducted: deducted,
            );
            await _persistOrders();
            notifyListeners();
          }
        }
      } catch (_) {
        // Una respuesta inesperada no interrumpe la sincronización.
      }
    }
  }

  Future<void> _pushCustomerToServer(CustomerRecord customer) async {
    if (!useDirectFirestore && _serverUrl.isEmpty) return;
    if (!customer.hasPhone) return;
    await _request(
      'POST',
      '/api/customers',
      body: customer.toJson(),
      query: {'id': customer.id},
    );
  }

  Future<void> pullServerCustomers() async {
    if (!useDirectFirestore && _serverUrl.isEmpty) return;
    try {
      final response = await _request('GET', '/api/customers');
      if (!response.ok) return;
      final decoded = jsonDecode(response.body);
      final rawList = decoded is Map<String, dynamic>
          ? decoded['customers']
          : null;
      if (rawList is! List) return;
      var changed = false;
      for (final raw in rawList) {
        if (raw is! Map<String, dynamic>) continue;
        final remote = CustomerRecord.fromJson(raw);
        if (!remote.hasPhone) continue;
        final idx = _customers.indexWhere(
          (c) => c.normalizedPhone == remote.normalizedPhone,
        );
        if (idx < 0) {
          _customers = [..._customers, remote];
          changed = true;
          continue;
        }
        final local = _customers[idx];
        if (remote.updatedAt.isAfter(local.updatedAt)) {
          _customers[idx] = remote.copyWith(
            tags: remote.tags.isNotEmpty ? remote.tags : local.tags,
            notes: remote.notes.isNotEmpty ? remote.notes : local.notes,
          );
          changed = true;
        }
      }
      if (changed) {
        _customers.sort((a, b) => b.lastOrderAt.compareTo(a.lastOrderAt));
        await _persistCustomers();
        notifyListeners();
      }
    } catch (_) {
      // Best-effort.
    }
  }

  /// Descarga las visitas registradas por la web pública.
  ///
  /// El feed es la fuente de verdad: se reemplaza la copia local para eliminar
  /// duplicados históricos y se deduplica por cliente/día. Los datos quedan en
  /// SharedPreferences para que el panel CRM funcione también sin conexión.
  Future<int> pullServerVisits() async {
    if (!useDirectFirestore && _serverUrl.isEmpty) return 0;
    try {
      final response = await _request('GET', '/api/visits');
      if (!response.ok) return 0;
      final decoded = jsonDecode(response.body);
      final rawList = decoded is Map<String, dynamic>
          ? decoded['visits']
          : null;
      if (rawList is! List) return 0;

      final seen = <String>{};
      final imported = <WebVisit>[];
      for (final raw in rawList) {
        if (raw is! Map<String, dynamic>) continue;
        final visit = WebVisit.fromJson(raw);
        if (visit.id.isEmpty || !seen.add(visit.dedupeKey)) continue;
        imported.add(visit);
      }

      _webVisits = imported
        ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      if (_webVisits.length > 2000) {
        _webVisits = _webVisits.take(2000).toList();
      }
      await _persistWebVisits();
      notifyListeners();
      return imported.length;
    } catch (_) {
      return 0;
    }
  }

  /// Devuelve el estado efectivo confirmado por la web, o `null` si falló.
  ///
  /// La web puede corregir un `available` a `unavailable` cuando el stock no
  /// permite preparar el plato; usar esa respuesta evita reencolar el mismo
  /// cambio en cada sondeo.
  Future<String?> _pushMenuItemStatusToServer(
    String itemId,
    String status,
    bool manual,
    String reason,
  ) async {
    if (!useDirectFirestore && _serverUrl.isEmpty) return null;
    // La web traduce `manual/reason` a `manualStatus/statusReason` antes de
    // escribir el documento. En directo aplicamos el mismo contrato para que
    // los triggers y el sondeo vean exactamente los mismos campos.
    final body = useDirectFirestore
        ? <String, dynamic>{
            'status': status,
            'manualStatus': status == 'unavailable' && manual
                ? 'unavailable'
                : null,
            'statusReason': reason,
            'statusUpdatedAt': DateTime.now().toIso8601String(),
          }
        : <String, dynamic>{
            'status': status,
            'manual': manual,
            'reason': reason,
          };
    final response = await _request(
      'PATCH',
      '/api/menu/${Uri.encodeComponent(itemId)}',
      body: body,
    );
    if (!response.ok) return null;
    try {
      final decoded = jsonDecode(response.body);
      final item = decoded is Map<String, dynamic> ? decoded['item'] : null;
      final effective = item is Map<String, dynamic> ? item['status'] : null;
      return effective is String && effective.isNotEmpty ? effective : status;
    } catch (_) {
      return status;
    }
  }

  /// Publica el campo «Favorito» usado por el carrusel de la web.
  Future<bool> _pushMenuItemFeaturedToServer(
    String itemId,
    bool featured,
  ) async {
    if (!useDirectFirestore && _serverUrl.isEmpty) return false;
    final response = await _request(
      'PATCH',
      '/api/menu/${Uri.encodeComponent(itemId)}',
      body: {'featured': featured},
    );
    return response.ok;
  }

  Future<void> _flushPendingFeaturedItems() async {
    if (!_webSyncEnabled || !isOnline || _pendingFeaturedItems.isEmpty) return;
    if (!_serverMenuCatalogLoaded) return;
    final snapshot = Map<String, bool>.from(_pendingFeaturedItems);
    for (final entry in snapshot.entries) {
      if (!_serverMenuCatalogIds.contains(entry.key)) continue;
      final ok = await _pushMenuItemFeaturedToServer(entry.key, entry.value);
      if (!ok) continue;
      if (_pendingFeaturedItems[entry.key] != entry.value) continue;
      _pendingFeaturedItems.remove(entry.key);
      await _persistPendingFeaturedItems();
    }
  }

  /// Envía a la web los cambios de disponibilidad hechos sin conexión.
  Future<void> _flushPendingMenuStatuses() async {
    if (!_webSyncEnabled || !isOnline || _flushingMenuStatuses) return;
    if (_pendingMenuStatuses.isEmpty) return;
    // Nunca crear documentos nuevos solo con el estado: un plato local que no
    // existe en Firestore se queda sin publicar hasta que su catálogo exista.
    if (!_serverMenuCatalogLoaded) return;
    _flushingMenuStatuses = true;
    try {
      final snapshot = Map<String, Map<String, dynamic>>.from(
        _pendingMenuStatuses,
      );
      var localChanges = 0;
      for (final entry in snapshot.entries) {
        if (!_serverMenuCatalogIds.contains(entry.key)) {
          if (_pendingMenuStatuses[entry.key] == entry.value) {
            _pendingMenuStatuses.remove(entry.key);
            await _persistPendingMenuStatuses();
          }
          continue;
        }
        final status = entry.value['status'] as String? ?? '';
        final manual =
            entry.value['manual'] as bool? ?? status == 'unavailable';
        final reason = entry.value['reason'] as String? ?? 'manual';
        final effective = await _pushMenuItemStatusToServer(
          entry.key,
          status,
          manual,
          reason,
        );
        if (effective == null) continue;
        // Solo limpiar si la cola sigue siendo la misma que se envió; un cambio
        // local posterior debe conservarse para el siguiente intento.
        if (_pendingMenuStatuses[entry.key] != entry.value) continue;
        _pendingMenuStatuses.remove(entry.key);
        await _persistPendingMenuStatuses();

        // La web puede corregir el estado por stock. Adoptar ese resultado
        // evita reenviar indefinidamente un cambio que ya fue reconciliado y
        // evita que `statusUpdatedAt` se reescriba en cada sondeo.
        final index = _items.indexWhere((item) => item.id == entry.key);
        if (index < 0) continue;
        final effectiveStatus = MenuItemStatus.fromName(effective);
        final effectiveManual =
            effective == 'unavailable' && manual && reason == 'manual';
        if (_items[index].status == effectiveStatus &&
            _items[index].manualUnavailable == effectiveManual) {
          continue;
        }
        _items[index] = _items[index].copyWith(
          status: effectiveStatus,
          manualUnavailable: effectiveManual,
        );
        localChanges++;
      }
      if (localChanges > 0) {
        await _persistItems();
        notifyListeners();
      }
    } finally {
      _flushingMenuStatuses = false;
    }
  }

  /// Reemplaza el catálogo local por el publicado en Firestore.
  ///
  /// `/api/menu` devuelve el menú normalizado en modo web y los documentos
  /// `menuItems` en modo directo; ambos tienen los campos de `MenuItem`. Los
  /// toggles pendientes se conservan para no perder cambios sin conexión.
  Future<int> pullServerMenuCatalog() async {
    if (!_webSyncEnabled || !isOnline) return 0;
    if (!useDirectFirestore && _serverUrl.isEmpty) return 0;
    final response = await _request('GET', '/api/menu');
    if (!response.ok) return 0;
    final decoded = jsonDecode(response.body);
    final rawList = decoded is List
        ? decoded
        : decoded is Map<String, dynamic>
        ? decoded['items']
        : null;
    _serverMenuCatalogIds = rawList is List
        ? rawList
              .whereType<Map<String, dynamic>>()
              .map((raw) => raw['id'] as String?)
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toSet()
        : <String>{};
    _serverMenuCatalogLoaded = true;
    if (rawList is! List || rawList.isEmpty) return 0;

    final next = <MenuItem>[];
    for (final raw in rawList) {
      if (raw is! Map<String, dynamic>) continue;
      final id = raw['id'] as String?;
      if (id == null || id.isEmpty) continue;
      final localIndex = _items.indexWhere((item) => item.id == id);
      final local = localIndex >= 0 ? _items[localIndex] : null;
      final json = Map<String, dynamic>.from(raw)
        ..['manualUnavailable'] =
            raw['manualUnavailable'] == true ||
            raw['manualStatus'] == 'unavailable';
      var item = MenuItem.fromJson(json);
      if (local != null && _dirtyMenuItemIds.contains(id)) {
        // Edición local pendiente de subir: no la pisamos con el servidor.
        next.add(local);
        continue;
      }
      if (local != null && _pendingMenuStatuses.containsKey(id)) {
        item = item.copyWith(
          status: local.status,
          manualUnavailable: local.manualUnavailable,
        );
      }
      if (local != null && _pendingFeaturedItems.containsKey(id)) {
        item = item.copyWith(featured: local.featured);
      }
      next.add(item);
    }
    if (next.isEmpty) return 0;

    if (listEquals(
      _items.map((item) => item.toJson()).toList(),
      next.map((item) => item.toJson()).toList(),
    )) {
      return 0;
    }
    _items = next;
    await _persistItems();
    notifyListeners();
    return next.length;
  }

  /// Carga las categorías reales cuando la APK habla directamente con
  /// Firestore. En modo web `/api/menu` ya las trae consigo.
  Future<int> pullServerCategories() async {
    if (!useDirectFirestore || !_webSyncEnabled || !isOnline) return 0;
    final response = await _request('GET', '/api/menu/categories');
    if (!response.ok) return 0;
    final decoded = jsonDecode(response.body);
    final rawList = decoded is Map<String, dynamic>
        ? decoded['categories']
        : null;
    if (rawList is! List || rawList.isEmpty) return 0;
    final next =
        rawList
            .whereType<Map<String, dynamic>>()
            .map(Category.fromJson)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    if (next.isEmpty) return 0;
    if (listEquals(
      _categories.map((category) => category.toJson()).toList(),
      next.map((category) => category.toJson()).toList(),
    )) {
      return 0;
    }
    _categories = next;
    await _persistCategories();
    notifyListeners();
    return next.length;
  }

  /// Reconcilia la disponibilidad local con el catálogo publicado por la web.
  ///
  /// Los cambios pendientes de envío tienen prioridad para no sobrescribir un
  /// toggle offline que todavía no llegó a Firestore.
  Future<int> pullServerMenuStatus() async {
    if (!_webSyncEnabled || _pullingServerMenuStatuses) return 0;
    if (!useDirectFirestore && _serverUrl.isEmpty) return 0;
    _pullingServerMenuStatuses = true;
    try {
      final response = await _request('GET', '/api/menu/status');
      if (!response.ok) return 0;
      final decoded = jsonDecode(response.body);
      final rawList = decoded is Map<String, dynamic> ? decoded['items'] : null;
      if (rawList is! List) return 0;

      var changes = 0;
      for (final raw in rawList) {
        if (raw is! Map<String, dynamic>) continue;
        final id = raw['id'] as String?;
        final status = raw['status'] as String?;
        if (id == null || id.isEmpty || status == null) continue;
        if (_pendingMenuStatuses.containsKey(id)) continue;
        final index = _items.indexWhere((item) => item.id == id);
        if (index < 0) continue;
        final remoteStatus = MenuItemStatus.fromName(status);
        final manualUnavailable = raw['manualStatus'] == 'unavailable';
        if (_items[index].status == remoteStatus &&
            _items[index].manualUnavailable == manualUnavailable) {
          continue;
        }
        _items[index] = _items[index].copyWith(
          status: remoteStatus,
          manualUnavailable: manualUnavailable,
        );
        changes++;
      }
      // El estado remoto ya incluye los ajustes por stock (web/Functions).
      // Recalcularlo aquí sobrescribiría la corrección del servidor y volvería
      // a encolar el mismo cambio en cada sondeo.
      if (changes > 0) {
        await _persistItems();
        notifyListeners();
      }
      return changes;
    } catch (_) {
      return 0;
    } finally {
      _pullingServerMenuStatuses = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Sincronización de inventario con la web / Firestore
  // ---------------------------------------------------------------------------

  void _queueIngredientPatch(Ingredient ingredient) {
    _pendingIngredientStocks[ingredient.id] = {
      'name': ingredient.name,
      'unit': ingredient.unit.symbol,
      'stock': ingredient.stock,
      'minStock': ingredient.minStock,
      // Functions excluye al autor del aviso de stock bajo / sin stock.
      'updatedBy': _currentUser?.id,
    };
    unawaited(_persistPendingIngredientStocks());
    if (_webSyncEnabled) unawaited(_flushPendingIngredientPatches());
  }

  Future<bool> _pushIngredientPatchToServer(
    String ingredientId,
    Map<String, dynamic> patch,
  ) async {
    if (!useDirectFirestore && _serverUrl.isEmpty) return false;
    final response = await _request(
      'PATCH',
      '/api/ingredients/${Uri.encodeComponent(ingredientId)}',
      body: patch,
    );
    return response.ok;
  }

  Future<bool> _deleteIngredientOnServer(String ingredientId) async {
    if (!useDirectFirestore && _serverUrl.isEmpty) return false;
    final response = await _request(
      'DELETE',
      '/api/ingredients/${Uri.encodeComponent(ingredientId)}',
    );
    return response.ok;
  }

  Future<void> _flushPendingIngredientPatches() async {
    if (!_webSyncEnabled || !isOnline || _flushingIngredientStocks) return;
    if (_pendingIngredientStocks.isEmpty) return;
    _flushingIngredientStocks = true;
    try {
      final snapshot = Map<String, Map<String, dynamic>>.from(
        _pendingIngredientStocks,
      );
      for (final entry in snapshot.entries) {
        final sent = await _pushIngredientPatchToServer(entry.key, entry.value);
        if (sent &&
            mapEquals(_pendingIngredientStocks[entry.key], entry.value)) {
          _pendingIngredientStocks.remove(entry.key);
          await _persistPendingIngredientStocks();
        }
      }
    } finally {
      _flushingIngredientStocks = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Pérdidas / caducidades de ingredientes (admin y cocinero)
  // ---------------------------------------------------------------------------

  /// Historial local, ordenado del más reciente al más antiguo.
  List<InventoryLoss> get inventoryLosses =>
      List.unmodifiable(_inventoryLosses);

  List<InventoryLoss> get pendingInventoryLosses =>
      _inventoryLosses.where((loss) => !loss.synced).toList();

  bool get hasPendingInventoryLosses =>
      _inventoryLosses.any((loss) => !loss.synced);

  /// Permite al historial forzar el envío de la cola sin esperar al sondeo.
  Future<void> flushInventoryLosses() => _flushInventoryLosses();

  /// Registra la pérdida en el dispositivo, descuenta el stock local y encola
  /// el PATCH de inventario. El POST a la web es solo la auditoría: el stock
  /// ya se envió con [_queueIngredientPatch], así no se descuenta dos veces.
  Future<InventoryLoss> registerInventoryLoss({
    required LossReason reason,
    required List<LossLine> lines,
    String notes = '',
    String? photoPath,
  }) async {
    final userRole = role;
    if (userRole == null || !userRole.canRegisterInventoryLoss) {
      throw StateError(
        'Solo administradores y cocineros pueden registrar pérdidas.',
      );
    }
    if (lines.isEmpty) {
      throw ArgumentError('Agrega al menos un ingrediente.');
    }
    for (final line in lines) {
      if (line.ingredientId.isEmpty || line.name.trim().isEmpty) {
        throw ArgumentError('Cada línea necesita un ingrediente.');
      }
      if (!line.quantity.isFinite || line.quantity <= 0) {
        throw ArgumentError('La cantidad debe ser mayor a cero.');
      }
    }

    final now = DateTime.now();
    final loss = InventoryLoss(
      id: newId('loss'),
      reason: reason,
      lines: lines
          .map(
            (line) => line.copyWith(
              name: line.name.trim(),
              unit: ingredientById(line.ingredientId)?.unit.symbol ?? line.unit,
            ),
          )
          .toList(),
      notes: notes.trim(),
      photoPath: photoPath,
      createdAt: now,
      createdById: _currentUser?.id ?? '',
      createdByName: _currentUser?.name ?? '',
      createdByRole: userRole.name,
      auditLog: [
        LossAuditEntry(
          action: 'Pérdida registrada',
          timestamp: now,
          actorId: _currentUser?.id ?? '',
          actorName: _currentUser?.name ?? '',
          actorRole: userRole.name,
        ),
      ],
    );

    _inventoryLosses.insert(0, loss);
    // Deducción offline: nunca por debajo de cero y con la misma cola que ya
    // usa el inventario, para que la web reciba el stock definitivo.
    for (final line in loss.lines) {
      final ingredient = ingredientById(line.ingredientId);
      if (ingredient == null) continue;
      final nextStock = line.quantity >= ingredient.stock
          ? 0.0
          : ingredient.stock - line.quantity;
      await upsertIngredient(ingredient.copyWith(stock: nextStock));
    }

    await _persistInventoryLosses();
    notifyListeners();
    if (_webSyncEnabled && isOnline) unawaited(_flushInventoryLosses());
    return loss;
  }

  Future<int> _pushInventoryLossToServer(InventoryLoss loss) async {
    if (!useDirectFirestore && _serverUrl.isEmpty) return 0;
    final response = await _request(
      'POST',
      '/api/inventory-losses',
      body: loss.toWebJson(),
      query: {'id': loss.id},
    );
    return response.statusCode;
  }

  /// Sube la foto (si está pendiente) y envía la auditoría. Un error de red o
  /// de Storage conserva el registro en la cola para el siguiente intento.
  Future<void> _flushInventoryLosses() async {
    if (_flushingInventoryLosses || !_webSyncEnabled || !isOnline) return;
    final pending = pendingInventoryLosses;
    if (pending.isEmpty) return;
    _flushingInventoryLosses = true;
    try {
      try {
        await _authService.getIdToken();
      } on AuthException {
        _markNeedsFirebaseReLogin();
        return;
      }

      for (final candidate in pending) {
        final index = _inventoryLosses.indexWhere((l) => l.id == candidate.id);
        if (index < 0) continue;
        var loss = _inventoryLosses[index];
        if (loss.synced) continue;

        String? photoUrl = loss.photoUrl;
        final localPath = loss.photoPath;
        if (photoUrl == null && localPath != null && localPath.isNotEmpty) {
          try {
            final mime = MediaUploadService.mimeTypeFromPath(localPath);
            final extension = mime.isEmpty ? 'jpg' : mime.split('/').last;
            final fileName = extension == 'jpeg' ? 'jpg' : extension;
            final service = MediaUploadService(authService: _authService);
            photoUrl = await service.uploadFile(
              filePath: localPath,
              objectName:
                  'tenants/$tenantId/inventory-losses/${loss.id}-${DateTime.now().millisecondsSinceEpoch}.$fileName',
              maxBytes: 6 * 1024 * 1024,
            );
          } catch (_) {
            // Sin foto subida no se envía la pérdida: se reintenta en conjunto.
            continue;
          }
        }

        final payload = loss.copyWith(photoUrl: photoUrl);
        final status = await _pushInventoryLossToServer(payload);
        // Un 403 no marca re-login: es falta de permiso, no sesión.
        if (status == 401) {
          _markNeedsFirebaseReLogin();
          return;
        }
        if (status < 200 || status >= 300) continue;

        _inventoryLosses[index] = payload.copyWith(
          synced: true,
          clearPhotoPath: true,
          auditLog: [
            ...payload.auditLog,
            LossAuditEntry(
              action: 'Sincronizado con la web',
              timestamp: DateTime.now(),
              actorId: _currentUser?.id ?? '',
              actorName: _currentUser?.name ?? '',
              actorRole: _currentUser?.role.name ?? '',
            ),
          ],
        );
        await _persistInventoryLosses();
        notifyListeners();
      }
    } finally {
      _flushingInventoryLosses = false;
    }
  }

  /// Reconcilia el historial con Firestore. Las pérdidas locales pendientes
  /// ganan para no perder auditoría hecha sin conexión.
  Future<bool> pullInventoryLosses() async {
    if (_pullingInventoryLosses || !_webSyncEnabled || !isOnline) {
      return false;
    }
    if (!useDirectFirestore && _serverUrl.isEmpty) return false;
    _pullingInventoryLosses = true;
    try {
      final response = await _request('GET', '/api/inventory-losses');
      if (!response.ok) return false;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return false;
      final rawLosses = decoded['losses'];
      if (rawLosses is! List<dynamic>) return false;
      final remote = rawLosses
          .whereType<Map<String, dynamic>>()
          .map(InventoryLoss.fromWebJson)
          .toList();
      final pending = _inventoryLosses.where((loss) => !loss.synced).toList();
      final pendingIds = pending.map((loss) => loss.id).toSet();
      final merged = [
        ...pending,
        ...remote.where(
          (loss) => loss.id.isNotEmpty && !pendingIds.contains(loss.id),
        ),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final changed =
          merged.length != _inventoryLosses.length ||
          _inventoryLosses.asMap().entries.any(
            (entry) =>
                entry.key >= merged.length || entry.value != merged[entry.key],
          );
      if (!changed) return false;
      _inventoryLosses = merged;
      await _persistInventoryLosses();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    } finally {
      _pullingInventoryLosses = false;
    }
  }

  /// Porciones preparables con el stock local; null si no hay receta o si
  /// faltan datos de inventario. Es la única fuente de verdad para decidir si
  /// un plato está agotado por insumos (etiqueta y estado)
  int? _preparableServings(MenuItem item) {
    if (item.recipe.isEmpty) return null;
    int? max;
    for (final line in item.recipe) {
      if (line.quantity <= 0) continue;
      final ingredient = ingredientById(line.ingredientId);
      // Insumo de la receta sin documento = agotado, nunca ilimitado.
      final stock = ingredient?.stock ?? 0;
      final servings = stock <= 0 ? 0 : (stock / line.quantity).floor();
      max = max == null ? servings : (servings < max ? servings : max);
    }
    return max;
  }

  /// Estado derivado del stock local, respetando los bloqueos manuales.
  ///
  /// Los cambios automáticos se encolan hacia la web con
  /// `reason: 'ingredients'` para que Firestore termine con el mismo estado;
  /// un toggle manual pendiente nunca se sobrescribe aquí.
  int _recomputeMenuStatuses() {
    var changes = 0;
    var queued = 0;
    for (var index = 0; index < _items.length; index++) {
      final item = _items[index];
      MenuItemStatus next;
      if (item.manualUnavailable) {
        next = MenuItemStatus.unavailable;
      } else {
        next = _preparableServings(item) == 0
            ? MenuItemStatus.unavailable
            : MenuItemStatus.available;
      }
      if (item.status == next) continue;
      _items[index] = item.copyWith(status: next);
      changes++;
      if (!item.manualUnavailable &&
          _pendingMenuStatuses[item.id]?['manual'] != true) {
        _pendingMenuStatuses[item.id] = {
          'status': next.name,
          'manual': false,
          'reason': 'ingredients',
        };
        queued++;
      }
    }
    if (queued > 0) {
      unawaited(_persistPendingMenuStatuses());
      if (_webSyncEnabled) unawaited(_flushPendingMenuStatuses());
    }
    return changes;
  }

  /// Descarga el inventario compartido. Los cambios locales pendientes tienen
  /// prioridad para no perder ajustes hechos sin conexión.
  Future<int> pullServerIngredients() async {
    if (!_webSyncEnabled || _pullingServerIngredients) return 0;
    if (!useDirectFirestore && _serverUrl.isEmpty) return 0;
    _pullingServerIngredients = true;
    try {
      final response = await _request('GET', '/api/ingredients');
      if (!response.ok) return 0;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['configured'] == false) {
        return 0;
      }
      final rawList = decoded['ingredients'];
      if (rawList is! List) return 0;
      final notifyChanges = _ingredientsPrimed;
      _ingredientsPrimed = true;
      final wasLow = <String>{
        for (final ingredient in _ingredients.where((item) => item.isLow))
          ingredient.id,
      };
      final wasOut = <String>{
        for (final ingredient in _ingredients.where((item) => item.stock <= 0))
          ingredient.id,
      };

      final remote = <Ingredient>[];
      for (final raw in rawList) {
        if (raw is! Map<String, dynamic>) continue;
        final id = raw['id'] as String?;
        final stock = (raw['stock'] as num?)?.toDouble();
        if (id == null || id.isEmpty || stock == null) continue;
        remote.add(
          Ingredient(
            id: id,
            name: raw['name'] as String? ?? id,
            unit: IngredientUnit.fromSymbol(raw['unit'] as String?),
            stock: stock,
            minStock: (raw['minStock'] as num?)?.toDouble() ?? 0,
          ),
        );
      }

      final merged = mergeServerIngredients(
        _ingredients,
        remote,
        _pendingIngredientStocks.keys.toSet(),
      );
      bool same(Ingredient a, Ingredient b) =>
          a.id == b.id &&
          a.name == b.name &&
          a.unit == b.unit &&
          a.stock == b.stock &&
          a.minStock == b.minStock;
      var changes = merged.length != _ingredients.length ? 1 : 0;
      for (var index = 0; index < merged.length && changes == 0; index++) {
        if (!same(_ingredients[index], merged[index])) changes = 1;
      }
      if (changes > 0) _ingredients = merged;

      final statusChanges = _recomputeMenuStatuses();
      if (changes > 0) await _persistIngredients();
      if (statusChanges > 0) await _persistItems();
      if (changes > 0 || statusChanges > 0) notifyListeners();
      if (notifyChanges) {
        // El agotamiento manda: no duplicamos el aviso de stock bajo del mismo
        // cambio. Un cruce posterior de stock bajo sí se avisa por separado.
        for (final ingredient in merged.where((item) => item.stock <= 0)) {
          if (wasOut.contains(ingredient.id)) continue;
          unawaited(
            NotificationService.instance.showLocal(
              type: AppNotificationType.outOfStock,
              tenantId: tenantId,
              title: 'Sin stock: ${ingredient.name}',
              body: 'Agotado · mínimo ${ingredient.minStockLabel}',
              orderId: ingredient.id,
            ),
          );
        }
        for (final ingredient
            in merged.where((item) => item.isLow && item.stock > 0)) {
          if (wasLow.contains(ingredient.id)) continue;
          unawaited(
            NotificationService.instance.showLocal(
              type: AppNotificationType.lowStock,
              tenantId: tenantId,
              title: 'Stock bajo: ${ingredient.name}',
              body:
                  'Quedan ${ingredient.stockLabel} · mínimo '
                  '${ingredient.minStockLabel}',
              orderId: ingredient.id,
            ),
          );
        }
      }
      return changes;
    } catch (_) {
      return 0;
    } finally {
      _pullingServerIngredients = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Inventario
  // ---------------------------------------------------------------------------

  List<Ingredient> get ingredients => List.unmodifiable(_ingredients);

  List<Ingredient> get lowStockIngredients =>
      _ingredients.where((ingredient) => ingredient.isLow).toList()
        ..sort((a, b) => a.stock.compareTo(b.stock));

  Ingredient? ingredientById(String id) {
    final matches = _ingredients.where((ingredient) => ingredient.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  Future<Ingredient> addIngredient({
    required String name,
    required IngredientUnit unit,
    required double stock,
    required double minStock,
    double cost = 0,
  }) async {
    final ingredient = Ingredient(
      id: newId('ing'),
      name: name.trim(),
      unit: unit,
      stock: stock,
      minStock: minStock,
      cost: cost,
    );
    _ingredients.add(ingredient);
    _queueIngredientPatch(ingredient);
    final statusChanges = _recomputeMenuStatuses();
    await _persistIngredients();
    if (statusChanges > 0) await _persistItems();
    notifyListeners();
    return ingredient;
  }

  Future<void> upsertIngredient(Ingredient ingredient) async {
    final index = _ingredients.indexWhere((entry) => entry.id == ingredient.id);
    if (index >= 0) {
      _ingredients[index] = ingredient;
    } else {
      _ingredients.add(ingredient);
    }
    _queueIngredientPatch(ingredient);
    final statusChanges = _recomputeMenuStatuses();
    await _persistIngredients();
    if (statusChanges > 0) await _persistItems();
    notifyListeners();
  }

  Future<void> deleteIngredient(String ingredientId) async {
    _ingredients.removeWhere((ingredient) => ingredient.id == ingredientId);
    _items = _items
        .map(
          (item) => item.copyWith(
            recipe: item.recipe
                .where((line) => line.ingredientId != ingredientId)
                .toList(),
          ),
        )
        .toList();
    _pendingIngredientStocks.remove(ingredientId);
    await _persistPendingIngredientStocks();
    if (_webSyncEnabled) unawaited(_deleteIngredientOnServer(ingredientId));
    final statusChanges = _recomputeMenuStatuses();
    await _persistIngredients();
    if (statusChanges > 0) await _persistItems();
    notifyListeners();
  }

  Future<void> adjustIngredientStock(String ingredientId, double delta) async {
    final index = _ingredients.indexWhere(
      (ingredient) => ingredient.id == ingredientId,
    );
    if (index < 0) return;
    final ingredient = _ingredients[index];
    final next = ingredient.stock + delta;
    final clamped = next < 0 ? 0.0 : next;
    _ingredients[index] = ingredient.copyWith(stock: clamped);
    _queueIngredientPatch(_ingredients[index]);
    final statusChanges = _recomputeMenuStatuses();
    await _persistIngredients();
    if (statusChanges > 0) await _persistItems();
    notifyListeners();
  }

  /// Insumos que consume un pedido completo (receta × cantidad).
  Map<String, double> consumptionForOrder(Order order) {
    final result = <String, double>{};
    for (final orderItem in order.items) {
      final menuItem = menuItemById(orderItem.menuItemId);
      if (menuItem == null || menuItem.recipe.isEmpty) continue;
      for (final line in menuItem.recipe) {
        final amount = line.quantity * orderItem.quantity;
        result[line.ingredientId] = (result[line.ingredientId] ?? 0) + amount;
      }
    }
    return result;
  }

  Map<String, double> _consumptionForCart(List<CartLine> lines) {
    final result = <String, double>{};
    for (final cartLine in lines) {
      final menuItem = menuItemById(cartLine.menuItemId);
      if (menuItem == null || menuItem.recipe.isEmpty) continue;
      for (final line in menuItem.recipe) {
        final amount = line.quantity * cartLine.quantity;
        result[line.ingredientId] = (result[line.ingredientId] ?? 0) + amount;
      }
    }
    return result;
  }

  /// Cuántas porciones adicionales de [menuItemId] se pueden preparar
  /// considerando el stock actual y lo ya reservado en [cart].
  int availableAdditionalServings(String menuItemId, List<CartLine> cart) {
    final menuItem = menuItemById(menuItemId);
    if (menuItem == null) return 0;
    if (!menuItem.isAvailable) return 0;
    if (menuItem.recipe.isEmpty) return 99;

    final reserved = _consumptionForCart(cart);
    var maxAdditional = 1 << 30;
    for (final line in menuItem.recipe) {
      final ingredient = ingredientById(line.ingredientId);
      if (line.quantity <= 0) continue;
      final alreadyReserved = reserved[line.ingredientId] ?? 0;
      final available = (ingredient?.stock ?? 0) - alreadyReserved;
      final canMake = available <= 0 ? 0 : (available / line.quantity).floor();
      if (canMake < maxAdditional) maxAdditional = canMake;
    }
    if (maxAdditional == 1 << 30) return 99;
    return maxAdditional < 0 ? 0 : maxAdditional;
  }

  void _validateCartStock(List<CartLine> lines) {
    final consumption = _consumptionForCart(lines);
    for (final entry in consumption.entries) {
      final ingredient = ingredientById(entry.key);
      final stock = ingredient?.stock ?? 0;
      if (entry.value > stock + 0.0001) {
        final name = ingredient?.name ?? entry.key;
        throw ArgumentError(
          'No hay suficiente "$name" en inventario para preparar la cantidad solicitada.',
        );
      }
    }
  }

  /// Los pedidos locales descuentan al crearse en Pendiente (createOrder), así
  /// que las transiciones a Pendiente no vuelven a descontar. Cancelado nunca
  /// descuenta y los estados superiores sí cuando el pedido aún no descontó.
  bool _isDeductibleStatus(OrderStatus status) =>
      status != OrderStatus.pending && status != OrderStatus.cancelled;

  Future<bool> _deductInventory(Order order) async {
    final consumption = consumptionForOrder(order);
    if (consumption.isEmpty) return false;
    var changed = false;
    for (final entry in consumption.entries) {
      final index = _ingredients.indexWhere(
        (ingredient) => ingredient.id == entry.key,
      );
      if (index < 0) continue;
      final ingredient = _ingredients[index];
      final next = ingredient.stock - entry.value;
      _ingredients[index] = ingredient.copyWith(stock: next < 0 ? 0 : next);
      _queueIngredientPatch(_ingredients[index]);
      changed = true;
    }
    final statusChanges = _recomputeMenuStatuses();
    await _persistIngredients();
    if (statusChanges > 0) await _persistItems();
    return changed;
  }

  Future<void> _restoreInventory(Order order) async {
    final consumption = consumptionForOrder(order);
    if (consumption.isEmpty) return;
    for (final entry in consumption.entries) {
      final index = _ingredients.indexWhere(
        (ingredient) => ingredient.id == entry.key,
      );
      if (index < 0) continue;
      final ingredient = _ingredients[index];
      final next = ingredient.stock + entry.value;
      _ingredients[index] = ingredient.copyWith(stock: next);
      _queueIngredientPatch(_ingredients[index]);
    }
    final statusChanges = _recomputeMenuStatuses();
    await _persistIngredients();
    if (statusChanges > 0) await _persistItems();
  }

  // ---------------------------------------------------------------------------
  // Menú
  // ---------------------------------------------------------------------------

  List<Category> get categories =>
      [..._categories]..sort((a, b) => a.order.compareTo(b.order));

  List<MenuItem> get menuItems => List.unmodifiable(_items);

  /// Cambios de disponibilidad esperando a llegar a Firestore (diagnóstico/QA).
  Map<String, Map<String, dynamic>> get pendingMenuStatuses =>
      Map.unmodifiable(_pendingMenuStatuses);

  bool isMenuItemOutOfStockByIngredients(MenuItem item) =>
      _preparableServings(item) == 0;

  /// Insumos de [item] que no alcanzan para una porción. Es la explicación
  /// de `isMenuItemOutOfStockByIngredients` y usa el mismo criterio que
  /// `_preparableServings`: stock menor que la cantidad de la receta.
  List<IngredientShortage> outOfStockIngredientsFor(MenuItem item) {
    final shortages = <IngredientShortage>[];
    for (final line in item.recipe) {
      if (line.quantity <= 0) continue;
      final ingredient = ingredientById(line.ingredientId);
      if (ingredient == null) continue;
      if (ingredient.stock + 0.0001 >= line.quantity) continue;
      shortages.add(
        IngredientShortage(ingredient: ingredient, required: line.quantity),
      );
    }
    return shortages;
  }

  bool isMenuItemEffectivelyAvailable(MenuItem item) =>
      item.isAvailable && !isMenuItemOutOfStockByIngredients(item);

  List<MenuItem> get availableMenuItems =>
      _items.where(isMenuItemEffectivelyAvailable).toList();

  MenuItem? menuItemById(String id) {
    final matches = _items.where((item) => item.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  List<MenuItem> itemsForCategory(String categoryId) =>
      _items.where((item) => item.categoryId == categoryId).toList();

  Category? categoryById(String id) {
    final matches = _categories.where((category) => category.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  Future<void> upsertMenuItem(MenuItem item) async {
    final index = _items.indexWhere((entry) => entry.id == item.id);
    if (index >= 0) {
      _items[index] = item;
    } else {
      _items.add(item);
    }
    _dirtyMenuItemIds.add(item.id);
    await _persistItems();
    await _persistDirtyMenuItemIds();
    notifyListeners();
    await _pushMenuItemToServer(item);
  }

  Future<void> _pushMenuItemToServer(MenuItem item) async {
    if (!_webSyncEnabled || !isOnline) return;
    if (!useDirectFirestore && _serverUrl.isEmpty) return;
    try {
      final response = await _request(
        'PATCH',
        '/api/menu/${Uri.encodeComponent(item.id)}',
        body: item.toJson(),
      );
      if (response.ok) {
        _dirtyMenuItemIds.remove(item.id);
        await _persistDirtyMenuItemIds();
      }
    } catch (_) {
      // El cambio queda local; el próximo pull/sync puede reintentar.
    }
  }

  Future<void> _flushDirtyMenuItems() async {
    if (_dirtyMenuItemIds.isEmpty || !_webSyncEnabled || !isOnline) return;
    if (!useDirectFirestore && _serverUrl.isEmpty) return;
    final ids = _dirtyMenuItemIds.toList();
    for (final id in ids) {
      final index = _items.indexWhere((item) => item.id == id);
      if (index < 0) {
        _dirtyMenuItemIds.remove(id);
        continue;
      }
      await _pushMenuItemToServer(_items[index]);
    }
    await _persistDirtyMenuItemIds();
  }

  Future<MenuItem> addMenuItem({
    required String name,
    required String description,
    required double price,
    required String categoryId,
    String emoji = '🍽️',
  }) async {
    final category = categoryById(categoryId);
    final item = MenuItem(
      id: newId('item'),
      name: name.trim(),
      slug: _slugify(name),
      description: description.trim(),
      price: price,
      categoryId: categoryId,
      categorySlug: category?.slug ?? 'otros',
      status: MenuItemStatus.available,
      ingredients: const [],
      allergens: const [],
      emoji: emoji,
      featured: false,
      prepMinutes: 15,
      calories: 0,
    );
    _items.add(item);
    await _persistItems();
    notifyListeners();
    return item;
  }

  Future<void> toggleAvailability(String itemId) async {
    final index = _items.indexWhere((item) => item.id == itemId);
    if (index < 0) return;
    final item = _items[index];
    final goingManual = item.status != MenuItemStatus.unavailable;
    _items[index] = item.copyWith(
      status: goingManual
          ? MenuItemStatus.unavailable
          : MenuItemStatus.available,
      manualUnavailable: goingManual,
    );
    if (!goingManual) _recomputeMenuStatuses();
    final finalStatus = _items[index].status;
    await _persistItems();

    // La web pública lee Firestore: el toggle debe llegar al catálogo
    // compartido, con cola local para cambios hechos offline. El bloqueo
    // manual viaja junto al estado para que el trigger de stock lo respete.
    _pendingMenuStatuses[itemId] = {
      'status': finalStatus.name,
      'manual': goingManual,
      'reason': 'manual',
    };
    await _persistPendingMenuStatuses();
    notifyListeners();
    if (_webSyncEnabled) unawaited(_flushPendingMenuStatuses());
  }

  /// Marca/desmarca un plato como Favorito y lo encola si no hay conexión.
  Future<void> toggleFavorite(String itemId) async {
    final index = _items.indexWhere((item) => item.id == itemId);
    if (index < 0) return;
    final next = !_items[index].featured;
    _items[index] = _items[index].copyWith(featured: next);
    await _persistItems();
    _pendingFeaturedItems[itemId] = next;
    await _persistPendingFeaturedItems();
    notifyListeners();
    if (_webSyncEnabled) unawaited(_flushPendingFeaturedItems());
  }

  Future<void> deleteMenuItem(String itemId) async {
    _items.removeWhere((item) => item.id == itemId);
    await _persistItems();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Pedidos
  // ---------------------------------------------------------------------------

  List<Order> get orders => List.unmodifiable(_orders);

  List<Order> get activeOrders =>
      _orders.where((order) => order.status.isActive).toList();

  /// Pedidos pendientes por cobrar (no cancelados).
  List<Order> get ordersToCollect => _orders
      .where(
        (order) =>
            order.paymentStatus == PaymentStatus.pending &&
            order.status != OrderStatus.cancelled,
      )
      .toList();

  Order? orderById(String id) {
    final matches = _orders.where((order) => order.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  Future<Order> createOrder({
    required List<CartLine> lines,
    String customerName = '',
    String customerPhone = '',
    String deliveryAddress = '',
    required OrderType type,
    int? tableNumber,
    PaymentMethod paymentMethod = PaymentMethod.cash,
    String notes = '',
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('El pedido necesita al menos un producto.');
    }
    final trimmedName = customerName.trim();
    final trimmedPhone = customerPhone.trim();
    final trimmedAddress = deliveryAddress.trim();
    if (type == OrderType.table) {
      if (tableNumber == null) {
        throw ArgumentError('Selecciona la mesa del pedido.');
      }
      final maxTables = _settings.tableCount;
      if (maxTables < 1) {
        throw ArgumentError('Este restaurante no tiene mesas configuradas.');
      }
      if (tableNumber < 1 || tableNumber > maxTables) {
        throw ArgumentError('Selecciona una mesa entre 1 y $maxTables.');
      }
    } else {
      if (trimmedName.length < 2) {
        throw ArgumentError('Escribe el nombre del cliente.');
      }
      final digits = trimmedPhone.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 7) {
        throw ArgumentError('Escribe un teléfono válido.');
      }
    }
    if (type == OrderType.delivery && trimmedAddress.length < 5) {
      throw ArgumentError('Escribe la dirección de entrega.');
    }
    // Límites idénticos a `isValidOrder` en firestore.rules (si la APK
    // publica directo a Firestore, el servidor rechaza lo que supere).
    if (trimmedName.length > 80) {
      throw ArgumentError(
        'El nombre del cliente no puede pasar de 80 caracteres.',
      );
    }
    if (trimmedPhone.length > 20) {
      throw ArgumentError('El teléfono no puede pasar de 20 caracteres.');
    }
    if (trimmedAddress.length > 160) {
      throw ArgumentError('La dirección no puede pasar de 160 caracteres.');
    }
    if (notes.trim().length > 300) {
      throw ArgumentError('Las notas no pueden pasar de 300 caracteres.');
    }
    if (lines.length > 50) {
      throw ArgumentError('El pedido no puede tener más de 50 productos.');
    }
    _validateCartStock(lines);
    final resolvedName = trimmedName.isNotEmpty
        ? trimmedName
        : 'Mesa $tableNumber';
    final now = DateTime.now();
    final orderItems = lines
        .map(
          (line) => OrderItem(
            menuItemId: line.menuItemId,
            name: line.name,
            price: line.price,
            quantity: line.quantity,
            emoji: line.emoji,
            imageUrl: line.imageUrl,
          ),
        )
        .toList();
    final subtotal = orderItems.fold<double>(
      0,
      (sum, item) => sum + item.subtotal,
    );
    final actorName = _currentUser?.name;
    final order = Order(
      id: newId('order'),
      code: orderCode(),
      customerName: resolvedName,
      customerPhone: trimmedPhone,
      deliveryAddress: type == OrderType.delivery ? trimmedAddress : '',
      type: type,
      tableNumber: type == OrderType.table ? tableNumber : null,
      items: orderItems,
      subtotal: subtotal,
      tax: 0,
      total: subtotal,
      status: OrderStatus.pending,
      paymentStatus: PaymentStatus.pending,
      paymentMethod: paymentMethod,
      notes: notes.trim(),
      createdAt: now,
      updatedAt: now,
      source: 'app',
      synced: isOnline,
      createdBy: _currentUser?.id,
      createdByName: actorName,
      auditLog: [
        OrderAuditEntry(
          action: 'Pedido creado',
          timestamp: now,
          actorId: _currentUser?.id,
          actorName: actorName ?? (isOnline ? 'Sistema' : 'Sistema (offline)'),
          detail:
              '${type.label}${type == OrderType.table && tableNumber != null ? ' · Mesa $tableNumber' : ''} · ${orderItems.fold<int>(0, (s, i) => s + i.quantity)} uds · ${formatCop(subtotal)}',
        ),
      ],
    );
    _orders.insert(0, order);

    // El pedido se toma en Pendiente desde la APK, así que ahí se consumen los
    // insumos exactamente una vez (flag inventoryDeducted). Los pedidos de la
    // web los descuenta la web cuando pasan a Confirmado.
    var savedOrder = _orders[0];
    if (order.source != 'web' && !order.inventoryDeducted) {
      if (await _deductInventory(order)) {
        savedOrder = savedOrder.copyWith(
          inventoryDeducted: true,
          auditLog: [
            ...savedOrder.auditLog,
            _audit(
              'Inventario descontado',
              detail: 'Descuento al registrar el pedido en Pendiente',
            ),
          ],
        );
        _orders[0] = savedOrder;
      }
    }
    if (savedOrder.tableNumber != null) {
      await _setTableForOrder(savedOrder.tableNumber!, savedOrder.id);
    }
    _upsertCustomerFromOrder(savedOrder);
    await _persistOrders();
    await _persistCustomers();
    notifyListeners();
    return savedOrder;
  }

  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    final index = _orders.indexWhere((order) => order.id == orderId);
    if (index < 0) return;
    final order = _orders[index];
    final now = DateTime.now();
    final entry = _audit(
      status == OrderStatus.cancelled
          ? 'Pedido cancelado'
          : 'Estado actualizado',
      detail: '${order.status.label} → ${status.label}',
    );
    _orders[index] = order.copyWith(
      status: status,
      updatedAt: now,
      updatedBy: _currentUser?.id,
      updatedByName: _currentUser?.name,
      auditLog: [...order.auditLog, entry],
    );
    // En modo web-API, la web descuenta/repondrá al recibir el PATCH. En
    // Firestore directo la APK es responsable (no hay web intermedia).
    if (order.source != 'web' || useDirectFirestore) {
      if (_isDeductibleStatus(status) && !order.inventoryDeducted) {
        if (await _deductInventory(order)) {
          _orders[index] = _orders[index].copyWith(
            inventoryDeducted: true,
            auditLog: [
              ..._orders[index].auditLog,
              _audit(
                'Inventario descontado',
                detail: 'Descuento por cambio a ${status.label}',
              ),
            ],
          );
        }
      }
      if (status == OrderStatus.cancelled && order.inventoryDeducted) {
        await _restoreInventory(order);
        _orders[index] = _orders[index].copyWith(
          inventoryDeducted: false,
          auditLog: [
            ..._orders[index].auditLog,
            _audit('Inventario repuesto', detail: 'Reposición por cancelación'),
          ],
        );
      }
    }
    if (status == OrderStatus.cancelled && order.tableNumber != null) {
      await _freeTableByNumber(order.tableNumber!);
    }
    _upsertCustomerFromOrder(_orders[index]);
    await _persistOrders();
    await _persistCustomers();
    notifyListeners();
    if (_orders[index].source == 'web') {
      await _pushOrderUpdateToServer(_orders[index]);
      await pullServerIngredients();
    }
  }

  Future<void> advanceOrder(String orderId) async {
    final order = orderById(orderId);
    if (order == null) return;
    final next = order.status.nextFor(order.type);
    if (next != null) await updateOrderStatus(orderId, next);
  }

  Future<void> markOrderPaid(
    String orderId, {
    List<OrderPayment>? payments,
  }) async {
    final index = _orders.indexWhere((order) => order.id == orderId);
    if (index < 0) return;
    final order = _orders[index];
    final now = DateTime.now();
    var audit = [...order.auditLog];
    var inventoryDeducted = order.inventoryDeducted;
    final resolvedStatus = order.status == OrderStatus.cancelled
        ? OrderStatus.cancelled
        : order.type == OrderType.delivery
        ? OrderStatus.sent
        : OrderStatus.delivered;
    if (order.source != 'web' || useDirectFirestore) {
      if (resolvedStatus == OrderStatus.cancelled && inventoryDeducted) {
        await _restoreInventory(order);
        inventoryDeducted = false;
        audit.add(_audit('Inventario repuesto', detail: 'Pedido cancelado'));
      } else if (_isDeductibleStatus(resolvedStatus) && !inventoryDeducted) {
        if (await _deductInventory(order)) {
          inventoryDeducted = true;
          audit.add(
            _audit('Inventario descontado', detail: 'Descuento al cobrar'),
          );
        }
      }
    }
    final resolvedPayments = (payments == null || payments.isEmpty)
        ? [OrderPayment(method: order.paymentMethod, amount: order.total)]
        : payments;
    final paymentDetail = resolvedPayments
        .map(
          (p) =>
              '${_settings.paymentLabel(p.method.name)} ${formatCop(p.amount)}${p.note.trim().isNotEmpty ? ' (${p.note.trim()})' : ''}',
        )
        .join(' + ');
    audit.add(
      _audit(
        'Pago registrado',
        detail: '$paymentDetail · Total ${formatCop(order.total)}',
      ),
    );
    if (order.status.isActive) {
      audit.add(
        _audit(
          'Estado actualizado',
          detail: '${order.status.label} → Entregado',
        ),
      );
    }
    _orders[index] = order.copyWith(
      paymentStatus: PaymentStatus.paid,
      paymentMethod: resolvedPayments.first.method,
      payments: resolvedPayments,
      status: resolvedStatus,
      updatedAt: now,
      inventoryDeducted: inventoryDeducted,
      updatedBy: _currentUser?.id,
      updatedByName: _currentUser?.name,
      paidAt: now,
      paidBy: _currentUser?.id,
      paidByName: _currentUser?.name ?? 'Sistema',
      auditLog: audit,
    );
    if (order.tableNumber != null) {
      final otherActive = _orders.any(
        (o) =>
            o.id != order.id &&
            o.tableNumber == order.tableNumber &&
            o.status.isActive,
      );
      if (!otherActive) {
        await _freeTableByNumber(order.tableNumber!);
      } else {
        final other = _orders.firstWhere(
          (o) =>
              o.id != order.id &&
              o.tableNumber == order.tableNumber &&
              o.status.isActive,
        );
        await _setTableForOrder(order.tableNumber!, other.id);
      }
    }
    await _persistOrders();
    notifyListeners();
    if (_orders[index].source == 'web') {
      await _pushOrderUpdateToServer(_orders[index]);
      await pullServerIngredients();
    }
  }

  /// Busca pedidos en preparación para una mesa específica.
  List<Order> preparingOrdersForTable(int tableNumber) {
    return _orders
        .where(
          (o) =>
              o.tableNumber == tableNumber && o.status == OrderStatus.preparing,
        )
        .toList();
  }

  /// Pedidos de una mesa, ordenados por creacion.
  /// Por defecto solo pedidos activos; usa [activeOnly]=false para incluir no activos.
  List<Order> tableOrders(
    int tableNumber, {
    bool includeCancelled = false,
    bool activeOnly = true,
  }) {
    return _orders
        .where(
          (o) =>
              o.tableNumber == tableNumber &&
              (includeCancelled || o.status != OrderStatus.cancelled) &&
              (!activeOnly || o.status.isActive),
        )
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Etiqueta de secuencia "1/2" para pedidos activos de la misma mesa.
  String? tableOrderSequence(Order order) {
    final table = order.tableNumber;
    if (table == null) return null;
    final group = tableOrders(table, activeOnly: true);
    if (group.length <= 1) return null;
    final index = group.indexWhere((o) => o.id == order.id);
    if (index < 0) return null;
    return '${index + 1}/${group.length}';
  }

  /// Pedidos pendientes de pago para una mesa, ordenados por creacion.
  List<Order> payableTableOrders(int tableNumber) {
    return _orders
        .where(
          (o) =>
              o.tableNumber == tableNumber &&
              o.paymentStatus == PaymentStatus.pending &&
              o.status != OrderStatus.cancelled,
        )
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Total pendiente de pago para una mesa.
  double tablePendingTotal(int tableNumber) {
    return payableTableOrders(tableNumber).fold(0, (sum, o) => sum + o.total);
  }

  bool canEditOrder(Order order) {
    return order.status == OrderStatus.pending ||
        order.status == OrderStatus.confirmed ||
        order.status == OrderStatus.preparing;
  }

  Future<Order> updateOrder({
    required String orderId,
    required List<CartLine> lines,
    String customerName = '',
    String customerPhone = '',
    String deliveryAddress = '',
    required OrderType type,
    int? tableNumber,
    PaymentMethod? paymentMethod,
    String notes = '',
  }) async {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index < 0) throw ArgumentError('Pedido no encontrado.');
    final existing = _orders[index];
    if (!canEditOrder(existing)) {
      throw ArgumentError('Este pedido ya no se puede editar.');
    }
    if (lines.isEmpty) {
      throw ArgumentError('El pedido necesita al menos un producto.');
    }
    final trimmedName = customerName.trim();
    final trimmedPhone = customerPhone.trim();
    final trimmedAddress = deliveryAddress.trim();
    if (type == OrderType.table) {
      if (tableNumber == null) {
        throw ArgumentError('Selecciona la mesa del pedido.');
      }
      final maxTables = _settings.tableCount;
      if (maxTables < 1) {
        throw ArgumentError('Este restaurante no tiene mesas configuradas.');
      }
      if (tableNumber < 1 || tableNumber > maxTables) {
        throw ArgumentError('Selecciona una mesa entre 1 y $maxTables.');
      }
    } else {
      if (trimmedName.length < 2) {
        throw ArgumentError('Escribe el nombre del cliente.');
      }
      final digits = trimmedPhone.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 7) {
        throw ArgumentError('Escribe un teléfono válido.');
      }
    }
    if (type == OrderType.delivery && trimmedAddress.length < 5) {
      throw ArgumentError('Escribe la dirección de entrega.');
    }
    // Límites idénticos a `isValidOrder` en firestore.rules (si la APK
    // publica directo a Firestore, el servidor rechaza lo que supere).
    if (trimmedName.length > 80) {
      throw ArgumentError(
        'El nombre del cliente no puede pasar de 80 caracteres.',
      );
    }
    if (trimmedPhone.length > 20) {
      throw ArgumentError('El teléfono no puede pasar de 20 caracteres.');
    }
    if (trimmedAddress.length > 160) {
      throw ArgumentError('La dirección no puede pasar de 160 caracteres.');
    }
    if (notes.trim().length > 300) {
      throw ArgumentError('Las notas no pueden pasar de 300 caracteres.');
    }
    if (lines.length > 50) {
      throw ArgumentError('El pedido no puede tener más de 50 productos.');
    }
    final wasDeducted = existing.inventoryDeducted;
    if (wasDeducted) {
      // El stock de los items existentes ya fue descontado; solo validar el delta.
      final existingQty = <String, int>{};
      for (final item in existing.items) {
        existingQty[item.menuItemId] =
            (existingQty[item.menuItemId] ?? 0) + item.quantity;
      }
      final deltaLines = <CartLine>[];
      for (final line in lines) {
        final prev = existingQty[line.menuItemId] ?? 0;
        final diff = line.quantity - prev;
        if (diff > 0) {
          deltaLines.add(
            CartLine(
              menuItemId: line.menuItemId,
              name: line.name,
              price: line.price,
              quantity: diff,
              emoji: line.emoji,
              imageUrl: line.imageUrl,
            ),
          );
        }
      }
      _validateCartStock(deltaLines);
    } else {
      _validateCartStock(lines);
    }
    final resolvedName = trimmedName.isNotEmpty
        ? trimmedName
        : 'Mesa $tableNumber';
    final now = DateTime.now();
    final orderItems = lines
        .map(
          (line) => OrderItem(
            menuItemId: line.menuItemId,
            name: line.name,
            price: line.price,
            quantity: line.quantity,
            emoji: line.emoji,
            imageUrl: line.imageUrl,
          ),
        )
        .toList();
    final subtotal = orderItems.fold<double>(
      0,
      (sum, item) => sum + item.subtotal,
    );
    final nextTable = type == OrderType.table ? tableNumber : null;

    var audit = [...existing.auditLog];
    if (wasDeducted && (existing.source != 'web' || useDirectFirestore)) {
      await _restoreInventory(existing);
      audit.add(
        _audit(
          'Inventario repuesto',
          detail: 'Reposición antes de editar pedido',
        ),
      );
    }

    audit.add(
      _audit(
        'Pedido editado',
        detail:
            '${orderItems.fold<int>(0, (s, i) => s + i.quantity)} uds · ${formatCop(subtotal)}',
      ),
    );

    final updated = existing.copyWith(
      customerName: resolvedName,
      customerPhone: trimmedPhone,
      deliveryAddress: type == OrderType.delivery ? trimmedAddress : '',
      type: type,
      tableNumber: nextTable,
      clearTableNumber: nextTable == null,
      items: orderItems,
      subtotal: subtotal,
      tax: 0,
      total: subtotal,
      paymentMethod: paymentMethod ?? existing.paymentMethod,
      notes: notes.trim(),
      updatedAt: now,
      synced: isOnline,
      inventoryDeducted: existing.source == 'web'
          ? wasDeducted
          : (wasDeducted || _isDeductibleStatus(existing.status)),
      updatedBy: _currentUser?.id,
      updatedByName: _currentUser?.name,
      auditLog: audit,
    );

    if (updated.inventoryDeducted &&
        (existing.source != 'web' || useDirectFirestore)) {
      await _deductInventory(updated);
      audit.add(
        _audit('Inventario descontado', detail: 'Descuento tras editar pedido'),
      );
    }

    _orders[index] = updated.copyWith(auditLog: audit);

    if (existing.tableNumber != nextTable) {
      if (existing.tableNumber != null) {
        final otherActive = _orders.any(
          (o) =>
              o.id != updated.id &&
              o.tableNumber == existing.tableNumber &&
              o.status.isActive,
        );
        if (!otherActive) {
          await _freeTableByNumber(existing.tableNumber!);
        } else {
          final other = _orders.firstWhere(
            (o) =>
                o.id != updated.id &&
                o.tableNumber == existing.tableNumber &&
                o.status.isActive,
          );
          await _setTableForOrder(existing.tableNumber!, other.id);
        }
      }
      if (nextTable != null) {
        await _setTableForOrder(nextTable, updated.id);
      }
    } else if (nextTable != null) {
      await _setTableForOrder(nextTable, updated.id);
    }

    await _persistOrders();
    notifyListeners();
    return updated;
  }

  /// Agrega items a un pedido existente en preparación.
  Future<void> addItemsToOrder(String orderId, List<CartLine> lines) async {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index < 0) return;
    final order = _orders[index];
    if (order.inventoryDeducted) {
      _validateCartStock(lines);
    } else {
      final combined = <String, CartLine>{};
      for (final item in order.items) {
        combined[item.menuItemId] = CartLine(
          menuItemId: item.menuItemId,
          name: item.name,
          price: item.price,
          quantity: item.quantity,
          emoji: item.emoji,
          imageUrl: item.imageUrl,
        );
      }
      for (final line in lines) {
        final prev = combined[line.menuItemId];
        combined[line.menuItemId] = CartLine(
          menuItemId: line.menuItemId,
          name: line.name,
          price: line.price,
          quantity: (prev?.quantity ?? 0) + line.quantity,
          emoji: line.emoji,
          imageUrl: line.imageUrl.isNotEmpty
              ? line.imageUrl
              : (prev?.imageUrl ?? ''),
        );
      }
      _validateCartStock(combined.values.toList());
    }
    final newItems = [...order.items];
    final addedNames = <String>[];
    for (final line in lines) {
      final existing = newItems.indexWhere(
        (i) => i.menuItemId == line.menuItemId,
      );
      addedNames.add('${line.quantity}× ${line.name}');
      if (existing >= 0) {
        newItems[existing] = OrderItem(
          menuItemId: newItems[existing].menuItemId,
          name: newItems[existing].name,
          price: newItems[existing].price,
          quantity: newItems[existing].quantity + line.quantity,
          emoji: newItems[existing].emoji,
          imageUrl: newItems[existing].imageUrl.isNotEmpty
              ? newItems[existing].imageUrl
              : line.imageUrl,
        );
      } else {
        newItems.add(
          OrderItem(
            menuItemId: line.menuItemId,
            name: line.name,
            price: line.price,
            quantity: line.quantity,
            emoji: line.emoji,
            imageUrl: line.imageUrl,
          ),
        );
      }
    }
    final subtotal = newItems.fold<double>(0, (s, i) => s + i.subtotal);
    var audit = [
      ...order.auditLog,
      _audit('Productos agregados', detail: addedNames.join(', ')),
    ];
    var inventoryDeducted = order.inventoryDeducted;
    if (order.inventoryDeducted &&
        (order.source != 'web' || useDirectFirestore)) {
      // Descontar solo los insumos de las líneas agregadas. En web-API los
      // pedidos web los descuenta la web; en Firestore directo la APK.
      final deltaOrder = Order(
        id: order.id,
        code: order.code,
        customerName: order.customerName,
        customerPhone: order.customerPhone,
        type: order.type,
        tableNumber: order.tableNumber,
        items: lines
            .map(
              (l) => OrderItem(
                menuItemId: l.menuItemId,
                name: l.name,
                price: l.price,
                quantity: l.quantity,
                emoji: l.emoji,
                imageUrl: l.imageUrl,
              ),
            )
            .toList(),
        subtotal: 0,
        tax: 0,
        total: 0,
        status: order.status,
        paymentStatus: order.paymentStatus,
        paymentMethod: order.paymentMethod,
        notes: '',
        createdAt: order.createdAt,
        updatedAt: order.updatedAt,
        source: order.source,
        synced: order.synced,
      );
      await _deductInventory(deltaOrder);
      audit.add(
        _audit(
          'Inventario descontado',
          detail: 'Descuento por productos agregados',
        ),
      );
      inventoryDeducted = true;
    }
    _orders[index] = order.copyWith(
      items: newItems,
      subtotal: subtotal,
      tax: 0,
      total: subtotal,
      updatedAt: DateTime.now(),
      updatedBy: _currentUser?.id,
      updatedByName: _currentUser?.name,
      auditLog: audit,
      inventoryDeducted: inventoryDeducted,
    );
    _upsertCustomerFromOrder(_orders[index]);
    await _persistOrders();
    await _persistCustomers();
    notifyListeners();
  }

  Future<void> markGroupPaid(
    int tableNumber, {
    List<OrderPayment>? payments,
  }) async {
    final group = _orders
        .where(
          (order) =>
              order.tableNumber == tableNumber &&
              order.paymentStatus == PaymentStatus.pending &&
              order.status != OrderStatus.cancelled,
        )
        .toList();
    if (group.isEmpty) return;
    final total = group.fold<double>(0, (s, o) => s + o.total);
    for (final order in group) {
      List<OrderPayment>? orderPayments;
      if (payments != null && payments.isNotEmpty && total > 0) {
        final ratio = order.total / total;
        orderPayments = payments
            .map(
              (p) => OrderPayment(
                method: p.method,
                amount: p.amount * ratio,
                note: p.note,
              ),
            )
            .toList();
      }
      await markOrderPaid(order.id, payments: orderPayments);
    }
  }

  Future<void> cancelOrder(String orderId) =>
      updateOrderStatus(orderId, OrderStatus.cancelled);

  // ---------------------------------------------------------------------------
  // Mesas
  // ---------------------------------------------------------------------------

  List<RestaurantTable> get tables =>
      [..._tables]..sort((a, b) => a.number.compareTo(b.number));

  /// Ajusta las mesas al número configurado (`settings.tableCount`).
  /// - Conserva las existentes por número (y su estado/pedido actual).
  /// - Crea las que falten como `libres`.
  /// - Si hay más mesas de las configuradas, elimina solo las sobrantes libres
  ///   (nunca borra mesas ocupadas/con pedido).
  /// - `0` significa «no gestionar mesas»: deja las existentes intactas para
  ///   no borrar datos demo o de instalaciones anteriores.
  Future<void> _applyTableCount() async {
    final count = _settings.tableCount;
    if (count <= 0) return;
    final existing = <int, RestaurantTable>{
      for (final table in _tables) table.number: table,
    };
    final next = <RestaurantTable>[];
    for (var number = 1; number <= count; number++) {
      final table = existing.remove(number);
      next.add(
        table ??
            RestaurantTable(
              id: 'table-$number',
              number: number,
              status: TableStatus.libre,
              capacity: 4,
              currentOrderId: null,
            ),
      );
    }
    // Sobrantes: conservar las ocupadas, descartar las libres.
    for (final entry in existing.entries) {
      final table = entry.value;
      if (table.status == TableStatus.libre && table.currentOrderId == null) {
        continue;
      }
      next.add(table);
    }
    final changed =
        next.length != _tables.length ||
        next.any((table) => !_tables.contains(table));
    _tables = next;
    if (changed) await _persistTables();
  }

  RestaurantTable? tableByNumber(int number) {
    final matches = _tables.where((table) => table.number == number);
    return matches.isEmpty ? null : matches.first;
  }

  Future<void> updateTableStatus(int tableNumber, TableStatus status) async {
    final index = _tables.indexWhere((table) => table.number == tableNumber);
    if (index < 0) return;
    _tables[index] = _tables[index].copyWith(status: status);
    await _persistTables();
    notifyListeners();
  }

  Future<void> freeTable(int tableNumber) async {
    final orderId = tableByNumber(tableNumber)?.currentOrderId;
    if (orderId != null) {
      final index = _orders.indexWhere((order) => order.id == orderId);
      if (index >= 0) {
        _orders[index] = _orders[index].copyWith(
          auditLog: [
            ..._orders[index].auditLog,
            _audit(
              'Mesa liberada',
              detail: 'Mesa $tableNumber liberada manualmente',
            ),
          ],
        );
        await _persistOrders();
      }
    }
    await _freeTableByNumber(tableNumber);
    await _persistTables();
    notifyListeners();
  }

  Future<void> _setTableForOrder(int tableNumber, String orderId) async {
    final index = _tables.indexWhere((table) => table.number == tableNumber);
    if (index < 0) return;
    _tables[index] = _tables[index].copyWith(
      status: TableStatus.esperandoPedido,
      currentOrderId: orderId,
    );
    await _persistTables();
  }

  Future<void> _freeTableByNumber(int tableNumber) async {
    final index = _tables.indexWhere((table) => table.number == tableNumber);
    if (index < 0) return;
    _tables[index] = _tables[index].copyWith(
      status: TableStatus.libre,
      clearOrder: true,
    );
    await _persistTables();
  }

  // ---------------------------------------------------------------------------
  // Configuración
  // ---------------------------------------------------------------------------

  RestaurantSettings get settings => _settings;

  Future<void> updateSettings(
    RestaurantSettings settings, {
    bool publishToWeb = true,
  }) async {
    _settings = settings;
    await _prefs.setString(_kSettings, jsonEncode(settings.toJson()));
    await _applyTableCount();
    if (publishToWeb) {
      _pendingConfigPatch = settings.toWebConfigPatch();
      await _prefs.setString(
        _kPendingConfigPatch,
        jsonEncode(_pendingConfigPatch),
      );
    }
    notifyListeners();
    if (publishToWeb && _webSyncEnabled && isOnline) {
      await _flushPendingRestaurantConfig();
    }
  }

  // ---------------------------------------------------------------------------
  // Apariencia de la web pública
  // ---------------------------------------------------------------------------

  RestaurantAppearance get restaurantAppearance => _restaurantAppearance;
  bool get hasPendingRestaurantConfig =>
      _pendingRestaurantConfig != null || _pendingConfigPatch != null;
  bool get hasFirebaseSession => _firebaseSignedIn;

  /// Id estable de este dispositivo (persistido fuera del prefijo de tenant).
  String get deviceId => _deviceId;

  NotificationPreferences get notificationPreferences => _notificationPreferences;

  /// Silencia todos los avisos o solo los tipos indicados. Se guarda en el
  /// dispositivo (no por tenant) y se aplica también en el isolate de FCM.
  Future<void> updateNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    _notificationPreferences = preferences;
    await NotificationService.instance.setPreferences(preferences);
    notifyListeners();
  }

  /// Abre el destino asociado a una notificación tocada. Si el aviso pertenece
  /// a otra instancia, cambia de tenant antes de navegar.
  Future<void> handleNotificationTap(Map<String, dynamic> data) async {
    final tenantId = data['tenantId']?.toString().trim() ?? '';
    if (tenantId.isNotEmpty &&
        tenantId != this.tenantId &&
        isValidTenantId(tenantId)) {
      try {
        await switchTenant(tenantId);
      } catch (_) {
        return;
      }
    }
    final type =
        AppNotificationType.fromValue(data['type']?.toString()) ??
        AppNotificationType.newOrder;
    notificationTarget.value = NotificationTarget(
      type: type,
      orderFilter: type.orderFilter,
      orderId: data['orderId']?.toString(),
    );
  }

  /// Registra el dispositivo en `all_user/{email}` para notificaciones push.
  /// Mantiene `deviceId` (último) y `deviceIds` (historial) sin borrar los que
  /// ya había, y respeta las memberships existentes.
  Future<void> registerDeviceId({String? email}) async {
    if (!useDirectFirestore || !_webSyncEnabled || !isOnline) return;
    final normalized = (email ?? _currentUser?.email ?? '')
        .trim()
        .toLowerCase();
    if (normalized.isEmpty) return;
    try {
      final existing = await _request('GET', '/api/all-users/$normalized');
      if (!existing.ok) return;
      final data = existing.json?['allUser'];
      if (data is! Map<String, dynamic>) return;
      final ids = <String>[];
      final raw = data['deviceIds'];
      if (raw is List) {
        for (final value in raw) {
          final id = value?.toString().trim() ?? '';
          if (id.isNotEmpty && !ids.contains(id)) ids.add(id);
        }
      }
      final lastDevice = data['deviceId']?.toString().trim();
      if (lastDevice != null &&
          lastDevice.isNotEmpty &&
          !ids.contains(lastDevice)) {
        ids.add(lastDevice);
      }
      if (!ids.contains(_deviceId)) ids.add(_deviceId);

      // Token FCM de este dispositivo. Se conservan los de los demás para que
      // un login en otro teléfono no deje al anterior sin notificaciones.
      final tokens = <String, String>{};
      final rawTokens = data['fcmTokens'];
      if (rawTokens is Map) {
        rawTokens.forEach((key, value) {
          final device = key?.toString().trim() ?? '';
          final token = value?.toString().trim() ?? '';
          if (device.isNotEmpty && token.isNotEmpty) tokens[device] = token;
        });
      }
      final token = await NotificationService.instance.getToken();
      if (token != null && token.isNotEmpty) {
        tokens[_deviceId] = token;
      }
      await _request(
        'PATCH',
        '/api/all-users/$normalized',
        body: {
          'deviceId': _deviceId,
          'deviceIds': ids,
          'fcmTokens': tokens,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      );
    } catch (_) {
      // Best-effort: el registro de push no debe bloquear el login.
    }
  }

  // --- Diagnóstico (sin secretos) -------------------------------------------
  /// Proyecto Firebase al que apunta el transporte activo.
  String get firebaseProjectId {
    final api = _api;
    return api is FirestoreTransport ? api.projectId : '';
  }

  /// `firestore` (directo a Firestore REST) o `web` (API Next.js).
  String get apiTransportName => useDirectFirestore ? 'firestore' : 'web';

  /// Clave de API pública compilada (nunca el service account).
  bool get hasFirebaseApiKey => AuthService.firebaseApiKey.isNotEmpty;

  /// Rol actual o `null` si no hay sesión.
  UserRole? get currentRole => _currentUser?.role;

  /// Expuesto únicamente para el servicio de subida de imágenes a Storage.
  AuthService get authServiceForMedia => _authService;
  bool get needsFirebaseReLogin => _needsFirebaseReLogin;

  /// Recuperación de contraseña usando Firebase Auth (correo OOB).
  Future<void> sendPasswordReset(String email) =>
      _authService.sendPasswordReset(email);

  /// Guarda la apariencia en el dispositivo, la encola y la publica de inmediato
  /// si hay conexión y un idToken de Firebase vigente.
  Future<void> updateRestaurantAppearance(
    RestaurantAppearance appearance,
  ) async {
    _restaurantAppearance = appearance;
    _pendingRestaurantConfig = appearance;
    await _persistAppearance();
    await _persistPendingRestaurantConfig();
    notifyListeners();
    if (_webSyncEnabled && isOnline) {
      await _flushPendingRestaurantConfig();
    }
  }

  /// Solo reconcilia con la web. El flush de la cola lo hace syncPendingOrders
  /// (incluido el botón «Sincronizar ahora») o el sondeo, para no enviar dos
  /// veces el mismo PATCH al reconectar.
  Future<void> _syncRestaurantConfig() async {
    await pullServerRestaurantConfig();
  }

  void _markNeedsFirebaseReLogin() {
    _firebaseSignedIn = false;
    _needsFirebaseReLogin = true;
    notifyListeners();
  }

  /// Envía el cuerpo exacto del contrato a la web con el idToken Bearer.
  /// Devuelve el código HTTP, o 0 si no se pudo obtener token/conectar.
  Future<int> _pushRestaurantConfigToServer(
    RestaurantAppearance appearance,
    Map<String, dynamic>? settingsPatch,
  ) async {
    if (!useDirectFirestore && _serverUrl.isEmpty) return 0;
    final response = await _request(
      'PATCH',
      '/api/restaurant/config',
      body: {...appearance.toJson(), ...?settingsPatch},
    );
    return response.statusCode;
  }

  /// Vacía la cola offline de configuración cuando la web confirma el cambio.
  /// En 401 (sesión) conserva la cola y pide re-login Firebase; en 403
  /// (falta de permiso) conserva la cola sin marcar sesión vencida.
  Future<void> _flushPendingRestaurantConfig() async {
    if (_flushingRestaurantConfig ||
        !_webSyncEnabled ||
        !isOnline ||
        (_pendingRestaurantConfig == null && _pendingConfigPatch == null)) {
      return;
    }
    _flushingRestaurantConfig = true;
    try {
      final snapshot = _pendingRestaurantConfig;
      final settingsSnapshot = _pendingConfigPatch;
      final status = await _pushRestaurantConfigToServer(
        snapshot ?? _restaurantAppearance,
        settingsSnapshot,
      );
      // 403 no dispara re-login; solo una sesión vencida (401).
      if (status == 401) {
        _markNeedsFirebaseReLogin();
        return;
      }
      if (status < 200 || status >= 300) return;
      // Un cambio local posterior debe conservarse para el próximo intento.
      if (_pendingRestaurantConfig != snapshot) return;
      if (_pendingConfigPatch != settingsSnapshot) return;
      _pendingRestaurantConfig = null;
      _pendingConfigPatch = null;
      _needsFirebaseReLogin = false;
      await _persistPendingRestaurantConfig();
      await _prefs.remove(_kPendingConfigPatch);
      notifyListeners();
    } finally {
      _flushingRestaurantConfig = false;
    }
  }

  /// Reconcilia la apariencia con la web. Los cambios pendientes ganan para no
  /// sobrescribir una edición hecha sin conexión.
  Future<bool> pullServerRestaurantConfig() async {
    if (_pullingRestaurantConfig) return false;
    if (!useDirectFirestore && _serverUrl.isEmpty) return false;
    _pullingRestaurantConfig = true;
    try {
      final response = await _request('GET', '/api/restaurant/config');
      if (!response.ok) return false;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['configured'] == false) {
        return false;
      }
      final rawConfig = decoded['config'];
      if (rawConfig is! Map<String, dynamic>) return false;
      final remote = RestaurantAppearance.fromJson(rawConfig);
      final remoteSettings = RestaurantSettings.fromWebConfig(
        rawConfig,
        _settings,
      );
      final appearanceChanged = remote != _restaurantAppearance;
      final settingsChanged = remoteSettings != _settings;
      if (_pendingRestaurantConfig != null || _pendingConfigPatch != null) {
        return false;
      }
      var changed = false;
      if (appearanceChanged) {
        _restaurantAppearance = remote;
        await _persistAppearance();
        changed = true;
      }
      if (settingsChanged) {
        _settings = remoteSettings;
        await _prefs.setString(_kSettings, jsonEncode(_settings.toJson()));
        await _applyTableCount();
        changed = true;
      }
      if (changed) notifyListeners();
      return changed;
    } catch (_) {
      return false;
    } finally {
      _pullingRestaurantConfig = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Métricas para dashboards y reportes
  // ---------------------------------------------------------------------------

  List<Order> get todayOrders => _orders
      .where((order) => isSameDay(order.createdAt, DateTime.now()))
      .toList();

  double get todaySales => todayOrders
      .where(
        (order) =>
            order.paymentStatus == PaymentStatus.paid &&
            order.status != OrderStatus.cancelled,
      )
      .fold(0, (sum, order) => sum + order.total);

  double get pendingPayments => _orders
      .where(
        (order) =>
            order.paymentStatus == PaymentStatus.pending &&
            order.status != OrderStatus.cancelled,
      )
      .fold(0, (sum, order) => sum + order.total);

  int get pendingCount =>
      _orders.where((order) => order.status == OrderStatus.pending).length;

  int get preparingCount =>
      _orders.where((order) => order.status == OrderStatus.preparing).length;

  int get readyCount =>
      _orders.where((order) => order.status == OrderStatus.ready).length;

  int get occupiedTables =>
      _tables.where((table) => table.status != TableStatus.libre).length;

  int get freeTables =>
      _tables.where((table) => table.status == TableStatus.libre).length;

  int get todayOrderCount => todayOrders.length;

  /// Pedidos efectivamente cobrados, ordenados por fecha de pago.
  List<Order> get paidOrders => _orders
      .where(
        (order) =>
            order.paymentStatus == PaymentStatus.paid &&
            order.status != OrderStatus.cancelled,
      )
      .toList();

  List<Order> paidOrdersInRange(DateTime start, DateTime end) =>
      paidOrders.where((order) {
          final paidAt = order.paidAtOrFallback;
          return !paidAt.isBefore(start) && !paidAt.isAfter(end);
        }).toList()
        ..sort((a, b) => b.paidAtOrFallback.compareTo(a.paidAtOrFallback));

  List<Order> paidOrdersForShift(CashShift shift) {
    final end = shift.closedAt ?? DateTime.now();
    if (!end.isAfter(shift.openedAt)) {
      return paidOrdersInRange(shift.openedAt, shift.openedAt);
    }
    return paidOrdersInRange(shift.openedAt, end);
  }

  DateTime _bucketStart(DateTime value, SalesBucket bucket) => switch (bucket) {
    SalesBucket.hour => DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
    ),
    SalesBucket.day => DateTime(value.year, value.month, value.day),
    SalesBucket.week => DateTime(
      value.year,
      value.month,
      value.day,
    ).subtract(Duration(days: value.weekday - 1)),
    SalesBucket.month => DateTime(value.year, value.month),
  };

  DateTime _nextBucket(DateTime value, SalesBucket bucket) => switch (bucket) {
    SalesBucket.hour => value.add(const Duration(hours: 1)),
    SalesBucket.day => value.add(const Duration(days: 1)),
    SalesBucket.week => value.add(const Duration(days: 7)),
    SalesBucket.month => DateTime(value.year, value.month + 1),
  };

  /// Totales de ventas cobradas en [start]..[end], agrupados por [bucket].
  /// Usa `paidAt` (con fallback) en vez de la fecha de creación del pedido.
  List<DailySales> salesInRange({
    required DateTime start,
    required DateTime end,
    SalesBucket bucket = SalesBucket.day,
  }) {
    final last = _bucketStart(end, bucket);
    final result = <DailySales>[];
    var cursor = _bucketStart(start, bucket);
    var index = 0;
    while (!cursor.isAfter(last) && index < 400) {
      final next = _nextBucket(cursor, bucket);
      final bucketEnd = next.isAfter(end) ? end : next;
      final effectiveStart = index == 0 ? start : cursor;
      final total = paidOrdersInRange(
        effectiveStart,
        bucketEnd,
      ).fold<double>(0, (sum, order) => sum + order.total);
      result.add(DailySales(day: cursor, total: total));
      cursor = next;
      index++;
    }
    return result;
  }

  List<DailySales> salesForShift(CashShift shift) {
    final end = shift.closedAt ?? DateTime.now();
    final effectiveEnd = end.isAfter(shift.openedAt)
        ? end
        : shift.openedAt.add(const Duration(seconds: 1));
    return salesInRange(
      start: shift.openedAt,
      end: effectiveEnd,
      bucket: SalesBucket.hour,
    );
  }

  List<DailySales> salesByDay({int days = 7}) {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1));
    return salesInRange(start: start, end: now, bucket: SalesBucket.day);
  }

  List<ProductSales> topProducts({int limit = 5, Iterable<Order>? orders}) {
    final Map<String, ({int quantity, double total})> accumulator = {};
    for (final order in orders ?? _orders) {
      if (order.status == OrderStatus.cancelled) continue;
      for (final item in order.items) {
        final current = accumulator[item.name] ?? (quantity: 0, total: 0.0);
        accumulator[item.name] = (
          quantity: current.quantity + item.quantity,
          total: current.total + item.subtotal,
        );
      }
    }
    final entries = accumulator.entries.toList()
      ..sort((a, b) => b.value.quantity.compareTo(a.value.quantity));
    return entries
        .take(limit)
        .map(
          (entry) => ProductSales(
            name: entry.key,
            quantity: entry.value.quantity,
            total: entry.value.total,
          ),
        )
        .toList();
  }

  List<CustomerSummary> get customerSummaries {
    final map = <String, _CustomerAgg>{};
    for (final order in _orders) {
      final phone = order.customerPhone.replaceAll(RegExp(r'\D'), '');
      final key = phone.isNotEmpty
          ? phone
          : 'name:${order.customerName.toLowerCase().trim()}';
      if (key.isEmpty || key == 'name:') continue;
      final agg = map.putIfAbsent(
        key,
        () => _CustomerAgg(
          phone: order.customerPhone.trim(),
          name: order.customerName.trim(),
        ),
      );
      if (order.customerName.trim().length >= 2) {
        agg.name = order.customerName.trim();
      }
      if (order.customerPhone.trim().isNotEmpty) {
        agg.phone = order.customerPhone.trim();
      }
      if (order.deliveryAddress.trim().isNotEmpty) {
        agg.address = order.deliveryAddress.trim();
      }
      agg.orderCount += 1;
      if (order.status != OrderStatus.cancelled) {
        agg.totalSpent += order.total;
      }
      if (order.createdAt.isAfter(agg.lastOrderAt)) {
        agg.lastOrderAt = order.createdAt;
      }
      if (order.createdAt.isBefore(agg.firstOrderAt)) {
        agg.firstOrderAt = order.createdAt;
      }
      agg.lastType = order.type;
    }
    final list = map.values
        .map(
          (a) => CustomerSummary(
            name: a.name,
            phone: a.phone,
            address: a.address,
            orderCount: a.orderCount,
            totalSpent: a.totalSpent,
            firstOrderAt: a.firstOrderAt,
            lastOrderAt: a.lastOrderAt,
            lastType: a.lastType,
          ),
        )
        .toList();
    list.sort((a, b) => b.lastOrderAt.compareTo(a.lastOrderAt));
    return list;
  }

  Map<PaymentMethod, double> salesByPaymentMethodFor(Iterable<Order> orders) {
    final result = <PaymentMethod, double>{};
    for (final order in orders) {
      if (order.paymentStatus != PaymentStatus.paid ||
          order.status == OrderStatus.cancelled) {
        continue;
      }
      if (order.payments.isNotEmpty) {
        for (final p in order.payments) {
          result[p.method] = (result[p.method] ?? 0) + p.amount;
        }
      } else {
        result[order.paymentMethod] =
            (result[order.paymentMethod] ?? 0) + order.total;
      }
    }
    return result;
  }

  Map<PaymentMethod, double> get salesByPaymentMethod =>
      salesByPaymentMethodFor(_orders);

  /// Datos vivos del turno abierto. El historial nunca modifica estos totals.
  List<Order> get currentShiftOrders => paidOrdersForShift(_activeShift);

  CashShift get activeShift => _activeShift;

  List<CashShift> get closedShifts => List.unmodifiable(_closedShifts);

  Map<String, Map<String, dynamic>> get pendingCashShiftClosures =>
      Map.unmodifiable(_pendingCashShiftClosures);

  /// Cierra el turno actual, guarda la foto de sus totales y abre uno nuevo.
  /// Los pedidos no se modifican: el nuevo turno empieza en cero porque su
  /// ventana de fechas comienza ahora.
  Future<CashShift> closeShift({
    double? closingAmount,
    String notes = '',
  }) async {
    if (role?.canCloseShift != true) {
      throw StateError('Solo un administrador o cajero puede cerrar caja.');
    }
    final now = DateTime.now();
    final orders = paidOrdersForShift(_activeShift);
    final totals = salesByPaymentMethodFor(orders);
    final total = orders.fold<double>(0, (sum, order) => sum + order.total);
    final closed = _activeShift.copyWith(
      closedAt: now,
      closedBy: _currentUser?.id,
      closedByName: _currentUser?.name ?? 'Sistema',
      orderCount: orders.length,
      total: total,
      totalsByPaymentMethod: totals,
      closingAmount: closingAmount,
      notes: notes.trim(),
      status: 'closed',
    );
    _closedShifts = [closed, ..._closedShifts];
    _activeShift = _newCashShift(now, user: _currentUser);
    _pendingCashShiftClosures[closed.id] = closed.toJson();
    await _persistCashShifts();
    await _persistActiveShift();
    await _persistPendingCashShiftClosures();
    notifyListeners();
    if (_webSyncEnabled) unawaited(_flushPendingCashShiftClosures());
    return closed;
  }

  Future<void> _flushPendingCashShiftClosures() async {
    if (!_webSyncEnabled ||
        !isOnline ||
        _flushingCashShifts ||
        _pendingCashShiftClosures.isEmpty) {
      return;
    }
    if (!useDirectFirestore && _serverUrl.isEmpty) return;
    _flushingCashShifts = true;
    try {
      final snapshot = Map<String, Map<String, dynamic>>.fromEntries(
        _pendingCashShiftClosures.entries.map(
          (entry) =>
              MapEntry(entry.key, Map<String, dynamic>.from(entry.value)),
        ),
      );
      for (final entry in snapshot.entries) {
        // La web espera `{shift: ...}` y crea el turno nuevo por su cuenta.
        // En Firestore directo el cuerpo son los campos del documento y la APK
        // publica ella misma el turno abierto que ya creó localmente.
        final payload = useDirectFirestore
            ? entry.value
            : <String, dynamic>{'shift': entry.value};
        final response = await _request(
          'POST',
          '/api/cash-shifts/close',
          body: payload,
          query: useDirectFirestore ? {'id': entry.key} : const {},
        );
        if (!response.ok) continue;
        if (useDirectFirestore) {
          final opened = await _request(
            'POST',
            '/api/cash-shifts',
            body: _activeShift.toJson(),
            query: {'id': _activeShift.id},
          );
          if (!opened.ok) continue;
        }
        if (response.body.isNotEmpty) {
          try {
            final decoded = jsonDecode(response.body);
            if (decoded is Map<String, dynamic>) {
              final remoteCurrent = decoded['currentShift'];
              if (remoteCurrent is Map<String, dynamic>) {
                final parsed = CashShift.fromJson(remoteCurrent);
                if (parsed.openedAt.isAfter(_activeShift.openedAt)) {
                  _activeShift = parsed;
                }
              }
            }
          } catch (_) {
            // El cierre ya se aplicó; no hace falta la respuesta para darlo por
            // enviado si el servidor devolvió 2xx.
          }
        }
        if (mapEquals(_pendingCashShiftClosures[entry.key], entry.value)) {
          _pendingCashShiftClosures.remove(entry.key);
        }
      }
      await _persistPendingCashShiftClosures();
      await _persistActiveShift();
      notifyListeners();
    } catch (_) {
      // Queda en la cola para el próximo evento de conectividad.
    } finally {
      _flushingCashShifts = false;
    }
  }

  /// Baja el turno abierto y el historial publicados por la web. Los cierres
  /// pendientes ganan para no sobrescribir un cierre hecho sin conexión.
  Future<void> pullCashShifts() async {
    if (!_webSyncEnabled || !isOnline || _pullingCashShifts) return;
    if (!useDirectFirestore && _serverUrl.isEmpty) return;
    _pullingCashShifts = true;
    try {
      final response = await _request('GET', '/api/cash-shifts');
      if (!response.ok) return;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return;
      final notifyChanges = _shiftsPrimed;
      _shiftsPrimed = true;
      final knownClosedIds = _closedShifts.map((shift) => shift.id).toSet();
      var changed = false;

      String? remoteCurrentId;
      final remoteCurrent = decoded['currentShift'];
      if (remoteCurrent is Map<String, dynamic>) {
        final parsed = CashShift.fromJson(remoteCurrent);
        remoteCurrentId = parsed.id;
        if (_pendingCashShiftClosures.isEmpty &&
            parsed.openedAt.isAfter(_activeShift.openedAt)) {
          _activeShift = parsed;
          changed = true;
        }
      }

      final remoteShifts = decoded['shifts'];
      if (remoteShifts is List<dynamic>) {
        // Versiones anteriores guardaban el turno abierto en este historial;
        // lo descartamos también en local para que el arreglo se aplique sin
        // borrar datos del dispositivo.
        final byId = {
          for (final shift in _closedShifts)
            if (shift.isClosed && shift.id != remoteCurrentId) shift.id: shift,
        };
        for (final raw in remoteShifts.whereType<Map<String, dynamic>>()) {
          final parsed = CashShift.fromJson(raw);
          // El turno abierto es el activo, no un cierre; mostrarlo en
          // «Turnos cerrados» confundiría el historial y el detalle.
          if (parsed.id.isEmpty ||
              parsed.status != 'closed' ||
              parsed.id == remoteCurrentId ||
              _pendingCashShiftClosures.containsKey(parsed.id)) {
            continue;
          }
          byId[parsed.id] = parsed;
        }
        final merged = byId.values.toList()
          ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
        if (merged.length != _closedShifts.length ||
            !mapEquals(
              {for (final shift in merged) shift.id: shift.toJson()},
              {for (final shift in _closedShifts) shift.id: shift.toJson()},
            )) {
          _closedShifts = merged;
          changed = true;
        }
      }
      if (changed) {
        await _persistCashShifts();
        await _persistActiveShift();
        notifyListeners();
      }
      if (notifyChanges && remoteShifts is List<dynamic>) {
        for (final raw in remoteShifts.whereType<Map<String, dynamic>>()) {
          final parsed = CashShift.fromJson(raw);
          if (parsed.id.isEmpty ||
              parsed.status != 'closed' ||
              knownClosedIds.contains(parsed.id)) {
            continue;
          }
          unawaited(
            NotificationService.instance.showLocal(
              type: AppNotificationType.shiftClosed,
              tenantId: tenantId,
              title: 'Turno cerrado',
              body: 'Cierre \$${parsed.total.toStringAsFixed(0)} · '
                  '${parsed.orderCount} pedido(s)',
              orderId: parsed.id,
            ),
          );
        }
      }
    } catch (_) {
      // El estado local sigue siendo válido; se reintenta en el próximo pull.
    } finally {
      _pullingCashShifts = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Utilidades
  // ---------------------------------------------------------------------------

  Future<void> resetDemoData() async {
    final seedDemo = AuthService.firebaseApiKey.isEmpty;
    await _prefs.remove(_kCategories);
    await _prefs.remove(_kItems);
    await _prefs.remove(_kIngredients);
    await _prefs.remove(_kOrders);
    await _prefs.remove(_kInventoryLosses);
    await _prefs.remove(_kTables);
    await _prefs.remove(_kSettings);
    await _prefs.remove(_kSession);
    await _prefs.remove(_kUsers);
    await _prefs.remove(_kLastSync);
    await _prefs.remove(_kServerUrl);
    await _prefs.remove(_kCustomers);
    await _prefs.remove(_kWebVisits);
    await _prefs.remove(_kPendingMenuStatuses);
    await _prefs.remove(_kPendingMenuItemPatches);
    await _prefs.remove(_kPendingIngredientStocks);
    await _prefs.remove(_kActiveCashShift);
    await _prefs.remove(_kCashShifts);
    await _prefs.remove(_kPendingCashShiftClosures);
    await _prefs.remove(_kAppearance);
    await _prefs.remove(_kPendingRestaurantConfig);
    await _prefs.remove(_kPendingConfigPatch);
    await _prefs.remove(_kPendingFeaturedItems);
    try {
      await _authService.logout();
    } catch (_) {}
    _firebaseSignedIn = false;
    _needsFirebaseReLogin = false;
    _pendingMenuStatuses = {};
    _dirtyMenuItemIds = {};
    _pendingIngredientStocks = {};
    _pendingCashShiftClosures = {};
    _closedShifts = [];
    _activeShift = _newCashShift(DateTime.now());
    _categories = seedDemo ? [...SeedData.categories] : <Category>[];
    _items = seedDemo ? SeedData.menuItemsWithRecipes() : <MenuItem>[];
    _ingredients = seedDemo ? [...SeedData.ingredients] : <Ingredient>[];
    _orders = seedDemo
        ? (SeedData.orders()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
        : <Order>[];
    _inventoryLosses = [];
    _tables = seedDemo ? SeedData.tables() : <RestaurantTable>[];
    _settings = seedDemo ? SeedData.settings : RestaurantSettings.defaults;
    _restaurantAppearance = RestaurantAppearance.defaults;
    _pendingRestaurantConfig = null;
    _pendingConfigPatch = null;
    _pendingFeaturedItems = {};
    _currentUser = null;
    _users = seedDemo ? [...SeedData.users] : <AppUser>[];
    _customers = <CustomerRecord>[];
    _webVisits = <WebVisit>[];
    _lastSync = null;
    _serverUrl = defaultServerUrl;
    await _persistCategories();
    await _persistItems();
    await _persistIngredients();
    await _persistOrders();
    await _persistTables();
    await _persistUsers();
    await _persistActiveShift();
    await _persistCashShifts();
    await _persistAppearance();
    await _persistPendingRestaurantConfig();
    await _syncRestaurantConfig();
    notifyListeners();
  }

  OrderAuditEntry _audit(String action, {String detail = ''}) =>
      OrderAuditEntry(
        action: action,
        timestamp: DateTime.now(),
        actorId: _currentUser?.id,
        actorName:
            _currentUser?.name ?? (isOnline ? 'Sistema' : 'Sistema (offline)'),
        detail: detail,
      );

  String _slugify(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp('[áàäâ]'), 'a')
        .replaceAll(RegExp('[éèëê]'), 'e')
        .replaceAll(RegExp('[íìïî]'), 'i')
        .replaceAll(RegExp('[óòöô]'), 'o')
        .replaceAll(RegExp('[úùüû]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp('(^-|-\$)'), '');
    return normalized.isEmpty ? 'plato' : normalized;
  }

  Future<void> _persistCategories() async {
    await _prefs.setString(
      _kCategories,
      jsonEncode(_categories.map((category) => category.toJson()).toList()),
    );
  }

  Future<void> _persistItems() async {
    await _prefs.setString(
      _kItems,
      jsonEncode(_items.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _persistDirtyMenuItemIds() async {
    await _prefs.setString(
      _kPendingMenuItemPatches,
      jsonEncode(_dirtyMenuItemIds.toList()),
    );
  }

  Future<void> _persistIngredients() async {
    await _prefs.setString(
      _kIngredients,
      jsonEncode(
        _ingredients.map((ingredient) => ingredient.toJson()).toList(),
      ),
    );
  }

  Future<void> _persistOrders() async {
    await _prefs.setString(
      _kOrders,
      jsonEncode(_orders.map((order) => order.toJson()).toList()),
    );
  }

  Future<void> _persistInventoryLosses() async {
    await _prefs.setString(
      _kInventoryLosses,
      jsonEncode(_inventoryLosses.map((loss) => loss.toJson()).toList()),
    );
  }

  Future<void> _persistTables() async {
    await _prefs.setString(
      _kTables,
      jsonEncode(_tables.map((table) => table.toJson()).toList()),
    );
  }

  Future<void> _persistCustomers() async {
    await _prefs.setString(
      _kCustomers,
      jsonEncode(_customers.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> _persistUsers() async {
    await _prefs.setString(
      _kUsers,
      jsonEncode(_users.map((user) => user.toJson()).toList()),
    );
  }

  Future<void> _persistWebVisits() async {
    await _prefs.setString(
      _kWebVisits,
      jsonEncode(_webVisits.map((v) => v.toJson()).toList()),
    );
  }

  Future<void> _persistPendingMenuStatuses() async {
    await _prefs.setString(
      _kPendingMenuStatuses,
      jsonEncode(_pendingMenuStatuses),
    );
  }

  Future<void> _persistPendingFeaturedItems() async {
    await _prefs.setString(
      _kPendingFeaturedItems,
      jsonEncode(_pendingFeaturedItems),
    );
  }

  Future<void> _persistPendingIngredientStocks() async {
    await _prefs.setString(
      _kPendingIngredientStocks,
      jsonEncode(_pendingIngredientStocks),
    );
  }

  Future<void> _persistActiveShift() async {
    await _prefs.setString(
      _kActiveCashShift,
      jsonEncode(_activeShift.toJson()),
    );
  }

  Future<void> _persistCashShifts() async {
    await _prefs.setString(
      _kCashShifts,
      jsonEncode(_closedShifts.map((shift) => shift.toJson()).toList()),
    );
  }

  Future<void> _persistPendingCashShiftClosures() async {
    await _prefs.setString(
      _kPendingCashShiftClosures,
      jsonEncode(_pendingCashShiftClosures),
    );
  }

  Future<void> _persistAppearance() async {
    await _prefs.setString(
      _kAppearance,
      jsonEncode(_restaurantAppearance.toJson()),
    );
  }

  Future<void> _persistPendingRestaurantConfig() async {
    final pending = _pendingRestaurantConfig;
    if (pending == null) {
      await _prefs.remove(_kPendingRestaurantConfig);
      return;
    }
    await _prefs.setString(
      _kPendingRestaurantConfig,
      jsonEncode(pending.toJson()),
    );
  }

  List<CustomerRecord> get crmCustomers =>
      _customers.where((c) => c.hasPhone).toList()
        ..sort((a, b) => b.lastOrderAt.compareTo(a.lastOrderAt));

  CustomerRecord? customerByPhone(String phone) {
    final normalized = phone.replaceAll(RegExp(r'\D'), '');
    if (normalized.length < 7) return null;
    for (final c in _customers) {
      if (c.normalizedPhone == normalized) return c;
    }
    return null;
  }

  Future<void> updateCustomer(CustomerRecord record) async {
    if (!record.hasPhone) return;
    final idx = _customers.indexWhere((c) => c.id == record.id);
    final updated = record.copyWith(updatedAt: DateTime.now());
    if (idx >= 0) {
      _customers[idx] = updated;
    } else {
      _customers = [..._customers, updated];
    }
    await _persistCustomers();
    notifyListeners();
    await _pushCustomerToServer(updated);
  }

  // ---------------------------------------------------------------------------
  // Visitas originadas en la web
  // ---------------------------------------------------------------------------

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  List<WebVisit> get webVisits => List.unmodifiable(_webVisits);

  List<WebVisit> get todayWebVisits => webVisitsForDay(_todayKey());

  int get todayWebVisitCount => todayWebVisits.length;

  List<WebVisit> webVisitsForDay(String dayKey) {
    final list = _webVisits.where((v) => v.dayKey == dayKey).toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return list;
  }

  List<WebVisit> get registeredWebVisits =>
      _webVisits.where((v) => v.registered).toList()
        ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

  List<WebVisit> get anonymousWebVisits =>
      _webVisits.where((v) => !v.registered).toList()
        ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

  /// Historial agrupado por día, del más reciente al más antiguo.
  Map<String, List<WebVisit>> get webVisitsByDay {
    final grouped = <String, List<WebVisit>>{};
    for (final visit in _webVisits) {
      grouped.putIfAbsent(visit.dayKey, () => []).add(visit);
    }
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return {
      for (final key in sortedKeys)
        key: (grouped[key]!
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt))),
    };
  }

  List<String> _mergeAddresses(List<String> existing, String address) {
    final clean = address.trim();
    if (clean.isEmpty) return existing;
    final exists = existing.any((a) => a.toLowerCase() == clean.toLowerCase());
    if (exists) return existing;
    return [...existing, clean];
  }

  void _upsertCustomerFromOrder(Order order) {
    final normalized = order.customerPhone.replaceAll(RegExp(r'\D'), '');
    if (normalized.length < 7) return;
    final name = order.customerName.trim();
    final address = order.deliveryAddress.trim();
    final idx = _customers.indexWhere((c) => c.normalizedPhone == normalized);
    final now = DateTime.now();
    if (idx < 0) {
      _customers = [
        ..._customers,
        CustomerRecord(
          id: 'cus_$normalized',
          name: name,
          phone: order.customerPhone.trim(),
          address: address,
          tags: const [],
          notes: '',
          createdAt: order.createdAt,
          updatedAt: now,
          lastOrderAt: order.createdAt,
          orderCount: 1,
          totalSpent: order.status == OrderStatus.cancelled ? 0 : order.total,
          lastType: order.type,
          addresses: address.isEmpty ? const [] : [address],
        ),
      ];
      return;
    }
    final current = _customers[idx];
    final orders = _orders.where((o) {
      final p = o.customerPhone.replaceAll(RegExp(r'\D'), '');
      return p == normalized;
    }).toList();
    final orderCount = orders.length;
    final totalSpent = orders
        .where((o) => o.status != OrderStatus.cancelled)
        .fold<double>(0, (s, o) => s + o.total);
    final last = orders.isEmpty
        ? order
        : (orders..sort((a, b) => b.createdAt.compareTo(a.createdAt))).first;
    final first = orders.isEmpty
        ? order
        : (orders..sort((a, b) => a.createdAt.compareTo(b.createdAt))).first;
    _customers[idx] = current.copyWith(
      name: name.isNotEmpty ? name : current.name,
      phone: order.customerPhone.trim().isNotEmpty
          ? order.customerPhone.trim()
          : current.phone,
      address: address.isNotEmpty ? address : current.address,
      addresses: _mergeAddresses(current.addresses, address),
      updatedAt: now,
      createdAt: first.createdAt.isBefore(current.createdAt)
          ? first.createdAt
          : current.createdAt,
      lastOrderAt: last.createdAt.isAfter(current.lastOrderAt)
          ? last.createdAt
          : current.lastOrderAt,
      orderCount: orderCount > 0 ? orderCount : current.orderCount,
      totalSpent: orderCount > 0 ? totalSpent : current.totalSpent,
      lastType: last.type,
    );
  }

  Future<void> _rebuildCustomersFromOrders({bool persist = false}) async {
    final byPhone = <String, CustomerRecord>{};
    for (final existing in _customers) {
      if (existing.hasPhone) byPhone[existing.normalizedPhone] = existing;
    }
    final sortedOrders = [..._orders]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final order in sortedOrders) {
      final normalized = order.customerPhone.replaceAll(RegExp(r'\D'), '');
      if (normalized.length < 7) continue;
      final current = byPhone[normalized];
      final name = order.customerName.trim();
      final address = order.deliveryAddress.trim();
      if (current == null) {
        byPhone[normalized] = CustomerRecord(
          id: 'cus_$normalized',
          name: name,
          phone: order.customerPhone.trim(),
          address: address,
          tags: const [],
          notes: '',
          createdAt: order.createdAt,
          updatedAt: DateTime.now(),
          lastOrderAt: order.createdAt,
          orderCount: 1,
          totalSpent: order.status == OrderStatus.cancelled ? 0 : order.total,
          lastType: order.type,
          addresses: address.isEmpty ? const [] : [address],
        );
      } else {
        final isLast = !order.createdAt.isBefore(current.lastOrderAt);
        final isFirst = order.createdAt.isBefore(current.createdAt);
        byPhone[normalized] = current.copyWith(
          name: name.isNotEmpty ? name : current.name,
          phone: order.customerPhone.trim().isNotEmpty
              ? order.customerPhone.trim()
              : current.phone,
          address: address.isNotEmpty ? address : current.address,
          addresses: _mergeAddresses(current.addresses, address),
          createdAt: isFirst ? order.createdAt : current.createdAt,
          lastOrderAt: isLast ? order.createdAt : current.lastOrderAt,
          orderCount: current.orderCount + 1,
          totalSpent:
              current.totalSpent +
              (order.status == OrderStatus.cancelled ? 0 : order.total),
          lastType: isLast ? order.type : current.lastType,
        );
      }
    }
    _customers = byPhone.values.toList()
      ..sort((a, b) => b.lastOrderAt.compareTo(a.lastOrderAt));
    if (persist) await _persistCustomers();
  }

  @override
  void dispose() {
    _webPollTimer?.cancel();
    _connectivity.online.removeListener(_onConnectivityChanged);
    if (_ownsConnectivity) _connectivity.dispose();
    notificationTarget.dispose();
    super.dispose();
  }
}

class CustomerSummary {
  const CustomerSummary({
    required this.name,
    required this.phone,
    required this.address,
    required this.orderCount,
    required this.totalSpent,
    required this.firstOrderAt,
    required this.lastOrderAt,
    required this.lastType,
  });

  final String name;
  final String phone;
  final String address;
  final int orderCount;
  final double totalSpent;
  final DateTime firstOrderAt;
  final DateTime lastOrderAt;
  final OrderType lastType;
}

class _CustomerAgg {
  _CustomerAgg({required this.name, required this.phone});

  String name;
  String phone;
  String address = '';
  int orderCount = 0;
  double totalSpent = 0;
  DateTime firstOrderAt = DateTime(9999);
  DateTime lastOrderAt = DateTime(2000);
  OrderType lastType = OrderType.pickup;
}
