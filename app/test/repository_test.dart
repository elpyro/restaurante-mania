import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/data/repository.dart';
import 'package:app/core/data/seed_data.dart';
import 'package:app/core/models/ingredient.dart';
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
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);

    expect(repository.login('admin@restaurante.com', '1234'), isTrue);
    expect(repository.role, UserRole.admin);
    expect(repository.currentUser?.name, 'Valentina Ríos');

    repository.logout();
    expect(repository.isAuthenticated, isFalse);
    expect(repository.login('admin@restaurante.com', '0000'), isFalse);
  });

  test(
    'agrega un usuario, persiste los cambios y permite iniciar sesión',
    () async {
      final repository = await RestaurantRepository.load(
        watchConnectivity: false,
      );
      addTearDown(repository.dispose);
      repository.loginAs(UserRole.admin);

      final user = await repository.addUser(
        name: 'Nueva Cajera',
        email: 'nueva@restaurante.com',
        role: UserRole.cashier,
      );
      expect(repository.users.any((u) => u.id == user.id), isTrue);
      expect(repository.isEmailTaken('nueva@restaurante.com'), isTrue);
      repository.logout();
      expect(
        repository.login('nueva@restaurante.com', SeedData.demoPassword),
        isTrue,
      );
      expect(repository.role, UserRole.cashier);

      final reloaded = await RestaurantRepository.load(
        watchConnectivity: false,
      );
      addTearDown(reloaded.dispose);
      expect(
        reloaded.users.any((u) => u.email == 'nueva@restaurante.com'),
        isTrue,
      );
    },
  );

  test('protege la propia cuenta y el último administrador', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);
    repository.loginAs(UserRole.admin);
    final admin = repository.currentUser!;

    expect(
      () => repository.deleteUser(admin.id),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => repository.updateUser(admin.id, role: UserRole.cook),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('acceso rápido asigna el rol correcto', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);

    repository.loginAs(UserRole.cook);
    expect(repository.role, UserRole.cook);
    expect(repository.currentUser?.email, 'cocina@restaurante.com');
  });

  test('crea un pedido, calcula totales y lo persiste', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
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

    final reloaded = await RestaurantRepository.load(watchConnectivity: false);
    addTearDown(reloaded.dispose);
    final restored = reloaded.orderById(order.id);
    expect(restored, isNotNull);
    expect(restored!.total, 39800);
    expect(restored.items.length, 2);
  });

  test('pending no descuenta el inventario', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);

    final stockBefore = repository.ingredientById('pollo')!.stock;
    final order = await repository.createOrder(
      lines: cart(),
      customerName: 'Ana Pérez',
      customerPhone: '300 123 4567',
      type: OrderType.pickup,
      paymentMethod: PaymentMethod.cash,
    );

    expect(order.status, OrderStatus.pending);
    expect(order.inventoryDeducted, isFalse);
    expect(repository.ingredientById('pollo')!.stock, stockBefore);
  });

  test('avanzar a confirmed descuenta una sola vez', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);

    final stockBefore = repository.ingredientById('pollo')!.stock;
    final order = await repository.createOrder(
      lines: cart(),
      customerName: 'Ana Pérez',
      customerPhone: '300 123 4567',
      type: OrderType.pickup,
      paymentMethod: PaymentMethod.cash,
    );

    await repository.updateOrderStatus(order.id, OrderStatus.confirmed);

    expect(repository.ingredientById('pollo')!.stock, stockBefore - 180);
    expect(repository.orderById(order.id)!.inventoryDeducted, isTrue);

    await repository.updateOrderStatus(order.id, OrderStatus.confirmed);
    expect(repository.ingredientById('pollo')!.stock, stockBefore - 180);
  });

  test('cancelar un pedido confirmado repone los ingredientes', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);

    final stockBefore = repository.ingredientById('pollo')!.stock;
    final order = await repository.createOrder(
      lines: cart(),
      customerName: 'Ana Pérez',
      customerPhone: '300 123 4567',
      type: OrderType.pickup,
      paymentMethod: PaymentMethod.cash,
    );
    await repository.updateOrderStatus(order.id, OrderStatus.confirmed);
    expect(repository.ingredientById('pollo')!.stock, stockBefore - 180);

    await repository.updateOrderStatus(order.id, OrderStatus.cancelled);

    expect(repository.ingredientById('pollo')!.stock, stockBefore);
    expect(repository.orderById(order.id)!.inventoryDeducted, isFalse);
  });

  test('encola pedidos offline y los sincroniza al reconectar', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
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
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);
    repository.loginAs(UserRole.cashier);

    final stockBefore = repository.ingredientById('pollo')!.stock;
    final order = await repository.createOrder(
      lines: cart(),
      customerName: 'Mesa 6',
      customerPhone: '300 111 2222',
      type: OrderType.table,
      tableNumber: 6,
      paymentMethod: PaymentMethod.card,
    );
    expect(repository.tableByNumber(6)?.status, TableStatus.esperandoPedido);
    expect(repository.tableByNumber(6)?.currentOrderId, order.id);

    await repository.markOrderPaid(order.id);
    final paid = repository.orderById(order.id)!;
    expect(paid.paymentStatus, PaymentStatus.paid);
    expect(paid.status, OrderStatus.delivered);
    expect(paid.inventoryDeducted, isTrue);
    expect(repository.ingredientById('pollo')!.stock, stockBefore - 180);
    expect(repository.tableByNumber(6)?.status, TableStatus.libre);
    expect(repository.tableByNumber(6)?.currentOrderId, isNull);
  });

  test('actualiza disponibilidad del menú y persiste', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);

    final item = repository.menuItems.first;
    expect(item.isAvailable, isTrue);
    await repository.toggleAvailability(item.id);
    expect(repository.menuItems.first.isAvailable, isFalse);

    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString('rm_pending_menu_statuses_v1');
    expect(pending, contains(item.id));
    expect(pending, contains('unavailable'));

    final reloaded = await RestaurantRepository.load(watchConnectivity: false);
    addTearDown(reloaded.dispose);
    expect(reloaded.menuItems.first.isAvailable, isFalse);
  });

  test('reiniciar demo restaura semilla y cierra sesión', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
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
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);

    expect(repository.orders, isNotEmpty);
    expect(repository.occupiedTables, 2);
    expect(repository.freeTables, 8);
    // `todaySales` depende de la hora local: cerca de medianoche los pedidos
    // semilla de las últimas horas caen en el día anterior. Comprobamos el
    // total de la última semana para que la métrica no dependa del reloj.
    expect(
      repository.salesByDay(
        days: 7,
      ).fold<double>(0, (sum, day) => sum + day.total),
      greaterThan(0),
    );
    expect(repository.pendingPayments, greaterThan(0));
    expect(repository.salesByDay(days: 7).length, 7);
    expect(repository.topProducts(limit: 3), isNotEmpty);
  });

  test('migra el insumo cafe-huila al identificador compartido cafe', () async {
    final legacyItems = SeedData.menuItemsWithRecipes().map((item) {
      if (item.id != 'item-cafe') return item;
      return item.copyWith(
        recipe: item.recipe
            .map((line) => line.copyWith(ingredientId: 'cafe-huila'))
            .toList(),
      );
    }).toList();
    final legacyIngredients = SeedData.ingredients.map(
      (ingredient) => ingredient.id == 'cafe'
          ? ingredient.copyWith(id: 'cafe-huila')
          : ingredient,
    );
    SharedPreferences.setMockInitialValues({
      'rm_menu_items_v1': jsonEncode(
        legacyItems.map((item) => item.toJson()).toList(),
      ),
      'rm_ingredients_v1': jsonEncode(
        legacyIngredients.map((ingredient) => ingredient.toJson()).toList(),
      ),
    });

    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);

    expect(repository.ingredientById('cafe'), isNotNull);
    expect(repository.ingredientById('cafe-huila'), isNull);
    final cafe = repository.menuItemById('item-cafe');
    expect(cafe, isNotNull);
    expect(cafe!.recipe.map((line) => line.ingredientId), contains('cafe'));
    expect(
      cafe.recipe.map((line) => line.ingredientId),
      isNot(contains('cafe-huila')),
    );
  });

  test('agotar por insumos encola el estado como derivado del stock', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);

    final cafe = repository.ingredientById('cafe')!;
    await repository.adjustIngredientStock('cafe', -cafe.stock);

    expect(repository.menuItemById('item-cafe')!.status.name, 'unavailable');
    expect(repository.pendingMenuStatuses['item-cafe'], {
      'status': 'unavailable',
      'manual': false,
      'reason': 'ingredients',
    });
  });

  test('un agotado manual pendiente no es sobrescrito por el stock', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);

    await repository.toggleAvailability('item-cafe');
    final cafe = repository.ingredientById('cafe')!;
    await repository.adjustIngredientStock('cafe', -cafe.stock);

    expect(repository.pendingMenuStatuses['item-cafe'], {
      'status': 'unavailable',
      'manual': true,
      'reason': 'manual',
    });
  });

  test('la etiqueta usa porciones preparables, no solo stock cero', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);

    final cafe = repository.menuItemById('item-cafe')!;
    final recipeLine = cafe.recipe.firstWhere(
      (line) => line.ingredientId == 'cafe',
    );
    expect(recipeLine.quantity, 15);
    await repository.adjustIngredientStock(
      'cafe',
      10 - repository.ingredientById('cafe')!.stock,
    );

    expect(repository.isMenuItemOutOfStockByIngredients(cafe), isTrue);
    expect(repository.menuItemById('item-cafe')!.status.name, 'unavailable');
  });

  test('informa todos los insumos que faltan para una porción', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);

    final item = repository.menuItemById('item-empanadas')!;
    expect(repository.outOfStockIngredientsFor(item), isEmpty);

    await repository.adjustIngredientStock(
      'carne-res',
      10 - repository.ingredientById('carne-res')!.stock,
    );
    await repository.adjustIngredientStock(
      'hogao',
      -repository.ingredientById('hogao')!.stock,
    );

    final shortages = repository.outOfStockIngredientsFor(item);
    expect(shortages.map((shortage) => shortage.ingredient.id), [
      'carne-res',
      'hogao',
    ]);
    expect(shortages.first.required, 80);
    expect(shortages.first.ingredient.name, 'Carne de res');
    expect(shortages.first.ingredient.stock, 10);
    expect(shortages.last.ingredient.stock, 0);
    expect(repository.isMenuItemOutOfStockByIngredients(item), isTrue);
  });

  test('el estado del plato se agota y se recupera con el stock', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);

    final cafe = repository.ingredientById('cafe');
    expect(cafe, isNotNull);
    expect(repository.menuItemById('item-cafe')!.status.name, 'available');

    await repository.adjustIngredientStock('cafe', -cafe!.stock);
    expect(repository.menuItemById('item-cafe')!.status.name, 'unavailable');

    await repository.adjustIngredientStock('cafe', 100);
    expect(repository.menuItemById('item-cafe')!.status.name, 'available');
  });

  test('un agotado manual no se levanta al reponer stock', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);

    await repository.toggleAvailability('item-cafe');
    expect(repository.menuItemById('item-cafe')!.manualUnavailable, isTrue);
    expect(repository.menuItemById('item-cafe')!.status.name, 'unavailable');

    await repository.adjustIngredientStock('cafe', 100);
    expect(repository.menuItemById('item-cafe')!.status.name, 'unavailable');

    await repository.toggleAvailability('item-cafe');
    expect(repository.menuItemById('item-cafe')!.manualUnavailable, isFalse);
    expect(repository.menuItemById('item-cafe')!.status.name, 'available');
  });

  test(
    'mergeServerIngredients aplica stock, mínimo, nombre y unidad de la web',
    () {
      final local = [
        Ingredient(
          id: 'harina',
          name: 'Harina local',
          unit: IngredientUnit.gramo,
          stock: 100,
          minStock: 50,
          cost: 12,
        ),
      ];
      final remote = [
        Ingredient(
          id: 'harina',
          name: 'Harina web',
          unit: IngredientUnit.kilogramo,
          stock: 2,
          minStock: 0,
        ),
        Ingredient(
          id: 'nuevo',
          name: 'Nuevo',
          unit: IngredientUnit.unidad,
          stock: 7,
          minStock: 3,
        ),
      ];

      final merged = mergeServerIngredients(local, remote, const {});

      expect(merged.map((ingredient) => ingredient.id), ['harina', 'nuevo']);
      expect(merged.first.name, 'Harina web');
      expect(merged.first.unit, IngredientUnit.kilogramo);
      expect(merged.first.stock, 2);
      expect(merged.first.minStock, 0);
      expect(merged.first.cost, 12);
      expect(merged.first.isLow, isFalse);
    },
  );

  test(
    'mergeServerIngredients conserva pendientes y quita lo borrado en la web',
    () {
      final local = [
        Ingredient(
          id: 'pendiente',
          name: 'Pendiente',
          unit: IngredientUnit.unidad,
          stock: 40,
          minStock: 10,
        ),
        Ingredient(
          id: 'borrado',
          name: 'Borrado',
          unit: IngredientUnit.unidad,
          stock: 5,
          minStock: 2,
        ),
      ];
      final remote = [
        Ingredient(
          id: 'pendiente',
          name: 'Remoto',
          unit: IngredientUnit.unidad,
          stock: 1,
          minStock: 1,
        ),
      ];

      final merged = mergeServerIngredients(local, remote, const {'pendiente'});

      expect(merged.map((ingredient) => ingredient.id), ['pendiente']);
      expect(merged.first.stock, 40);
      expect(merged.first.name, 'Pendiente');
    },
  );

  test('registra momento y autor del cobro en el pedido', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);
    repository.loginAs(UserRole.cashier);

    final order = await repository.createOrder(
      lines: cart(),
      customerName: 'Ana Pérez',
      customerPhone: '300 123 4567',
      type: OrderType.pickup,
      paymentMethod: PaymentMethod.cash,
    );
    await repository.markOrderPaid(order.id);

    final paid = repository.orderById(order.id)!;
    expect(paid.paymentStatus, PaymentStatus.paid);
    expect(paid.paidAt, isNotNull);
    expect(paid.paidAtOrFallback, paid.paidAt);
    expect(paid.paidByName, 'Andrés Mejía');
    expect(paid.paidByNameOrFallback, 'Andrés Mejía');
    expect(paid.toJson()['paidBy'], isNotNull);

    final restored = await RestaurantRepository.load(watchConnectivity: false);
    addTearDown(restored.dispose);
    expect(restored.orderById(order.id)!.paidByName, 'Andrés Mejía');
  });

  test('los reportes aceptan rangos largos y turnos cerrados', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);
    repository.loginAs(UserRole.admin);

    final order = await repository.createOrder(
      lines: cart(),
      customerName: 'Ana Pérez',
      customerPhone: '300 123 4567',
      type: OrderType.pickup,
      paymentMethod: PaymentMethod.card,
    );
    await repository.markOrderPaid(order.id);

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 29));
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    expect(repository.salesByDay(days: 30).length, 30);
    expect(repository.salesInRange(start: start, end: end).length, 30);
    expect(
      repository.salesInRange(
        start: start,
        end: end,
        bucket: SalesBucket.month,
      ).length,
      greaterThanOrEqualTo(1),
    );
    expect(repository.paidOrdersInRange(start, end).any((o) => o.id == order.id), isTrue);
    expect(repository.currentShiftOrders.any((o) => o.id == order.id), isTrue);
  });

  test('cerrar caja guarda el turno y abre uno nuevo en cero', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);
    repository.loginAs(UserRole.cashier);

    final order = await repository.createOrder(
      lines: cart(),
      customerName: 'Ana Pérez',
      customerPhone: '300 123 4567',
      type: OrderType.pickup,
      paymentMethod: PaymentMethod.cash,
    );
    await repository.markOrderPaid(order.id);
    final previous = repository.activeShift;

    final closed = await repository.closeShift(closingAmount: 50000);

    expect(closed.id, previous.id);
    expect(closed.isClosed, isTrue);
    expect(closed.orderCount, 1);
    expect(closed.total, order.total);
    expect(closed.closedByName, 'Andrés Mejía');
    expect(closed.expectedCash, order.total);
    expect(closed.difference, 50000 - order.total);
    expect(repository.closedShifts.map((shift) => shift.id), contains(closed.id));
    expect(repository.activeShift.id, isNot(closed.id));
    expect(repository.activeShift.isOpen, isTrue);
    expect(repository.currentShiftOrders, isEmpty);

    final reloaded = await RestaurantRepository.load(watchConnectivity: false);
    addTearDown(reloaded.dispose);
    expect(reloaded.closedShifts.any((shift) => shift.id == closed.id), isTrue);
    expect(reloaded.activeShift.id, repository.activeShift.id);
  });

  test('mesero y cocinero no pueden cerrar caja', () async {
    for (final role in [UserRole.waiter, UserRole.cook]) {
      final repository = await RestaurantRepository.load(
        watchConnectivity: false,
      );
      addTearDown(repository.dispose);
      repository.loginAs(role);

      expect(role.canCloseShift, isFalse);
      expect(() => repository.closeShift(), throwsA(isA<StateError>()));
    }
  });
}
