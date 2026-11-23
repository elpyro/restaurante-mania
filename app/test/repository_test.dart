import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/data/repository.dart';
import 'package:app/core/models/order.dart';
import 'package:app/core/models/restaurant_table.dart';
import 'package:app/core/models/role.dart';

List<CartLine> cart() => const [
      CartLine(
        menuItemId: 'item-ajiaco',
        name: 'Ajiaco',
        price: 32900,
        quantity: 1,
        emoji: '🍲',
      ),
      CartLine(
        menuItemId: 'item-cafe',
        name: 'Café',
        price: 6900,
        quantity: 1,
        emoji: '☕',
      ),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('inicia sesión con cuentas demo y rechaza clave incorrecta', () async {
    final repository =
        await RestaurantRepository.load(watchConnectivity: false);
    addTearDown(repository.dispose);

    expect(repository.login('admin@restaurante.com', '1234'), isTrue);
    expect(repository.role, UserRole.admin);
    expect(repository.currentUser?.name, 'Valentina Ríos');

    repository.logout();
    expect(repository.isAuthenticated, isFalse);
    expect(repository.login('admin@restaurante.com', '0000'), isFalse);
  });

  test('acceso rápido asigna el rol correcto', () async {
    final repository =
        await RestaurantRepository.load(watchConnectivity: false);
    addTearDown(repository.dispose);

    repository.loginAs(UserRole.cook);
    expect(repository.role, UserRole.cook);
    expect(repository.currentUser?.email, 'cocina@restaurante.com');
  });

  test('crea un pedido, calcula totales y lo persiste', () async {
    final repository =
        await RestaurantRepository.load(watchConnectivity: false);
    addTearDown(repository.dispose);
    repository.loginAs(UserRole.waiter);

    final before = repository.orders.length;
    final order = await repository.createOrder(
      lines: cart(),
      customerName: 'Ana Pérez',
      customerPhone: '300 123 4567',
      type: OrderType.pickup,
      paymentMethod: PaymentMethod.nequi,
    );

    expect(repository.orders.length, before + 1);
    expect(order.total, 39800);
    expect(order.status, OrderStatus.pending);
    expect(order.synced, isTrue);

    final reloaded =
        await RestaurantRepository.load(watchConnectivity: false);
    addTearDown(reloaded.dispose);
    final restored = reloaded.orderById(order.id);
    expect(restored, isNotNull);
    expect(restored!.total, 39800);
    expect(restored.items.length, 2);
  });

  test('encola pedidos offline y los sincroniza al reconectar', () async {
    final repository =
        await RestaurantRepository.load(watchConnectivity: false);
    addTearDown(repository.dispose);

    await repository.setOnlineForDemo(false);
    expect(repository.isOnline, isFalse);

    final order = await repository.createOrder(
      lines: cart(),
      customerName: 'Cliente Offline',
      customerPhone: '310 000 0000',
      deliveryAddress: 'Calle 10 # 20-30, Medellín',
      type: OrderType.delivery,
      paymentMethod: PaymentMethod.cash,
    );
    expect(order.synced, isFalse);
    expect(repository.pendingSyncCount, 1);

    await repository.setOnlineForDemo(true);
    expect(repository.isOnline, isTrue);
    expect(repository.pendingSyncCount, 0);
    expect(repository.orderById(order.id)?.synced, isTrue);
    expect(repository.lastSync, isNotNull);
  });

  test('cobrar un pedido de mesa libera la mesa', () async {
    final repository =
        await RestaurantRepository.load(watchConnectivity: false);
    addTearDown(repository.dispose);
    repository.loginAs(UserRole.cashier);

    final order = await repository.createOrder(
      lines: cart(),
      customerName: 'Mesa 6',
      customerPhone: '300 111 2222',
      type: OrderType.table,
      tableNumber: 6,
      paymentMethod: PaymentMethod.card,
    );
    expect(repository.tableByNumber(6)?.status,
        TableStatus.esperandoPedido);
    expect(repository.tableByNumber(6)?.currentOrderId, order.id);

    await repository.markOrderPaid(order.id);
    final paid = repository.orderById(order.id)!;
    expect(paid.paymentStatus, PaymentStatus.paid);
    expect(paid.status, OrderStatus.delivered);
    expect(repository.tableByNumber(6)?.status, TableStatus.libre);
    expect(repository.tableByNumber(6)?.currentOrderId, isNull);
  });

  test('actualiza disponibilidad del menú y persiste', () async {
    final repository =
        await RestaurantRepository.load(watchConnectivity: false);
    addTearDown(repository.dispose);

    final item = repository.menuItems.first;
    expect(item.isAvailable, isTrue);
    await repository.toggleAvailability(item.id);
    expect(repository.menuItems.first.isAvailable, isFalse);

    final reloaded =
        await RestaurantRepository.load(watchConnectivity: false);
    addTearDown(reloaded.dispose);
    expect(reloaded.menuItems.first.isAvailable, isFalse);
  });

  test('reiniciar demo restaura semilla y cierra sesión', () async {
    final repository =
        await RestaurantRepository.load(watchConnectivity: false);
    addTearDown(repository.dispose);
    repository.loginAs(UserRole.admin);
    await repository.createOrder(
      lines: cart(),
      customerName: 'Temporal',
      customerPhone: '300 000 0000',
      type: OrderType.pickup,
      paymentMethod: PaymentMethod.cash,
    );

    await repository.resetDemoData();
    expect(repository.isAuthenticated, isFalse);
    expect(repository.orders.length, 8);
    expect(repository.menuItems.length, 13);
    expect(repository.tables.length, 10);
  });

  test('métricas de dashboard responden a los datos', () async {
    final repository =
        await RestaurantRepository.load(watchConnectivity: false);
    addTearDown(repository.dispose);

    expect(repository.orders, isNotEmpty);
    expect(repository.occupiedTables, 2);
    expect(repository.freeTables, 8);
    expect(repository.todaySales, greaterThan(0));
    expect(repository.pendingPayments, greaterThan(0));
    expect(repository.salesByDay(days: 7).length, 7);
    expect(repository.topProducts(limit: 3), isNotEmpty);
  });
}
