// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import '../utils/formatters.dart';
import 'seed_data.dart';

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
class RestaurantRepository extends ChangeNotifier {
  RestaurantRepository._({
    required SharedPreferences prefs,
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
  }) : _prefs = prefs,
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
  static const _kPendingIngredientStocks = 'rm_pending_ingredient_stocks_v1';
  static const _kActiveCashShift = 'rm_active_cash_shift_v1';
  static const _kCashShifts = 'rm_cash_shifts_v1';
  static const _kPendingCashShiftClosures = 'rm_pending_cash_shift_closures_v1';
  static const _kAppearance = 'rm_restaurant_appearance_v1';
  static const _kPendingRestaurantConfig = 'rm_pending_restaurant_config_v1';
  static const _kPendingConfigPatch = 'rm_pending_config_patch_v1';
  static const _kPendingFeaturedItems = 'rm_pending_featured_items_v1';

  /// URL de la web pública para importar los pedidos creados en línea.
  /// Se puede cambiar desde Configuración o con
  /// `--dart-define=WEB_API_URL=http://mi-servidor:3000`.
  static const defaultServerUrl = String.fromEnvironment(
    'WEB_API_URL',
    defaultValue: 'http://192.168.101.7:3000',
  );

  static const _pollInterval = Duration(seconds: 12);

  final SharedPreferences _prefs;
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
  Future<void>? _syncFuture;
  Timer? _webPollTimer;

