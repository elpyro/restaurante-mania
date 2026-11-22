// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import '../models/category.dart';
import '../models/ingredient.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../models/restaurant_settings.dart';
import '../models/restaurant_table.dart';
import '../models/role.dart';
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
    required RestaurantSettings settings,
    required AppUser? currentUser,
    required DateTime? lastSync,
    required String serverUrl,
  })  : _prefs = prefs,
        _connectivity = connectivity,
        _ownsConnectivity = ownsConnectivity,
        _categories = categories,
        _items = items,
        _ingredients = ingredients,
        _orders = orders,
        _tables = tables,
        _settings = settings,
        _currentUser = currentUser,
        _lastSync = lastSync,
        _serverUrl = serverUrl {
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
  RestaurantSettings _settings;
  AppUser? _currentUser;
  DateTime? _lastSync;
  String _serverUrl;
  bool _syncing = false;
  bool _pullingServerOrders = false;
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

    final repository = RestaurantRepository._(
      prefs: prefs,
      connectivity: service,
      ownsConnectivity: connectivity == null,
      categories: categories.isEmpty ? [...SeedData.categories] : categories,
      items: items,
      ingredients: ingredients.isEmpty
          ? [...SeedData.ingredients]
          : ingredients,
      orders: (orders.isEmpty ? SeedData.orders() : orders)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      tables: tables.isEmpty ? SeedData.tables() : tables,
      settings: settings,
      currentUser: currentUser,
      lastSync: lastSync,
      serverUrl: serverUrl,
    );

    if (categories.isEmpty) await repository._persistCategories();
    if (storedItems.isEmpty || !_sameItemExtras(storedItems, items)) {
      await repository._persistItems();
    }
    if (ingredients.isEmpty) await repository._persistIngredients();
    if (orders.isEmpty) await repository._persistOrders();
    if (tables.isEmpty) await repository._persistTables();

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
                  ? order.copyWith(synced: true, updatedAt: now)
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
      if (isOnline) unawaited(pullServerOrders());
    });
    unawaited(pullServerOrders());
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

      final existing = _orders.map((order) => order.id).toSet();
      final imported = <Order>[];
      for (final raw in rawList) {
        if (raw is! Map<String, dynamic>) continue;
        final order = Order.fromJson({
          ...raw,
          'source': 'web',
          'synced': true,
        });
        if (order.id.isEmpty || existing.contains(order.id)) continue;
        existing.add(order.id);
        imported.add(order);
      }
      if (imported.isEmpty) {
        _lastSync = DateTime.now();
        _prefs.setString(_kLastSync, _lastSync!.toIso8601String());
        return 0;
      }

      _orders = [...imported, ..._orders]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      for (final order in imported) {
        final table = order.tableNumber;
        if (table != null) {
          await _setTableForOrder(table, order.id);
        }
      }
      _lastSync = DateTime.now();
      _prefs.setString(_kLastSync, _lastSync!.toIso8601String());
      await _persistOrders();
      notifyListeners();
      return imported.length;
    } catch (_) {
      return 0;
    } finally {
      _pullingServerOrders = false;
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

  List<MenuItem> get availableMenuItems =>
      _items.where((item) => item.isAvailable).toList();

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
    notifyListeners();
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

  Order? orderById(String id) {
    final matches = _orders.where((order) => order.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  Future<Order> createOrder({
    required List<CartLine> lines,
    String customerName = '',
    String customerPhone = '',
    required OrderType type,
    int? tableNumber,
    required PaymentMethod paymentMethod,
    String notes = '',
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('El pedido necesita al menos un producto.');
    }
    final trimmedName = customerName.trim();
    final trimmedPhone = customerPhone.trim();
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
          ),
        )
        .toList();
    final subtotal =
        orderItems.fold<double>(0, (sum, item) => sum + item.subtotal);
    final order = Order(
      id: newId('order'),
      code: orderCode(),
      customerName: resolvedName,
      customerPhone: trimmedPhone,
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
    );
    _orders.insert(0, order);

    if (order.tableNumber != null) {
      await _setTableForOrder(order.tableNumber!, order.id);
    }
    await _persistOrders();
    notifyListeners();
    return order;
  }

  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    final index = _orders.indexWhere((order) => order.id == orderId);
    if (index < 0) return;
    final order = _orders[index];
    _orders[index] = order.copyWith(status: status, updatedAt: DateTime.now());
    if (status == OrderStatus.preparing && !order.inventoryDeducted) {
      await _deductInventory(order);
      _orders[index] = _orders[index].copyWith(inventoryDeducted: true);
    }
    if (status == OrderStatus.cancelled) {
      if (order.inventoryDeducted) {
        await _restoreInventory(order);
      }
      if (order.tableNumber != null) {
        await _freeTableByNumber(order.tableNumber!);
      }
    }
    await _persistOrders();
    notifyListeners();
  }

  Future<void> advanceOrder(String orderId) async {
    final order = orderById(orderId);
    final next = order?.status.next;
    if (next != null) await updateOrderStatus(orderId, next);
  }

  Future<void> markOrderPaid(String orderId) async {
    final index = _orders.indexWhere((order) => order.id == orderId);
    if (index < 0) return;
    final order = _orders[index];
    _orders[index] = order.copyWith(
      paymentStatus: PaymentStatus.paid,
      status: order.status == OrderStatus.cancelled
          ? OrderStatus.cancelled
          : OrderStatus.delivered,
      updatedAt: DateTime.now(),
    );
    if (order.tableNumber != null) {
      await _freeTableByNumber(order.tableNumber!);
    }
    await _persistOrders();
    notifyListeners();
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
    await _freeTableByNumber(tableNumber);
    await _persistTables();
    notifyListeners();
  }

  Future<void> _setTableForOrder(int tableNumber, String orderId) async {
    final index =
        _tables.indexWhere((table) => table.number == tableNumber);
    if (index < 0) return;
    _tables[index] = _tables[index].copyWith(
      status: TableStatus.ocupada,
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

  Map<PaymentMethod, double> get salesByPaymentMethod {
    final result = <PaymentMethod, double>{};
    for (final order in _orders) {
      if (order.paymentStatus != PaymentStatus.paid ||
          order.status == OrderStatus.cancelled) {
        continue;
      }
      result[order.paymentMethod] =
          (result[order.paymentMethod] ?? 0) + order.total;
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

  @override
  void dispose() {
    _webPollTimer?.cancel();
    _connectivity.online.removeListener(_onConnectivityChanged);
    if (_ownsConnectivity) _connectivity.dispose();
    super.dispose();
  }
}
