// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import '../models/category.dart';
import '../models/customer.dart';
import '../models/ingredient.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../models/restaurant_settings.dart';
import '../models/restaurant_table.dart';
import '../models/role.dart';
import '../models/web_visit.dart';
import '../services/connectivity_service.dart';
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
    required List<RestaurantTable> tables,
    required List<CustomerRecord> customers,
    required List<WebVisit> webVisits,
    required Map<String, String> pendingMenuStatuses,
    required RestaurantSettings settings,
    required AppUser? currentUser,
    required DateTime? lastSync,
    required String serverUrl,
    required bool webSyncEnabled,
  })  : _prefs = prefs,
        _connectivity = connectivity,
        _ownsConnectivity = ownsConnectivity,
        _categories = categories,
        _items = items,
        _ingredients = ingredients,
        _orders = orders,
        _tables = tables,
        _customers = customers,
        _webVisits = webVisits,
        _pendingMenuStatuses = pendingMenuStatuses,
        _settings = settings,
        _currentUser = currentUser,
        _lastSync = lastSync,
        _serverUrl = serverUrl,
        _webSyncEnabled = webSyncEnabled {
    _connectivity.online.addListener(_onConnectivityChanged);
  }

  static const _kCategories = 'rm_categories_v1';
  static const _kItems = 'rm_menu_items_v1';
  static const _kIngredients = 'rm_ingredients_v1';
  static const _kOrders = 'rm_orders_v1';
  static const _kTables = 'rm_tables_v1';
  static const _kSettings = 'rm_settings_v1';
  static const _kSession = 'rm_session_v1';
  static const _kLastSync = 'rm_last_sync_v1';
  static const _kServerUrl = 'rm_server_url_v1';
  static const _kCustomers = 'rm_customers_v1';
  static const _kWebVisits = 'rm_web_visits_v1';
  static const _kPendingMenuStatuses = 'rm_pending_menu_statuses_v1';

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
  List<RestaurantTable> _tables;
  List<CustomerRecord> _customers;
  List<WebVisit> _webVisits;
  RestaurantSettings _settings;
  AppUser? _currentUser;
  DateTime? _lastSync;
  String _serverUrl;
  bool _syncing = false;
  bool _pullingServerOrders = false;
  bool _flushingMenuStatuses = false;
  final bool _webSyncEnabled;
  Map<String, String> _pendingMenuStatuses = {};
  Future<void>? _syncFuture;
  Timer? _webPollTimer;

  static Future<RestaurantRepository> load({
    ConnectivityService? connectivity,
    bool watchConnectivity = true,
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
    final items = storedItems.isEmpty
        ? seedItems
        : _hydrateSeedExtras(storedItems, seedItems);
    final ingredients = _readList<Ingredient>(
      prefs,
      _kIngredients,
      Ingredient.fromJson,
    );
    final orders = _readList<Order>(prefs, _kOrders, Order.fromJson);
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
    final currentUser = sessionRaw == null
        ? null
        : AppUser.fromJson(jsonDecode(sessionRaw) as Map<String, dynamic>);
    final lastSyncRaw = prefs.getString(_kLastSync);
    final lastSync =
        lastSyncRaw == null ? null : DateTime.tryParse(lastSyncRaw);
    final serverUrl = _normalizeServerUrl(
      prefs.getString(_kServerUrl) ?? defaultServerUrl,
    );
    final customers = _readList(
      prefs,
      _kCustomers,
      CustomerRecord.fromJson,
    );
    final webVisits = _readList(prefs, _kWebVisits, WebVisit.fromJson);
    final pendingMenuStatuses = _readPendingMenuStatuses(prefs);

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
            )
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      tables: tables.isEmpty ? SeedData.tables() : tables,
      customers: customers,
      webVisits: webVisits,
      pendingMenuStatuses: pendingMenuStatuses,
      settings: settings,
      currentUser: currentUser,
      lastSync: lastSync,
      serverUrl: serverUrl,
      webSyncEnabled: watchConnectivity,
    );

    repository._rebuildCustomersFromOrders(persist: customers.isEmpty);

    if (categories.isEmpty) await repository._persistCategories();
    if (storedItems.isEmpty || !_sameItemExtras(storedItems, items)) {
      await repository._persistItems();
    }
    if (ingredients.isEmpty) await repository._persistIngredients();
    if (orders.isEmpty) await repository._persistOrders();
    if (tables.isEmpty) await repository._persistTables();
    if (customers.isEmpty) await repository._persistCustomers();

    if (watchConnectivity) {
      repository._startWebPolling();
    }

    return repository;
  }

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
        recipeSteps:
            item.recipeSteps.isEmpty ? seed.recipeSteps : item.recipeSteps,
        ingredients:
            item.ingredients.isEmpty ? seed.ingredients : item.ingredients,
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
      return order.copyWith(items: items, auditLog: audit);
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
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Map<String, String> _readPendingMenuStatuses(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getString(_kPendingMenuStatuses);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      return Map.fromEntries(
        decoded.entries
            .where(
              (entry) =>
                  entry.value is String &&
                  (entry.value == 'available' || entry.value == 'unavailable'),
            )
            .map((entry) => MapEntry(entry.key, entry.value as String)),
      );
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

  bool login(String email, String password) {
    final normalized = email.trim().toLowerCase();
    final matches =
        SeedData.users.where((user) => user.email.toLowerCase() == normalized);
    if (matches.isEmpty || password != SeedData.demoPassword) {
      return false;
    }
    _currentUser = matches.first;
    _prefs.setString(_kSession, jsonEncode(_currentUser!.toJson()));
    notifyListeners();
    return true;
  }

  void loginAs(UserRole role) {
    final matches = SeedData.users.where((user) => user.role == role);
    if (matches.isEmpty) return;
    _currentUser = matches.first;
    _prefs.setString(_kSession, jsonEncode(_currentUser!.toJson()));
    notifyListeners();
  }

  void logout() {
    _currentUser = null;
    _prefs.remove(_kSession);
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
    if (isOnline && pendingSyncCount > 0) {
      syncPendingOrders();
    }
    if (isOnline && _webSyncEnabled) {
      unawaited(_flushPendingMenuStatuses());
    }
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
                          detail: 'Enviado al servidor al restablecerse la conexión',
                        ),
                      ],
                    )
                  : order,
            )
            .toList();
        await _persistOrders();
      }
      _lastSync = DateTime.now();
      _prefs.setString(_kLastSync, _lastSync!.toIso8601String());
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

  void _startWebPolling() {
    _webPollTimer?.cancel();
    _webPollTimer = Timer.periodic(_pollInterval, (_) {
      if (isOnline) {
        unawaited(pullServerOrders());
        unawaited(pullServerCustomers());
        unawaited(pullServerVisits());
        unawaited(pullServerMenuStatus());
        unawaited(_flushPendingMenuStatuses());
      }
    });
    unawaited(pullServerOrders());
    unawaited(pullServerCustomers());
    unawaited(pullServerVisits());
    unawaited(pullServerMenuStatus());
    unawaited(_flushPendingMenuStatuses());
  }

  /// Prueba la conexión con la API de la web pública.
  Future<bool> testServerConnection() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request =
          await client.getUrl(Uri.parse('$_serverUrl/api/health'));
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
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request =
          await client.getUrl(Uri.parse('$_serverUrl/api/orders'));
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
      var updatedExisting = false;

      for (final raw in rawList) {
        if (raw is! Map<String, dynamic>) continue;
        final remote = Order.fromJson({
          ...raw,
          'source': 'web',
          'synced': true,
          'auditLog': raw['auditLog'] ??
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
          imported.add(remote.copyWith(
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
          ));
          continue;
        }

        final index = _orders.indexWhere((o) => o.id == remote.id);
        if (index < 0) continue;
        final local = _orders[index];
        if (local.source != 'web') continue;

        final statusChanged = local.status != remote.status ||
            local.paymentStatus != remote.paymentStatus;
        if (!statusChanged) continue;

        final audit = [...local.auditLog];
        if (local.status != remote.status) {
          audit.add(OrderAuditEntry(
            action: 'Estado actualizado desde la web',
            timestamp: remote.updatedAt,
            actorName: 'Web pública',
            detail: '${local.status.label} → ${remote.status.label}',
          ));
        }
        if (local.paymentStatus != remote.paymentStatus) {
          audit.add(OrderAuditEntry(
            action: 'Pago actualizado desde la web',
            timestamp: remote.updatedAt,
            actorName: 'Web pública',
            detail:
                '${local.paymentStatus.label} → ${remote.paymentStatus.label}',
          ));
        }
        _orders[index] = local.copyWith(
          status: remote.status,
          paymentStatus: remote.paymentStatus,
          deliveryAddress: remote.deliveryAddress,
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
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.patchUrl(
        Uri.parse('$_serverUrl/api/orders/${Uri.encodeComponent(order.id)}'),
      );
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(jsonEncode({
        'status': order.status.name,
        'paymentStatus': order.paymentStatus.name,
      }));
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
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(Uri.parse('$_serverUrl/api/customers'));
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
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(Uri.parse('$_serverUrl/api/customers'));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        return;
      }
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      final rawList = decoded is Map<String, dynamic> ? decoded['customers'] : null;
      if (rawList is! List) return;
      var changed = false;
      for (final raw in rawList) {
        if (raw is! Map<String, dynamic>) continue;
        final remote = CustomerRecord.fromJson(raw);
        if (!remote.hasPhone) continue;
        final idx = _customers.indexWhere((c) => c.normalizedPhone == remote.normalizedPhone);
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
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
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
      final rawList = decoded is Map<String, dynamic> ? decoded['visits'] : null;
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

  Future<bool> _pushMenuItemStatusToServer(String itemId, String status) async {
    if (_serverUrl.isEmpty) return false;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.patchUrl(
        Uri.parse('$_serverUrl/api/menu/${Uri.encodeComponent(itemId)}'),
      );
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(jsonEncode({'status': status}));
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Envía a la web los cambios de disponibilidad hechos sin conexión.
  Future<void> _flushPendingMenuStatuses() async {
    if (!_webSyncEnabled || !isOnline || _flushingMenuStatuses) return;
    if (_pendingMenuStatuses.isEmpty) return;
    _flushingMenuStatuses = true;
    try {
      final snapshot = Map<String, String>.from(_pendingMenuStatuses);
      for (final entry in snapshot.entries) {
        final sent = await _pushMenuItemStatusToServer(entry.key, entry.value);
        if (sent && _pendingMenuStatuses[entry.key] == entry.value) {
          _pendingMenuStatuses.remove(entry.key);
          await _persistPendingMenuStatuses();
        }
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
    if (!_webSyncEnabled || _serverUrl.isEmpty) return 0;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request =
          await client.getUrl(Uri.parse('$_serverUrl/api/menu/status'));
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
        if (_items[index].status == remoteStatus) continue;
        _items[index] = _items[index].copyWith(status: remoteStatus);
        changes++;
      }
      if (changes > 0) {
        await _persistItems();
        notifyListeners();
      }
      return changes;
    } catch (_) {
      return 0;
    } finally {
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
    await _persistIngredients();
    notifyListeners();
    return ingredient;
  }

  Future<void> upsertIngredient(Ingredient ingredient) async {
    final index =
        _ingredients.indexWhere((entry) => entry.id == ingredient.id);
    if (index >= 0) {
      _ingredients[index] = ingredient;
    } else {
      _ingredients.add(ingredient);
    }
    await _persistIngredients();
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
    await _persistIngredients();
    await _persistItems();
    notifyListeners();
  }

  Future<void> adjustIngredientStock(String ingredientId, double delta) async {
    final index =
        _ingredients.indexWhere((ingredient) => ingredient.id == ingredientId);
    if (index < 0) return;
    final ingredient = _ingredients[index];
    final next = ingredient.stock + delta;
    _ingredients[index] = ingredient.copyWith(stock: next < 0 ? 0 : next);
    await _persistIngredients();
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

  Future<void> _deductInventory(Order order) async {
    final consumption = consumptionForOrder(order);
    if (consumption.isEmpty) return;
    for (final entry in consumption.entries) {
      final index = _ingredients
          .indexWhere((ingredient) => ingredient.id == entry.key);
      if (index < 0) continue;
      final ingredient = _ingredients[index];
      final next = ingredient.stock - entry.value;
      _ingredients[index] =
          ingredient.copyWith(stock: next < 0 ? 0 : next);
    }
    await _persistIngredients();
  }

  Future<void> _restoreInventory(Order order) async {
    final consumption = consumptionForOrder(order);
    if (consumption.isEmpty) return;
    for (final entry in consumption.entries) {
      final index = _ingredients
          .indexWhere((ingredient) => ingredient.id == entry.key);
      if (index < 0) continue;
      final ingredient = _ingredients[index];
      _ingredients[index] =
          ingredient.copyWith(stock: ingredient.stock + entry.value);
    }
    await _persistIngredients();
  }

  // ---------------------------------------------------------------------------
  // Menú
  // ---------------------------------------------------------------------------

  List<Category> get categories =>
      [..._categories]..sort((a, b) => a.order.compareTo(b.order));

  List<MenuItem> get menuItems => List.unmodifiable(_items);

  bool isMenuItemOutOfStockByIngredients(MenuItem item) {
    if (item.recipe.isEmpty) return false;
    for (final line in item.recipe) {
      final ingredient = ingredientById(line.ingredientId);
      if (ingredient == null) continue;
      if (ingredient.stock <= 0) return true;
    }
    return false;
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
    final next = item.status == MenuItemStatus.unavailable
        ? MenuItemStatus.available
        : MenuItemStatus.unavailable;
    _items[index] = item.copyWith(status: next);
    await _persistItems();

    // La web pública lee Firestore: el toggle debe llegar al catálogo
    // compartido, con cola local para cambios hechos offline.
    _pendingMenuStatuses[itemId] = next.name;
    await _persistPendingMenuStatuses();
    notifyListeners();
    if (_webSyncEnabled) unawaited(_flushPendingMenuStatuses());
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
      .where((order) =>
          order.paymentStatus == PaymentStatus.pending &&
          order.status != OrderStatus.cancelled)
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
    final subtotal =
        orderItems.fold<double>(0, (sum, item) => sum + item.subtotal);
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

    if (order.tableNumber != null) {
      await _setTableForOrder(order.tableNumber!, order.id);
    }
    _upsertCustomerFromOrder(order);
    await _persistOrders();
    await _persistCustomers();
    notifyListeners();
    return order;
  }

  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    final index = _orders.indexWhere((order) => order.id == orderId);
    if (index < 0) return;
    final order = _orders[index];
    final now = DateTime.now();
    final entry = _audit(
      status == OrderStatus.cancelled ? 'Pedido cancelado' : 'Estado actualizado',
      detail: '${order.status.label} → ${status.label}',
    );
    _orders[index] = order.copyWith(
      status: status,
      updatedAt: now,
      updatedBy: _currentUser?.id,
      updatedByName: _currentUser?.name,
      auditLog: [...order.auditLog, entry],
    );
    if ((status == OrderStatus.preparing ||
            status == OrderStatus.ready ||
            status == OrderStatus.sent ||
            status == OrderStatus.delivered) &&
        !order.inventoryDeducted) {
      await _deductInventory(order);
      _orders[index] = _orders[index].copyWith(
        inventoryDeducted: true,
        auditLog: [
          ..._orders[index].auditLog,
          _audit('Inventario descontado', detail: 'Descuento por cambio a ${status.label}'),
        ],
      );
    }
    if (status == OrderStatus.cancelled) {
      if (order.inventoryDeducted) {
        await _restoreInventory(order);
        _orders[index] = _orders[index].copyWith(
          auditLog: [
            ..._orders[index].auditLog,
            _audit('Inventario repuesto', detail: 'Reposición por cancelación'),
          ],
        );
      }
      if (order.tableNumber != null) {
        await _freeTableByNumber(order.tableNumber!);
      }
    }
    _upsertCustomerFromOrder(_orders[index]);
    await _persistOrders();
    await _persistCustomers();
    notifyListeners();
    if (_orders[index].source == 'web') {
      await _pushOrderUpdateToServer(_orders[index]);
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
    if (!order.inventoryDeducted) {
      await _deductInventory(order);
      audit.add(_audit('Inventario descontado', detail: 'Descuento al cobrar'));
    }
    final resolvedPayments = (payments == null || payments.isEmpty)
        ? [OrderPayment(method: order.paymentMethod, amount: order.total)]
        : payments;
    final paymentDetail = resolvedPayments
        .map((p) =>
            '${p.method.label} ${formatCop(p.amount)}${p.note.trim().isNotEmpty ? ' (${p.note.trim()})' : ''}')
        .join(' + ');
    audit.add(_audit(
      'Pago registrado',
      detail: '$paymentDetail · Total ${formatCop(order.total)}',
    ));
    if (order.status.isActive) {
      audit.add(_audit('Estado actualizado', detail: '${order.status.label} → Entregado'));
    }
    final resolvedStatus = order.status == OrderStatus.cancelled
        ? OrderStatus.cancelled
        : order.type == OrderType.delivery
            ? OrderStatus.sent
            : OrderStatus.delivered;
    _orders[index] = order.copyWith(
      paymentStatus: PaymentStatus.paid,
      paymentMethod: resolvedPayments.first.method,
      payments: resolvedPayments,
      status: resolvedStatus,
      updatedAt: now,
      inventoryDeducted: true,
      updatedBy: _currentUser?.id,
      updatedByName: _currentUser?.name,
      auditLog: audit,
    );
    if (order.tableNumber != null) {
      final otherActive = _orders.any((o) =>
          o.id != order.id &&
          o.tableNumber == order.tableNumber &&
          o.status.isActive);
      if (!otherActive) {
        await _freeTableByNumber(order.tableNumber!);
      } else {
        final other = _orders.firstWhere((o) =>
            o.id != order.id &&
            o.tableNumber == order.tableNumber &&
            o.status.isActive);
        await _setTableForOrder(order.tableNumber!, other.id);
      }
    }
    await _persistOrders();
    notifyListeners();
    if (_orders[index].source == 'web') {
      await _pushOrderUpdateToServer(_orders[index]);
    }
  }

  /// Busca pedidos en preparación para una mesa específica.
  List<Order> preparingOrdersForTable(int tableNumber) {
    return _orders
        .where((o) =>
            o.tableNumber == tableNumber && o.status == OrderStatus.preparing)
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
        .where((o) =>
            o.tableNumber == tableNumber &&
            (includeCancelled || o.status != OrderStatus.cancelled) &&
            (!activeOnly || o.status.isActive))
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
        .where((o) =>
            o.tableNumber == tableNumber &&
            o.paymentStatus == PaymentStatus.pending &&
            o.status != OrderStatus.cancelled)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Total pendiente de pago para una mesa.
  double tablePendingTotal(int tableNumber) {
    return payableTableOrders(tableNumber)
        .fold(0, (sum, o) => sum + o.total);
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
          deltaLines.add(CartLine(
            menuItemId: line.menuItemId,
            name: line.name,
            price: line.price,
            quantity: diff,
            emoji: line.emoji,
            imageUrl: line.imageUrl,
          ));
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
    final subtotal =
        orderItems.fold<double>(0, (sum, item) => sum + item.subtotal);
    final nextTable = type == OrderType.table ? tableNumber : null;

    var audit = [...existing.auditLog];
    if (wasDeducted) {
      await _restoreInventory(existing);
      audit.add(_audit('Inventario repuesto', detail: 'Reposición antes de editar pedido'));
    }

    audit.add(_audit(
      'Pedido editado',
      detail:
          '${orderItems.fold<int>(0, (s, i) => s + i.quantity)} uds · ${formatCop(subtotal)}',
    ));

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
      inventoryDeducted: wasDeducted ||
          existing.status == OrderStatus.preparing ||
          existing.status == OrderStatus.ready ||
          existing.status == OrderStatus.delivered,
      updatedBy: _currentUser?.id,
      updatedByName: _currentUser?.name,
      auditLog: audit,
    );

    if (updated.inventoryDeducted) {
      await _deductInventory(updated);
      audit.add(_audit('Inventario descontado', detail: 'Descuento tras editar pedido'));
    }

    _orders[index] = updated.copyWith(auditLog: audit);

    if (existing.tableNumber != nextTable) {
      if (existing.tableNumber != null) {
        final otherActive = _orders.any((o) =>
            o.id != updated.id &&
            o.tableNumber == existing.tableNumber &&
            o.status.isActive);
        if (!otherActive) {
          await _freeTableByNumber(existing.tableNumber!);
        } else {
          final other = _orders.firstWhere((o) =>
              o.id != updated.id &&
              o.tableNumber == existing.tableNumber &&
              o.status.isActive);
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
          imageUrl: line.imageUrl.isNotEmpty ? line.imageUrl : (prev?.imageUrl ?? ''),
        );
      }
      _validateCartStock(combined.values.toList());
    }
    final newItems = [...order.items];
    final addedNames = <String>[];
    for (final line in lines) {
      final existing = newItems.indexWhere((i) => i.menuItemId == line.menuItemId);
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
        newItems.add(OrderItem(
          menuItemId: line.menuItemId,
          name: line.name,
          price: line.price,
          quantity: line.quantity,
          emoji: line.emoji,
          imageUrl: line.imageUrl,
        ));
      }
    }
    final subtotal = newItems.fold<double>(0, (s, i) => s + i.subtotal);
    var audit = [
      ...order.auditLog,
      _audit('Productos agregados', detail: addedNames.join(', ')),
    ];
    var inventoryDeducted = order.inventoryDeducted;
    if (order.inventoryDeducted) {
      // Descontar solo los insumos de las líneas agregadas.
      final deltaOrder = Order(
        id: order.id,
        code: order.code,
        customerName: order.customerName,
        customerPhone: order.customerPhone,
        type: order.type,
        tableNumber: order.tableNumber,
        items: lines
            .map((l) => OrderItem(
                  menuItemId: l.menuItemId,
                  name: l.name,
                  price: l.price,
                  quantity: l.quantity,
                  emoji: l.emoji,
                  imageUrl: l.imageUrl,
                ))
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
      audit.add(_audit('Inventario descontado', detail: 'Descuento por productos agregados'));
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
        .where((order) =>
            order.tableNumber == tableNumber &&
            order.paymentStatus == PaymentStatus.pending &&
            order.status != OrderStatus.cancelled)
        .toList();
    if (group.isEmpty) return;
    final total = group.fold<double>(0, (s, o) => s + o.total);
    for (final order in group) {
      List<OrderPayment>? orderPayments;
      if (payments != null && payments.isNotEmpty && total > 0) {
        final ratio = order.total / total;
        orderPayments = payments
            .map((p) => OrderPayment(
                  method: p.method,
                  amount: p.amount * ratio,
                  note: p.note,
                ))
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
    final index =
        _tables.indexWhere((table) => table.number == tableNumber);
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
    final index =
        _tables.indexWhere((table) => table.number == tableNumber);
    if (index < 0) return;
    _tables[index] = _tables[index].copyWith(
      status: TableStatus.esperandoPedido,
      currentOrderId: orderId,
    );
    await _persistTables();
  }

  Future<void> _freeTableByNumber(int tableNumber) async {
    final index =
        _tables.indexWhere((table) => table.number == tableNumber);
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

  Future<void> updateSettings(RestaurantSettings settings) async {
    _settings = settings;
    await _prefs.setString(_kSettings, jsonEncode(settings.toJson()));
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Métricas para dashboards y reportes
  // ---------------------------------------------------------------------------

  List<Order> get todayOrders => _orders
      .where((order) => isSameDay(order.createdAt, DateTime.now()))
      .toList();

  double get todaySales => todayOrders
      .where((order) =>
          order.paymentStatus == PaymentStatus.paid &&
          order.status != OrderStatus.cancelled)
      .fold(0, (sum, order) => sum + order.total);

  double get pendingPayments => _orders
      .where((order) =>
          order.paymentStatus == PaymentStatus.pending &&
          order.status != OrderStatus.cancelled)
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

  List<DailySales> salesByDay({int days = 7}) {
    final now = DateTime.now();
    return List.generate(days, (index) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: days - 1 - index));
      final total = _orders
          .where((order) =>
              order.paymentStatus == PaymentStatus.paid &&
              order.status != OrderStatus.cancelled &&
              isSameDay(order.createdAt, day))
          .fold<double>(0, (sum, order) => sum + order.total);
      return DailySales(day: day, total: total);
    });
  }

  List<ProductSales> topProducts({int limit = 5}) {
    final Map<String, ({int quantity, double total})> accumulator = {};
    for (final order in _orders) {
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
        .map((entry) => ProductSales(
              name: entry.key,
              quantity: entry.value.quantity,
              total: entry.value.total,
            ))
        .toList();
  }

  List<CustomerSummary> get customerSummaries {
    final map = <String, _CustomerAgg>{};
    for (final order in _orders) {
      final phone = order.customerPhone.replaceAll(RegExp(r'\D'), '');
      final key = phone.isNotEmpty ? phone : 'name:${order.customerName.toLowerCase().trim()}';
      if (key.isEmpty || key == 'name:') continue;
      final agg = map.putIfAbsent(key, () => _CustomerAgg(
            phone: order.customerPhone.trim(),
            name: order.customerName.trim(),
          ));
      if (order.customerName.trim().length >= 2) agg.name = order.customerName.trim();
      if (order.customerPhone.trim().isNotEmpty) agg.phone = order.customerPhone.trim();
      if (order.deliveryAddress.trim().isNotEmpty) agg.address = order.deliveryAddress.trim();
      agg.orderCount += 1;
      if (order.status != OrderStatus.cancelled) {
        agg.totalSpent += order.total;
      }
      if (order.createdAt.isAfter(agg.lastOrderAt)) agg.lastOrderAt = order.createdAt;
      if (order.createdAt.isBefore(agg.firstOrderAt)) agg.firstOrderAt = order.createdAt;
      agg.lastType = order.type;
    }
    final list = map.values
        .map((a) => CustomerSummary(
              name: a.name,
              phone: a.phone,
              address: a.address,
              orderCount: a.orderCount,
              totalSpent: a.totalSpent,
              firstOrderAt: a.firstOrderAt,
              lastOrderAt: a.lastOrderAt,
              lastType: a.lastType,
            ))
        .toList();
    list.sort((a, b) => b.lastOrderAt.compareTo(a.lastOrderAt));
    return list;
  }

  Map<PaymentMethod, double> get salesByPaymentMethod {
    final result = <PaymentMethod, double>{};
    for (final order in _orders) {
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

  // ---------------------------------------------------------------------------
  // Utilidades
  // ---------------------------------------------------------------------------

  Future<void> resetDemoData() async {
    await _prefs.remove(_kCategories);
    await _prefs.remove(_kItems);
    await _prefs.remove(_kIngredients);
    await _prefs.remove(_kOrders);
    await _prefs.remove(_kTables);
    await _prefs.remove(_kSettings);
    await _prefs.remove(_kSession);
    await _prefs.remove(_kLastSync);
    await _prefs.remove(_kPendingMenuStatuses);
    _pendingMenuStatuses = {};
    _categories = [...SeedData.categories];
    _items = SeedData.menuItemsWithRecipes();
    _ingredients = [...SeedData.ingredients];
    _orders = SeedData.orders()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _tables = SeedData.tables();
    _settings = SeedData.settings;
    _currentUser = null;
    _lastSync = null;
    await _persistCategories();
    await _persistItems();
    await _persistIngredients();
    await _persistOrders();
    await _persistTables();
    notifyListeners();
  }

  OrderAuditEntry _audit(String action, {String detail = ''}) =>
      OrderAuditEntry(
        action: action,
        timestamp: DateTime.now(),
        actorId: _currentUser?.id,
        actorName: _currentUser?.name ?? (isOnline ? 'Sistema' : 'Sistema (offline)'),
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

  List<CustomerRecord> get crmCustomers => _customers
      .where((c) => c.hasPhone)
      .toList()
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
        key: (grouped[key]!..sort((a, b) => b.occurredAt.compareTo(a.occurredAt)))
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
      createdAt:
          first.createdAt.isBefore(current.createdAt) ? first.createdAt : current.createdAt,
      lastOrderAt:
          last.createdAt.isAfter(current.lastOrderAt) ? last.createdAt : current.lastOrderAt,
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
    final sortedOrders = [..._orders]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
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
          totalSpent: current.totalSpent +
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
