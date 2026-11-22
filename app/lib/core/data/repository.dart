// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import '../models/category.dart';
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
    required List<Order> orders,
    required List<RestaurantTable> tables,
    required RestaurantSettings settings,
    required AppUser? currentUser,
    required DateTime? lastSync,
  })  : _prefs = prefs,
        _connectivity = connectivity,
        _ownsConnectivity = ownsConnectivity,
        _categories = categories,
        _items = items,
        _orders = orders,
        _tables = tables,
        _settings = settings,
        _currentUser = currentUser,
        _lastSync = lastSync {
    _connectivity.online.addListener(_onConnectivityChanged);
  }

  static const _kCategories = 'rm_categories_v1';
  static const _kItems = 'rm_menu_items_v1';
  static const _kOrders = 'rm_orders_v1';
  static const _kTables = 'rm_tables_v1';
  static const _kSettings = 'rm_settings_v1';
  static const _kSession = 'rm_session_v1';
  static const _kLastSync = 'rm_last_sync_v1';

  final SharedPreferences _prefs;
  final ConnectivityService _connectivity;
  final bool _ownsConnectivity;

  List<Category> _categories;
  List<MenuItem> _items;
  List<Order> _orders;
  List<RestaurantTable> _tables;
  RestaurantSettings _settings;
  AppUser? _currentUser;
  DateTime? _lastSync;
  bool _syncing = false;
  Future<void>? _syncFuture;

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
    final items = _readList<MenuItem>(prefs, _kItems, MenuItem.fromJson);
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

    final repository = RestaurantRepository._(
      prefs: prefs,
      connectivity: service,
      ownsConnectivity: connectivity == null,
      categories: categories.isEmpty ? [...SeedData.categories] : categories,
      items: items.isEmpty ? [...SeedData.menuItems] : items,
      orders: (orders.isEmpty ? SeedData.orders() : orders)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      tables: tables.isEmpty ? SeedData.tables() : tables,
      settings: settings,
      currentUser: currentUser,
      lastSync: lastSync,
    );

    if (categories.isEmpty) await repository._persistCategories();
    if (items.isEmpty) await repository._persistItems();
    if (orders.isEmpty) await repository._persistOrders();
    if (tables.isEmpty) await repository._persistTables();

    return repository;
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
  // Menú
  // ---------------------------------------------------------------------------

  List<Category> get categories =>
      [..._categories]..sort((a, b) => a.order.compareTo(b.order));

  List<MenuItem> get menuItems => List.unmodifiable(_items);

  List<MenuItem> get availableMenuItems =>
      _items.where((item) => item.isAvailable).toList();

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
    required String customerName,
    required String customerPhone,
    required OrderType type,
    int? tableNumber,
    required PaymentMethod paymentMethod,
    String notes = '',
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('El pedido necesita al menos un producto.');
    }
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
      customerName: customerName.trim(),
      customerPhone: customerPhone.trim(),
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
    if (status == OrderStatus.cancelled && order.tableNumber != null) {
      await _freeTableByNumber(order.tableNumber!);
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
    await _prefs.remove(_kOrders);
    await _prefs.remove(_kTables);
    await _prefs.remove(_kSettings);
    await _prefs.remove(_kSession);
    await _prefs.remove(_kLastSync);
    _categories = [...SeedData.categories];
    _items = [...SeedData.menuItems];
    _orders = SeedData.orders()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _tables = SeedData.tables();
    _settings = SeedData.settings;
    _currentUser = null;
    _lastSync = null;
    await _persistCategories();
    await _persistItems();
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
    _connectivity.online.removeListener(_onConnectivityChanged);
    if (_ownsConnectivity) _connectivity.dispose();
    super.dispose();
  }
}
