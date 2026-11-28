import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/data/api_transport.dart';
import 'package:app/core/data/repository.dart';
import 'package:app/core/data/seed_data.dart';
import 'package:app/core/data/tenant.dart';
import 'package:app/core/models/category.dart';
import 'package:app/core/models/restaurant_appearance.dart';
import 'package:app/core/models/restaurant_table.dart';
import 'package:app/features/orders/new_order_screen.dart';

class _RecordedRequest {
  const _RecordedRequest(this.method, this.path);

  final String method;
  final String path;
}

class _ConfiguredTenantTransport implements ApiTransport {
  final requests = <_RecordedRequest>[];
  List<Map<String, dynamic>> menuItems = const [];

  @override
  Future<ApiResponse> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool authorized = true,
  }) async {
    requests.add(_RecordedRequest(method, path));
    if (path == '/api/restaurant/config') {
      return ApiResponse(
        200,
        jsonEncode({
          'config': {'name': 'Taquitos mexicanos'},
        }),
      );
    }
    if (path == '/api/menu') {
      return ApiResponse(200, jsonEncode({'items': menuItems}));
    }
    return ApiResponse(200, jsonEncode({}));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('la plantilla genérica no filtra datos de otro restaurante', () {
    expect(isFixedTenant('mania'), isTrue);
    expect(isFixedTenant('fuego'), isTrue);
    expect(isFixedTenant('verde'), isTrue);
    expect(isTemplateTenant('resturantedeejemplo'), isTrue);
    expect(isTemplateTenant('casa-nueva'), isTrue);
    expect(isTemplateTenant('Mi Tienda'), isFalse);

    final settings = SeedData.genericSettings;
    expect(settings.name, 'Restaurante de ejemplo');
    expect(settings.city, 'Ciudad por definir');
    expect(settings.aiSearch['description'], contains('pedidos en línea'));
    expect(
      settings.toWebConfigPatch()['aiSearch'],
      containsPair(
        'highlights',
        'Platillos preparados al momento, pedidos sencillos, servicio amable',
      ),
    );

    final appearance = RestaurantAppearance.generic;
    expect(appearance.preset, AppearancePreset.tierra);
    expect(appearance.heroBadge, isNot(contains('Colombia')));
    expect(appearance.heroDescription, isNot(contains('Bandeja')));

    final items = SeedData.genericMenuItems();
    expect(items, hasLength(2));
    expect(items.map((item) => item.id).toSet(), {
      'item-ensalada-fresca',
      'item-cafe-con-leche',
    });
    expect(
      items.where((item) => item.featured).map((item) => item.id).toSet(),
      {'item-ensalada-fresca', 'item-cafe-con-leche'},
    );
    expect(SeedData.genericCategories, hasLength(11));
    expect(
      SeedData.genericCategories.map((category) => category.name).toList(),
      [
        'Entradas',
        'Sopas',
        'Platos fuertes',
        'Ensaladas',
        'Guarniciones',
        'Postres',
        'Bebidas',
        'Licores',
        'Combos y promociones',
        'Menú infantil',
        'Opciones dietéticas',
      ],
    );
    expect(
      SeedData.genericIngredients.map((ingredient) => ingredient.name).toSet(),
      {'Tomates', 'Lechuga', 'Cafe', 'Leche'},
    );
    final cafe = SeedData.genericIngredients.firstWhere(
      (ingredient) => ingredient.id == 'ing-cafe',
    );
    expect(cafe.stock, 40);
    expect(cafe.minStock, 20);
    expect(
      SeedData.tables().every((table) => table.status == TableStatus.libre),
      isTrue,
    );

    final ingredientIds = SeedData.genericIngredients
        .map((item) => item.id)
        .toSet();
    for (final item in items) {
      expect(item.recipe, isNotEmpty);
      expect(item.imageUrl, contains('imagenesglobales'));
      for (final line in item.recipe) {
        expect(ingredientIds, contains(line.ingredientId));
      }
    }
  });

  test('Nuevo pedido oculta categorías vacías y con orden cero', () {
    final items = SeedData.genericMenuItems();
    final visible = categoriesForOrderMenu(SeedData.genericCategories, items);
    expect(visible.map((category) => category.id).toList(), [
      'cat-ensaladas',
      'cat-bebidas',
    ]);

    const zeroOrderCategory = Category(
      id: 'cat-ensaladas',
      name: 'Ensaladas',
      slug: 'ensaladas',
      description: '',
      order: 0,
      emoji: '🥗',
    );
    expect(categoriesForOrderMenu([zeroOrderCategory], items), isEmpty);
  });

  test(
    'un restaurante nuevo carga la plantilla sin tocar las semillas fijas',
    () async {
      const id = 'resturantedeejemplo';
      registerTenant(
        const TenantDefinition(
          id: id,
          label: 'Restaurante de ejemplo',
          description: '',
          emoji: '🍽️',
        ),
      );
      addTearDown(() => tenants.remove(id));

      final repository = await RestaurantRepository.load(
        tenantId: id,
        watchConnectivity: false,
      );
      addTearDown(repository.dispose);

      expect(repository.tenantId, id);
      expect(repository.settings.name, 'Restaurante de ejemplo');
      expect(repository.restaurantAppearance.heroBadge, '🍽️ Menú para todos');
      expect(repository.categories, hasLength(11));
      expect(repository.menuItems, hasLength(2));
      expect(repository.ingredients, hasLength(4));
      expect(
        repository.menuItems.every(
          (item) =>
              item.id != 'item-empanadas' && item.id != 'item-bandeja-paisa',
        ),
        isTrue,
      );
    },
  );

  test(
    'un tenant dinámico ya configurado conserva su catálogo histórico',
    () async {
      const id = 'taquitos-mexicanos';
      registerTenant(
        const TenantDefinition(
          id: id,
          label: 'Taquitos mexicanos',
          description: '',
          emoji: '🌮',
        ),
      );
      addTearDown(() => tenants.remove(id));

      final repository = await RestaurantRepository.load(
        tenantId: id,
        watchConnectivity: true,
        transport: _ConfiguredTenantTransport(),
      );
      addTearDown(repository.dispose);

      final ids = repository.menuItems.map((item) => item.id).toSet();
      expect(ids, contains('item-empanadas'));
      expect(ids, isNot(contains('item-cafe-con-leche')));
    },
  );

  test('no crea documentos parciales al publicar estados de platos', () async {
    const id = 'taquitos-mexicanos';
    registerTenant(
      const TenantDefinition(
        id: id,
        label: 'Taquitos mexicanos',
        description: '',
        emoji: '🌮',
      ),
    );
    addTearDown(() => tenants.remove(id));

    final transport = _ConfiguredTenantTransport();
    final repository = await RestaurantRepository.load(
      tenantId: id,
      watchConnectivity: true,
      transport: transport,
    );
    addTearDown(repository.dispose);
    await repository.setOnlineForDemo(true);
    await repository.refreshAll();

    await repository.toggleAvailability('item-empanadas');
    await repository.refreshAll();

    final menuPatches = transport.requests.where(
      (request) =>
          request.method == 'PATCH' && request.path.startsWith('/api/menu/'),
    );
    expect(menuPatches, isEmpty);
  });
}
