import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/data/repository.dart';
import 'package:app/core/data/seed_data.dart';
import 'package:app/core/data/tenant.dart';
import 'package:app/core/models/ingredient.dart';
import 'package:app/core/models/menu_item.dart';
import 'package:app/core/models/order.dart';

const _postre = CartLine(
  menuItemId: 'item-tres-leches',
  name: 'Tres leches',
  price: 12900,
  quantity: 1,
  emoji: '🍰',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('identidad de tenants', () {
    test('normaliza valores y desconoce ids inválidos', () {
      expect(normalizeTenantId(null), defaultTenantId);
      expect(normalizeTenantId(' FUEGO '), 'fuego');
      expect(normalizeTenantId('inexistente'), defaultTenantId);
      expect(isDemoTenant(defaultTenantId), isFalse);
      expect(isDemoTenant('verde'), isTrue);
      expect(tenants.keys, containsAll(['mania', 'fuego', 'verde']));
    });

    test('mania conserva las claves legacy y los demo usan prefijo', () {
      expect(tenantStorageKey('mania', 'rm_orders_v1'), 'rm_orders_v1');
      expect(tenantStorageKey('fuego', 'rm_orders_v1'), 'rm_fuego_orders_v1');
      expect(
        tenantStorageKey('verde', 'rm_customer_profile_v1'),
        'rm_verde_customer_profile_v1',
      );
    });

    test('TenantPreferences aísla lecturas y escrituras', () async {
      final raw = await SharedPreferences.getInstance();
      final fuego = TenantPreferences(raw, 'fuego');
      final verde = TenantPreferences(raw, 'verde');
      final mania = TenantPreferences(raw, 'mania');

      await fuego.setString('rm_orders_v1', 'solo-fuego');
      expect(verde.getString('rm_orders_v1'), isNull);
      expect(mania.getString('rm_orders_v1'), isNull);
      expect(raw.getString('rm_fuego_orders_v1'), 'solo-fuego');
      expect(fuego.scope('rm_orders_v1'), 'rm_fuego_orders_v1');
    });
  });

  group('seeds por tenant', () {
    test('fuego añade plato de brasa y stock propio', () {
      final mania = SeedData.menuItemsFor('mania');
      final fuego = SeedData.menuItemsFor('fuego');
      expect(
        mania.any((item) => item.id == 'item-fuego-parrilla'),
        isFalse,
      );
      expect(
        fuego.any((item) => item.id == 'item-fuego-parrilla'),
        isTrue,
      );
      final maniaStock = SeedData.ingredientsFor('mania');
      final fuegoStock = SeedData.ingredientsFor('fuego');
      double stock(List<Ingredient> list, String id) =>
          list.firstWhere((item) => item.id == id).stock;
      expect(stock(fuegoStock, 'maiz-blanco'), 0);
      expect(stock(maniaStock, 'maiz-blanco'), greaterThan(0));
      expect(stock(fuegoStock, 'camaron'), greaterThan(0));
    });

    test('verde agota el ajiaco y cambia sus insumos', () {
      final verde = SeedData.menuItemsFor('verde');
      final ajiaco = verde.firstWhere((item) => item.id == 'item-ajiaco');
      expect(ajiaco.status, MenuItemStatus.unavailable);
      expect(ajiaco.manualUnavailable, isTrue);
      final verdeStock = SeedData.ingredientsFor('verde');
      final res = verdeStock.firstWhere((item) => item.id == 'carne-res');
      expect(res.stock, 0);
    });

    test('solo manía arranca con pedidos históricos', () {
      expect(SeedData.ordersFor('mania'), isNotEmpty);
      expect(SeedData.ordersFor('fuego'), isEmpty);
      expect(SeedData.ordersFor('verde'), isEmpty);
    });
  });

  group('repositorio multi-tenant', () {
    test('carga fuego en claves prefijadas sin tocar las de manía', () async {
      final repository = await RestaurantRepository.load(
        tenantId: 'fuego',
        watchConnectivity: false,
      );
      addTearDown(repository.dispose);

      expect(repository.tenantId, 'fuego');
      expect(repository.orders, isEmpty);
      expect(
        repository.menuItems.any((item) => item.id == 'item-fuego-parrilla'),
        isTrue,
      );

      final raw = await SharedPreferences.getInstance();
      expect(raw.containsKey('rm_fuego_menu_items_v1'), isTrue);
      expect(raw.containsKey('rm_menu_items_v1'), isFalse);
    });

    test('switchTenant conserva la instancia y aísla pedidos y catálogo',
        () async {
      final repository = await RestaurantRepository.load(
        watchConnectivity: false,
      );
      addTearDown(repository.dispose);
      final maniaOrders = repository.orders.length;
      expect(maniaOrders, greaterThan(0));

      await repository.switchTenant('fuego');
      expect(repository.tenantId, 'fuego');
      expect(repository.orders, isEmpty);
      expect(
        repository.menuItems.any((item) => item.id == 'item-fuego-parrilla'),
        isTrue,
      );

      await repository.switchTenant('verde');
      expect(repository.tenantId, 'verde');
      expect(repository.orders, isEmpty);

      await repository.switchTenant('mania');
      expect(repository.tenantId, 'mania');
      expect(repository.orders.length, maniaOrders);
      expect(
        repository.menuItems.any((item) => item.id == 'item-fuego-parrilla'),
        isFalse,
      );
    });

    test('un pedido de verde no aparece al volver a manía', () async {
      final repository = await RestaurantRepository.load(
        tenantId: 'verde',
        watchConnectivity: false,
      );
      addTearDown(repository.dispose);

      final order = await repository.createOrder(
        lines: const [_postre],
        customerName: 'Ana Pérez',
        customerPhone: '300 123 4567',
        type: OrderType.pickup,
      );
      expect(repository.orders.any((item) => item.id == order.id), isTrue);

      final mania = await RestaurantRepository.load(
        tenantId: 'mania',
        watchConnectivity: false,
      );
      addTearDown(mania.dispose);
      expect(mania.orders.any((item) => item.id == order.id), isFalse);
      expect(
        mania.orders.any((item) => item.code == order.code),
        isFalse,
      );
    });

    test('la preferencia global recuerda el tenant seleccionado', () async {
      final repository = await RestaurantRepository.load(
        watchConnectivity: false,
      );
      addTearDown(repository.dispose);
      await repository.switchTenant('verde');

      final raw = await SharedPreferences.getInstance();
      expect(raw.getString(tenantPreferenceKey), 'verde');

      final restored = await RestaurantRepository.load(
        watchConnectivity: false,
      );
      addTearDown(restored.dispose);
      expect(restored.tenantId, 'verde');
    });
  });
}
