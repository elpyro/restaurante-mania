import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/data/api_transport.dart';
import 'package:app/core/data/repository.dart';
import 'package:app/core/models/order.dart';
import 'package:app/core/models/role.dart';
import 'package:app/core/services/auth_service.dart';

class _Recorded {
  const _Recorded(this.method, this.path, this.body, this.query);

  final String method;
  final String path;
  final Map<String, dynamic>? body;
  final Map<String, String>? query;
}

class _FakeTransport implements ApiTransport {
  final requests = <_Recorded>[];
  Map<String, dynamic> response = const {};

  @override
  Future<ApiResponse> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool authorized = true,
  }) async {
    requests.add(_Recorded(method, path, body, query));
    return ApiResponse(200, jsonEncode(response));
  }
}

class _TokenAuth extends AuthService {
  @override
  Future<bool> get isSignedIn async => true;

  @override
  Future<String> getIdToken() async => 'firebase-token';
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FirestoreTransport', () {
    test('codifica tipos Firestore y conserva acentos y listas', () {
      final fields = FirestoreTransport.encodeFields({
        'name': 'Ajiaco colombiano',
        'stock': 12,
        'price': 12.5,
        'available': true,
        'tags': ['caliente', 'típico'],
        'extra': {'unit': 'g'},
        'deletedAt': null,
      });

      expect(fields['name'], {'stringValue': 'Ajiaco colombiano'});
      expect(fields['stock'], {'integerValue': '12'});
      expect(fields['price'], isA<Map<String, dynamic>>());
      expect(fields['available'], {'booleanValue': true});
      expect(fields['tags']?['arrayValue']?['values'], hasLength(2));
      expect(fields['extra']?['mapValue']?['fields']?['unit'],
          {'stringValue': 'g'});
      expect(fields['deletedAt'], {'nullValue': null});
    });

    test('decodifica documentos REST añadiendo el id del nombre', () {
      final documents = FirestoreTransport.decodeDocuments(jsonEncode({
        'documents': [
          {
            'name':
                'projects/p/databases/(default)/documents/tenants/mania/ingredients/pollo',
            'fields': {
              'stock': {'integerValue': '900'},
              'name': {'stringValue': 'Pollo'},
            },
          },
        ],
      }));

      expect(documents, hasLength(1));
      expect(documents.single['id'], 'pollo');
      expect(documents.single['stock'], 900);
      expect(documents.single['name'], 'Pollo');
    });
  });

  test('pullServerUsers fusiona cuentas de Firestore por uid/email', () async {
    SharedPreferences.setMockInitialValues(
      {'rm_server_url_v1': 'http://localhost:3001'},
    );
    final api = _FakeTransport()
      ..response = {
        'users': [
          {
            'uid': 'uid-nuevo',
            'name': 'Nueva Cajera',
            'email': 'nueva@restaurante.com',
            'role': 'cashier',
          },
          {
            'id': 'uid-admin',
            'name': 'Admin Real',
            'email': 'admin.qa@restaurante.com',
            'role': 'admin',
          },
        ],
      };
    final repository = await RestaurantRepository.load(
      watchConnectivity: true,
      authService: _TokenAuth(),
      transport: api,
    );
    addTearDown(repository.dispose);
    await repository.setOnlineForDemo(true);
    repository.loginAs(UserRole.admin); // pullServerUsers solo para admin

    final changed = await repository.pullServerUsers();

    expect(changed, greaterThanOrEqualTo(1));
    final usersRequest = api.requests.lastWhere(
      (request) => request.path == '/api/users',
    );
    expect(usersRequest.method, 'GET');
    final nueva = repository.users.firstWhere(
      (user) => user.email == 'nueva@restaurante.com',
    );
    expect(nueva.id, 'uid-nuevo');
    expect(nueva.role, UserRole.cashier);
    final admin = repository.users.firstWhere(
      (user) => user.email == 'admin.qa@restaurante.com',
      orElse: () => repository.users.first,
    );
    expect(admin.name, 'Admin Real');
  });

  test('pullServerMenuCatalog reemplaza la semilla por el catálogo real', () async {
    SharedPreferences.setMockInitialValues(
      {'rm_server_url_v1': 'http://localhost:3001'},
    );
    final api = _FakeTransport()
      ..response = {
        'items': [
          {
            'id': 'item-remoto',
            'name': 'Plato real',
            'slug': 'plato-real',
            'description': 'Viene de Firestore',
            'price': 21500,
            'categoryId': 'cat-fuertes',
            'categorySlug': 'platos-fuertes',
            'status': 'available',
            'ingredients': ['Pollo'],
            'allergens': [],
            'emoji': '🍗',
          },
        ],
      };
    final repository = await RestaurantRepository.load(
      watchConnectivity: true,
      authService: _TokenAuth(),
      transport: api,
    );
    addTearDown(repository.dispose);
    await repository.setOnlineForDemo(true);

    final count = await repository.pullServerMenuCatalog();

    expect(count, 1);
    expect(repository.menuItems.map((item) => item.id), ['item-remoto']);
    expect(repository.menuItems.single.name, 'Plato real');
    expect(api.requests.any((request) => request.path == '/api/menu'), isTrue);
  });

  test('sincroniza pedidos offline con POST real a /api/orders', () async {
    final api = _FakeTransport();
    final repository = await RestaurantRepository.load(
      watchConnectivity: true,
      authService: _TokenAuth(),
      transport: api,
    );
    addTearDown(repository.dispose);

    await repository.setOnlineForDemo(false);
    final order = await repository.createOrder(
      lines: const [
        CartLine(
          menuItemId: 'item-ajiaco',
          name: 'Ajiaco',
          price: 32900,
          quantity: 1,
          emoji: '🍲',
        ),
      ],
      customerName: 'Cliente Offline',
      customerPhone: '310 000 0000',
      type: OrderType.pickup,
      paymentMethod: PaymentMethod.cash,
    );
    expect(order.synced, isFalse);

    await repository.setOnlineForDemo(true);

    final post = api.requests.where(
      (request) => request.path == '/api/orders' && request.method == 'POST',
    );
    expect(post, hasLength(1));
    expect(post.single.query?['id'], order.id);
    expect(post.single.body?['source'], 'app');
    expect(post.single.body?['inventoryDeducted'], isTrue);
    expect(repository.orderById(order.id)?.synced, isTrue);
    expect(repository.pendingSyncCount, 0);
  });

  test('FirestoreTransport.buildQueryString repite updateMask.fieldPaths', () {
    final query = FirestoreTransport.buildQueryString(
      parameters: {'id': 'abc def'},
      maskPaths: ['status', 'paymentStatus', 'items', 'notes'],
    );
    expect(query, contains('id=abc+def'));
    expect('updateMask.fieldPaths='.allMatches(query).length, 4);
    expect(query, contains('updateMask.fieldPaths=status'));
    expect(query, contains('updateMask.fieldPaths=paymentStatus'));
    expect(query, contains('updateMask.fieldPaths=items'));
    expect(query, contains('updateMask.fieldPaths=notes'));
    expect(query, isNot(contains('updateMask.fieldPaths=status,paymentStatus')));
  });

  test('FirestoreTransport.fromEnvironment usa el proyecto real', () {
    final transport = FirestoreTransport.fromEnvironment(
      auth: _TokenAuth(),
      tenantId: 'mania',
    );
    expect(transport.projectId, 'restaurante-mania-e47a0');
    expect(transport.tenantId, 'mania');
  });
}
