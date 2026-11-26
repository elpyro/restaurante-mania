import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/data/repository.dart';
import 'package:app/core/models/inventory_loss.dart';
import 'package:app/core/models/role.dart';
import 'package:app/core/services/auth_service.dart';

/// Igual que las pruebas de apariencia: HttpServer real porque el binding de
/// flutter_test intercepta HttpClient y devuelve 400.
class _PostedLoss {
  _PostedLoss({required this.authorization, required this.body});

  final String? authorization;
  final Map<String, dynamic> body;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      AuthService.idTokenKey: 'firebase-token',
      AuthService.refreshTokenKey: 'firebase-refresh',
      AuthService.expiryKey: DateTime.now()
          .add(const Duration(hours: 1))
          .toIso8601String(),
    });
  });

  Future<void> waitFor(bool Function() condition) async {
    for (var attempt = 0; attempt < 250; attempt++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('registra offline, descuenta stock y envía la auditoría al reconectar',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final posts = <_PostedLoss>[];
    server.listen((request) async {
      final bodyText = await utf8.decoder.bind(request).join();
      final response = request.response..headers.contentType = ContentType.json;
      if (request.method == 'POST' &&
          request.uri.path == '/api/inventory-losses') {
        Map<String, dynamic> body = {};
        try {
          body = jsonDecode(bodyText) as Map<String, dynamic>;
        } catch (_) {}
        posts.add(
          _PostedLoss(
            authorization:
                request.headers.value(HttpHeaders.authorizationHeader),
            body: body,
          ),
        );
      }
      response.write(jsonEncode(<String, dynamic>{'ok': true}));
      await response.close();
    });

    SharedPreferences.setMockInitialValues({
      'rm_server_url_v1': 'http://127.0.0.1:${server.port}',
    });
    final repository = await RestaurantRepository.load(
      watchConnectivity: true,
      authService: AuthService(storage: FlutterSecureStorage()),
    );
    addTearDown(() async {
      repository.dispose();
      await server.close();
    });

    repository.loginAs(UserRole.cook);
    await repository.setOnlineForDemo(false);

    final loss = await repository.registerInventoryLoss(
      reason: LossReason.perdida,
      lines: [
        LossLine(
          ingredientId: 'huevo',
          name: 'Huevo',
          quantity: 5,
          unit: 'unidad',
        ),
      ],
      notes: 'Se rompieron en la nevera',
    );

    expect(loss.synced, isFalse);
    expect(repository.pendingInventoryLosses, hasLength(1));
    expect(repository.ingredientById('huevo')!.stock, 115);
    expect(posts, isEmpty);

    await repository.setOnlineForDemo(true);
    await repository.flushInventoryLosses();
    await waitFor(() => repository.inventoryLosses.single.synced);

    expect(posts, hasLength(1));
    expect(posts.single.authorization, 'Bearer firebase-token');
    expect(posts.single.body['reason'], 'perdida');
    expect(posts.single.body['notes'], 'Se rompieron en la nevera');
    expect(posts.single.body['createdBy']['role'], 'cook');
    expect((posts.single.body['lines'] as List).single['quantity'], 5);
    expect(repository.pendingInventoryLosses, isEmpty);
    expect(repository.inventoryLosses.single.statusLabel, 'Sincronizado');
  });

  test('meseros y cajeros no pueden registrar pérdidas', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);

    repository.loginAs(UserRole.waiter);
    expect(
      () => repository.registerInventoryLoss(
        reason: LossReason.caducado,
        lines: [
          LossLine(
            ingredientId: 'huevo',
            name: 'Huevo',
            quantity: 1,
          ),
        ],
      ),
      throwsStateError,
    );
    expect(repository.inventoryLosses, isEmpty);
  });
}