  static Future<RestaurantRepository> load({
    ConnectivityService? connectivity,
    bool watchConnectivity = true,
    AuthService? authService,
    bool? requireFirebaseSignIn,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final service = connectivity ?? ConnectivityService();
    if (watchConnectivity) {
      await service.init();
    }

    final categories = _readList<Category>(
      prefs,
      _kCategories,
      Category.fromJson,
    );
    final storedItems = _readList<MenuItem>(prefs, _kItems, MenuItem.fromJson);
    final seedItems = SeedData.menuItemsWithRecipes();
    final migratedItems = _migrateRecipeIngredientIds(storedItems);
    final items = storedItems.isEmpty
        ? seedItems
        : _hydrateSeedExtras(migratedItems, seedItems);
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
    final tables = _readList<RestaurantTable>(
      prefs,
      _kTables,
      RestaurantTable.fromJson,
    );
    final settingsRaw = prefs.getString(_kSettings);
    final settings = settingsRaw == null
        ? SeedData.settings
        : RestaurantSettings.fromJson(
            jsonDecode(settingsRaw) as Map<String, dynamic>,
          );
    final sessionRaw = prefs.getString(_kSession);
    AppUser? currentUser = sessionRaw == null
        ? null
        : AppUser.fromJson(jsonDecode(sessionRaw) as Map<String, dynamic>);
    final storedUsers = _readList(prefs, _kUsers, AppUser.fromJson);
    final users = storedUsers.isEmpty ? [...SeedData.users] : storedUsers;
    final lastSyncRaw = prefs.getString(_kLastSync);
    final lastSync = lastSyncRaw == null
        ? null
        : DateTime.tryParse(lastSyncRaw);
    final serverUrl = _normalizeServerUrl(
      prefs.getString(_kServerUrl) ?? defaultServerUrl,
    );
    final customers = _readList(prefs, _kCustomers, CustomerRecord.fromJson);
    final webVisits = _readList(prefs, _kWebVisits, WebVisit.fromJson);
    final pendingMenuStatuses = _readPendingMenuStatuses(prefs);
    final pendingIngredientStocks = _readPendingIngredientStocks(prefs);
    final activeShiftRaw = prefs.getString(_kActiveCashShift);
    final activeShift = activeShiftRaw == null
        ? _newCashShift(DateTime.now(), user: currentUser)
        : CashShift.fromJson(jsonDecode(activeShiftRaw) as Map<String, dynamic>);
    final closedShifts = _readList(
      prefs,
      _kCashShifts,
      CashShift.fromJson,
    )..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    final pendingCashShiftClosures = _readPendingCashShiftClosures(prefs);
    final appearanceRaw = prefs.getString(_kAppearance);
    final appearance = appearanceRaw == null
        ? RestaurantAppearance.defaults
        : RestaurantAppearance.fromStoredJson(appearanceRaw);
    final pendingConfig = RestaurantAppearance.tryFromStoredJson(
      prefs.getString(_kPendingRestaurantConfig),
    );
    final pendingConfigPatch = _readPendingConfigPatch(prefs);
    final pendingFeaturedItems = _readPendingFeaturedItems(prefs);
    final auth = authService ?? AuthService();
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
      connectivity: service,
      ownsConnectivity: connectivity == null,
      categories: categories.isEmpty ? [...SeedData.categories] : categories,
      items: items,
      ingredients: ingredients.isEmpty
          ? [...SeedData.ingredients]
          : ingredients,
      orders: _hydrateOrderExtras(
        orders.isEmpty ? SeedData.orders() : orders,
        seedItems,
      )..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      inventoryLosses: inventoryLosses,
      tables: tables.isEmpty ? SeedData.tables() : tables,
      customers: customers,
      webVisits: webVisits,
      pendingMenuStatuses: pendingMenuStatuses,
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
    if (tables.isEmpty) await repository._persistTables();
    if (storedUsers.isEmpty) await repository._persistUsers();
    if (customers.isEmpty) await repository._persistCustomers();
    if (activeShiftRaw == null) await repository._persistActiveShift();
    if (appearanceRaw == null) await repository._persistAppearance();

    if (watchConnectivity) {
      repository._startWebPolling();
    }

    return repository;
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
        paidAt: order.paidAt ??
            (order.paymentStatus == PaymentStatus.paid
                ? order.updatedAt
                : null),
        paidByName: order.paidByName ??
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
    SharedPreferences prefs,
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
    SharedPreferences prefs,
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
    SharedPreferences prefs,
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

  static Map<String, Map<String, dynamic>> _readPendingIngredientStocks(
    SharedPreferences prefs,
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
    SharedPreferences prefs,
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

  static Map<String, bool> _readPendingFeaturedItems(
    SharedPreferences prefs,
  ) {
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

  /// Inicia sesión con Firebase Auth (REST) y usa la cuenta local que coincide
  /// por correo para conservar el rol definido en el dispositivo.
  Future<AppUser> loginWithFirebase(String email, String password) async {
    if (AuthService.firebaseApiKey.isEmpty) {
      throw StateError(
        'Firebase no está configurado. Define FIREBASE_WEB_API_KEY.',
      );
    }
    final normalized = email.trim().toLowerCase();
    final matches = _users.where(
      (user) => user.email.toLowerCase() == normalized,
    );
    if (matches.isEmpty) {
      throw ArgumentError('No hay un usuario local con ese correo.');
    }
    await _authService.signIn(email, password);
    _currentUser = matches.first;
    await _prefs.setString(_kSession, jsonEncode(_currentUser!.toJson()));
    _firebaseSignedIn = true;
    _needsFirebaseReLogin = false;
    notifyListeners();
    if (_webSyncEnabled && isOnline) {
      await _flushPendingRestaurantConfig();
      await pullServerRestaurantConfig();
    }
    return _currentUser!;
  }

  Future<void> logout() async {
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
    final pendingIds = pendingSyncOrders.map((order) => order.id).toSet();
    _syncing = true;
    notifyListeners();

    try {
      // Aquí se conectaría el adaptador de Firestore:
      // await _firestore.collection('orders').doc(order.id).set(order.toJson());
      await Future<void>.delayed(const Duration(milliseconds: 600));

      if (pendingIds.isNotEmpty) {
        final now = DateTime.now();
        _orders = _orders
            .map(
              (order) => pendingIds.contains(order.id)
                  ? order.copyWith(
                      synced: true,
                      updatedAt: now,
                      auditLog: [
                        ...order.auditLog,
                        _audit(
                          'Pedido sincronizado',
                          detail:
                              'Enviado al servidor al restablecerse la conexión',
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
    if (!_webSyncEnabled || !isOnline || _serverUrl.isEmpty) return;
    await _flushPendingIngredientPatches();
    await pullServerIngredients();
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
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(Uri.parse('$_serverUrl/api/health'));
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Descarga los pedidos creados en la web y los agrega al repositorio.
  ///
  /// Devuelve cuántos pedidos nuevos se importaron. Los pedidos locales que
  /// ya existen no se sobrescriben para no perder cambios de estado hechos
  /// desde la app.
  Future<int> pullServerOrders() async {
    if (_pullingServerOrders || _serverUrl.isEmpty) return 0;
    _pullingServerOrders = true;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(Uri.parse('$_serverUrl/api/orders'));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        return 0;
      }
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      final rawList = decoded is List
          ? decoded
          : decoded is Map<String, dynamic>
          ? decoded['orders']
          : null;
      if (rawList is! List) return 0;

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
      client.close(force: true);
    }
  }

  Future<void> _pushOrderUpdateToServer(Order order) async {
    if (_serverUrl.isEmpty) return;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.patchUrl(
        Uri.parse('$_serverUrl/api/orders/${Uri.encodeComponent(order.id)}'),
      );
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      // La web es la dueña del inventario de sus propios pedidos. Enviamos el
      // flag en false para que decida con su valor persistido: si el pedido ya
      // descontó no hace nada; si es el primer estado superior, descuenta.
      request.write(
        jsonEncode({
          'status': order.status.name,
          'paymentStatus': order.paymentStatus.name,
          'inventoryDeducted': false,
          if (order.paymentStatus == PaymentStatus.paid) ...{
            'paidAt': (order.paidAt ?? order.updatedAt).toIso8601String(),
            'paidBy': order.paidBy,
            'paidByName': order.paidByName ?? order.updatedByName,
          },
        }),
      );
      final response = await request.close();
      await response.drain<void>();
    } catch (_) {
      // Si falla, el siguiente pull reconciliará cuando haya conexión.
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _pushCustomerToServer(CustomerRecord customer) async {
    if (_serverUrl.isEmpty || !customer.hasPhone) return;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(
        Uri.parse('$_serverUrl/api/customers'),
      );
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(jsonEncode(customer.toJson()));
      final response = await request.close();
      await response.drain<void>();
    } catch (_) {
      // Best-effort: queda en local y se puede reenviar en próxima sync.
    } finally {
      client.close(force: true);
    }
  }

  Future<void> pullServerCustomers() async {
    if (_serverUrl.isEmpty) return;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(
        Uri.parse('$_serverUrl/api/customers'),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        return;
      }
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
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
    } finally {
      client.close(force: true);
    }
  }

  /// Descarga las visitas registradas por la web pública.
  ///
  /// El feed es la fuente de verdad: se reemplaza la copia local para eliminar
  /// duplicados históricos y se deduplica por cliente/día. Los datos quedan en
  /// SharedPreferences para que el panel CRM funcione también sin conexión.
  Future<int> pullServerVisits() async {
    if (_serverUrl.isEmpty) return 0;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(Uri.parse('$_serverUrl/api/visits'));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        return 0;
      }
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
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
    } finally {
      client.close(force: true);
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
    if (_serverUrl.isEmpty) return null;
    // Sin token no se publica nada: la cola conserva el cambio para reintentarlo.
    String token;
    try {
      token = await _authService.getIdToken();
    } catch (_) {
      return null;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.patchUrl(
        Uri.parse('$_serverUrl/api/menu/${Uri.encodeComponent(itemId)}'),
      );
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.write(
        jsonEncode({'status': status, 'manual': manual, 'reason': reason}),
      );
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        return null;
      }
      final body = await utf8.decoder.bind(response).join();
      try {
        final decoded = jsonDecode(body);
        final item = decoded is Map<String, dynamic> ? decoded['item'] : null;
        final effective = item is Map<String, dynamic> ? item['status'] : null;
        return effective is String && effective.isNotEmpty ? effective : status;
      } catch (_) {
        return status;
      }
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Publica el campo «Favorito» usado por el carrusel de la web.
  Future<bool> _pushMenuItemFeaturedToServer(
    String itemId,
    bool featured,
  ) async {
    if (_serverUrl.isEmpty) return false;
    // Sin token no se publica nada: la cola conserva el cambio para reintentarlo.
    String token;
    try {
      token = await _authService.getIdToken();
    } catch (_) {
      return false;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.patchUrl(
        Uri.parse('$_serverUrl/api/menu/${Uri.encodeComponent(itemId)}'),
      );
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.write(jsonEncode({'featured': featured}));
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _flushPendingFeaturedItems() async {
    if (!_webSyncEnabled || !isOnline || _pendingFeaturedItems.isEmpty) return;
    final snapshot = Map<String, bool>.from(_pendingFeaturedItems);
    for (final entry in snapshot.entries) {
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
    _flushingMenuStatuses = true;
    try {
      final snapshot = Map<String, Map<String, dynamic>>.from(
        _pendingMenuStatuses,
      );
      var localChanges = 0;
      for (final entry in snapshot.entries) {
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

  /// Reconcilia la disponibilidad local con el catálogo publicado por la web.
  ///
  /// Los cambios pendientes de envío tienen prioridad para no sobrescribir un
  /// toggle offline que todavía no llegó a Firestore.
  Future<int> pullServerMenuStatus() async {
    if (!_webSyncEnabled || _serverUrl.isEmpty || _pullingServerMenuStatuses) {
      return 0;
    }
    _pullingServerMenuStatuses = true;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(
        Uri.parse('$_serverUrl/api/menu/status'),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        return 0;
      }
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
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
      client.close(force: true);
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
    };
    unawaited(_persistPendingIngredientStocks());
    if (_webSyncEnabled) unawaited(_flushPendingIngredientPatches());
  }

  Future<bool> _pushIngredientPatchToServer(
    String ingredientId,
    Map<String, dynamic> patch,
  ) async {
    if (_serverUrl.isEmpty) return false;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.patchUrl(
        Uri.parse(
          '$_serverUrl/api/ingredients/${Uri.encodeComponent(ingredientId)}',
        ),
      );
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(jsonEncode(patch));
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> _deleteIngredientOnServer(String ingredientId) async {
    if (_serverUrl.isEmpty) return false;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.deleteUrl(
        Uri.parse(
          '$_serverUrl/api/ingredients/${Uri.encodeComponent(ingredientId)}',
        ),
      );
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
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
    if (_serverUrl.isEmpty) return 0;
    String token;
    try {
      token = await _authService.getIdToken();
    } on AuthException {
      _markNeedsFirebaseReLogin();
      return 0;
    }
    if (token.isEmpty) return 0;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(
        Uri.parse('$_serverUrl/api/inventory-losses'),
      );
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.add(utf8.encode(jsonEncode(loss.toWebJson())));
      final response = await request.close();
      final status = response.statusCode;
      await response.drain<void>();
      return status;
    } catch (_) {
      return 0;
    } finally {
      client.close(force: true);
    }
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
                  'inventory-losses/${loss.id}-${DateTime.now().millisecondsSinceEpoch}.$fileName',
              maxBytes: 6 * 1024 * 1024,
            );
          } catch (_) {
            // Sin foto subida no se envía la pérdida: se reintenta en conjunto.
            continue;
          }
        }

        final payload = loss.copyWith(photoUrl: photoUrl);
        final status = await _pushInventoryLossToServer(payload);
        if (status == 401 || status == 403) {
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
    if (_pullingInventoryLosses ||
        !_webSyncEnabled ||
        !isOnline ||
        _serverUrl.isEmpty) {
      return false;
    }
    _pullingInventoryLosses = true;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      String token;
      try {
        token = await _authService.getIdToken();
      } on AuthException {
        _markNeedsFirebaseReLogin();
        return false;
      }
      final request = await client.getUrl(
        Uri.parse('$_serverUrl/api/inventory-losses'),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close();
      if (response.statusCode == 401 || response.statusCode == 403) {
        await response.drain<void>();
        _markNeedsFirebaseReLogin();
        return false;
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        return false;
      }
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
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

      final changed = merged.length != _inventoryLosses.length ||
          _inventoryLosses.asMap().entries.any(
                (entry) =>
                    entry.key >= merged.length ||
                    entry.value != merged[entry.key],
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
      client.close(force: true);
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
      if (ingredient == null) continue;
      final servings = ingredient.stock <= 0
          ? 0
          : (ingredient.stock / line.quantity).floor();
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
    if (!_webSyncEnabled || _serverUrl.isEmpty || _pullingServerIngredients) {
      return 0;
    }
    _pullingServerIngredients = true;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(
        Uri.parse('$_serverUrl/api/ingredients'),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        return 0;
      }
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> || decoded['configured'] == false) {
        return 0;
      }
      final rawList = decoded['ingredients'];
      if (rawList is! List) return 0;

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
      return changes;
    } catch (_) {
      return 0;
    } finally {
      _pullingServerIngredients = false;
      client.close(force: true);
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
      if (ingredient == null) continue;
      if (line.quantity <= 0) continue;
      final alreadyReserved = reserved[line.ingredientId] ?? 0;
      final available = ingredient.stock - alreadyReserved;
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
      if (ingredient == null) continue;
      if (entry.value > ingredient.stock + 0.0001) {
        final name = ingredient.name;
        throw ArgumentError(
          'No hay suficiente "$name" en inventario para preparar la cantidad solicitada.',
        );
      }
    }
  }

  /// Pendiente y cancelado no consumen insumos; los estados intermedios y
  /// finales sí. Se usa tanto en pedidos locales como en pedidos web importados.
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
    await _persistItems();
    notifyListeners();
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

    // El pedido nace en Pendiente y aún no descuenta insumos; el descuento se
    // hace al avanzar a un estado superior (updateOrderStatus).
    final savedOrder = _orders[0];
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
    if (order.source != 'web') {
      // Los pedidos de la web los descuenta la propia web al recibir el PATCH;
      // descontar también aquí duplicaría el consumo en Firestore.
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
    if (order.source != 'web') {
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
              '${p.method.label} ${formatCop(p.amount)}${p.note.trim().isNotEmpty ? ' (${p.note.trim()})' : ''}',
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
    if (wasDeducted && existing.source != 'web') {
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

    if (updated.inventoryDeducted && existing.source != 'web') {
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
    if (order.inventoryDeducted && order.source != 'web') {
      // Descontar solo los insumos de las líneas agregadas. Los pedidos web
      // los descuenta la web; las ediciones de ítems aún no se reenvían.
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
    if (_serverUrl.isEmpty) return 0;
    String token;
    try {
      token = await _authService.getIdToken();
    } on AuthException {
      _markNeedsFirebaseReLogin();
      return 0;
    }
    if (token.isEmpty) return 0;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.patchUrl(
        Uri.parse('$_serverUrl/api/restaurant/config'),
      );
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.add(
        utf8.encode(
          jsonEncode({
            ...appearance.toJson(),
            ...?settingsPatch,
          }),
        ),
      );
      final response = await request.close();
      final statusCode = response.statusCode;
      await response.drain<void>();
      return statusCode;
    } catch (_) {
      return 0;
    } finally {
      client.close(force: true);
    }
  }

  /// Vacía la cola offline de configuración cuando la web confirma el cambio.
  /// En 401/403 conserva la cola y pide un nuevo inicio de sesión Firebase.
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
      if (status == 401 || status == 403) {
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
    if (_pullingRestaurantConfig || _serverUrl.isEmpty) return false;
    _pullingRestaurantConfig = true;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(
        Uri.parse('$_serverUrl/api/restaurant/config'),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode == 401 || response.statusCode == 403) {
        await response.drain<void>();
        _markNeedsFirebaseReLogin();
        return false;
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        return false;
      }
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> || decoded['configured'] == false) {
        return false;
      }
      final rawConfig = decoded['config'];
      if (rawConfig is! Map<String, dynamic>) return false;
      final remote = RestaurantAppearance.fromJson(rawConfig);
      final remoteSettings =
          RestaurantSettings.fromWebConfig(rawConfig, _settings);
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
        changed = true;
      }
      if (changed) notifyListeners();
      return changed;
    } catch (_) {
      return false;
    } finally {
      _pullingRestaurantConfig = false;
      client.close(force: true);
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

  List<Order> paidOrdersInRange(DateTime start, DateTime end) => paidOrders
      .where((order) {
        final paidAt = order.paidAtOrFallback;
        return !paidAt.isBefore(start) && !paidAt.isAfter(end);
      })
      .toList()
        ..sort((a, b) =>
            b.paidAtOrFallback.compareTo(a.paidAtOrFallback));

  List<Order> paidOrdersForShift(CashShift shift) {
    final end = shift.closedAt ?? DateTime.now();
    if (!end.isAfter(shift.openedAt)) {
      return paidOrdersInRange(shift.openedAt, shift.openedAt);
    }
    return paidOrdersInRange(shift.openedAt, end);
  }

  DateTime _bucketStart(DateTime value, SalesBucket bucket) => switch (bucket) {
        SalesBucket.hour => DateTime(value.year, value.month, value.day, value.hour),
        SalesBucket.day => DateTime(value.year, value.month, value.day),
        SalesBucket.week => DateTime(value.year, value.month, value.day)
            .subtract(Duration(days: value.weekday - 1)),
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
      final total = paidOrdersInRange(effectiveStart, bucketEnd)
          .fold<double>(0, (sum, order) => sum + order.total);
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
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    return salesInRange(start: start, end: now, bucket: SalesBucket.day);
  }

  List<ProductSales> topProducts({
    int limit = 5,
    Iterable<Order>? orders,
  }) {
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

  Map<PaymentMethod, double> salesByPaymentMethodFor(
    Iterable<Order> orders,
  ) {
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
        _pendingCashShiftClosures.isEmpty ||
        _serverUrl.isEmpty) {
      return;
    }
    _flushingCashShifts = true;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final snapshot = Map<String, Map<String, dynamic>>.fromEntries(
        _pendingCashShiftClosures.entries.map(
          (entry) => MapEntry(
            entry.key,
            Map<String, dynamic>.from(entry.value),
          ),
        ),
      );
      for (final entry in snapshot.entries) {
        final request = await client.postUrl(
          Uri.parse('$_serverUrl/api/cash-shifts/close'),
        );
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.write(jsonEncode({'shift': entry.value}));
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }
        final body = await utf8.decoder.bind(response).join();
        try {
          final decoded = jsonDecode(body);
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
      client.close(force: true);
    }
  }

  /// Baja el turno abierto y el historial publicados por la web. Los cierres
  /// pendientes ganan para no sobrescribir un cierre hecho sin conexión.
  Future<void> pullCashShifts() async {
    if (!_webSyncEnabled ||
        !isOnline ||
        _serverUrl.isEmpty ||
        _pullingCashShifts) {
      return;
    }
    _pullingCashShifts = true;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(
        Uri.parse('$_serverUrl/api/cash-shifts'),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(await utf8.decoder.bind(response).join());
      if (decoded is! Map<String, dynamic>) return;
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
    } catch (_) {
      // El estado local sigue siendo válido; se reintenta en el próximo pull.
    } finally {
      _pullingCashShifts = false;
      client.close(force: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Utilidades
  // ---------------------------------------------------------------------------

  Future<void> resetDemoData() async {
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
    await _prefs.remove(_kPendingMenuStatuses);
    await _prefs.remove(_kPendingIngredientStocks);
    await _prefs.remove(_kActiveCashShift);
    await _prefs.remove(_kCashShifts);
    await _prefs.remove(_kPendingCashShiftClosures);
    await _prefs.remove(_kAppearance);
    await _prefs.remove(_kPendingRestaurantConfig);
    await _prefs.remove(_kPendingConfigPatch);
    await _prefs.remove(_kPendingFeaturedItems);
    _pendingMenuStatuses = {};
    _pendingIngredientStocks = {};
    _pendingCashShiftClosures = {};
    _closedShifts = [];
    _activeShift = _newCashShift(DateTime.now());
    _categories = [...SeedData.categories];
    _items = SeedData.menuItemsWithRecipes();
    _ingredients = [...SeedData.ingredients];
    _orders = SeedData.orders()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _inventoryLosses = [];
    _tables = SeedData.tables();
    _settings = SeedData.settings;
    _restaurantAppearance = RestaurantAppearance.defaults;
    _pendingRestaurantConfig = null;
    _pendingConfigPatch = null;
    _pendingFeaturedItems = {};
    _currentUser = null;
    _users = [...SeedData.users];
    _lastSync = null;
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
    await _prefs.setString(_kActiveCashShift, jsonEncode(_activeShift.toJson()));
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
