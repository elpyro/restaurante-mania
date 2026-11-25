import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/data/repository.dart';

/// Igual que el test de ingredientes: usa un servidor HTTP real porque el
/// binding de flutter_test intercepta `HttpClient`.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'un pago marcado en la web actualiza el cobrador del pedido ya importado',
    () async {
      final paidAt = DateTime.utc(2026, 11, 25, 4, 38);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await request.drain<void>();
        final response = request.response
          ..headers.contentType = ContentType.json;
        if (request.uri.path == '/api/orders' && request.method == 'GET') {
          response.write(
            jsonEncode([
              {
                'id': 'o-web-1',
                'code': 'RM-20261125-1O35',
                'customerName': 'QA Turno',
                'items': const [],
                'subtotal': 9500,
                'tax': 0,
                'total': 9500,
                'status': 'pending',
                'paymentStatus': 'paid',
                'paymentMethod': 'cash',
                'createdAt': '2026-11-25T04:37:33.057Z',
                'updatedAt': '2026-11-25T04:38:00.000Z',
                'source': 'web',
                'inventoryDeducted': false,
                'paidAt': paidAt.toIso8601String(),
                'paidBy': 'u-cashier',
                'paidByName': 'QA Cajero',
              },
            ]),
          );
        } else {
          response.write('{}');
        }
        await response.close();
      });

      SharedPreferences.setMockInitialValues({
        'rm_server_url_v1': 'http://127.0.0.1:${server.port}',
        'rm_orders_v1': jsonEncode([
          {
            'id': 'o-web-1',
            'code': 'RM-20261125-1O35',
            'customerName': 'QA Turno',
            'items': const [],
            'subtotal': 9500,
            'tax': 0,
            'total': 9500,
            'status': 'pending',
            'paymentStatus': 'paid',
            'paymentMethod': 'cash',
            'createdAt': '2026-11-25T04:37:33.057Z',
            'updatedAt': '2026-11-25T04:37:56.767Z',
            'source': 'web',
            'synced': true,
            'inventoryDeducted': false,
          },
        ]),
      });

      final repository = await RestaurantRepository.load(
        watchConnectivity: true,
      );
      addTearDown(() async {
        repository.dispose();
        await server.close();
      });

      // El arranque pudo haber consumido el primer pull; esperamos a que
      // termine antes de lanzar uno nuevo.
      for (var attempt = 0; attempt < 100; attempt++) {
        if (repository.orders.first.paidByName == 'QA Cajero') break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(repository.orders.first.paidByName, 'QA Cajero');
      expect(repository.orders.first.paidBy, 'u-cashier');
      expect(repository.orders.first.paidAt, paidAt);
      final auditActions = repository.orders.first.auditLog
          .map((entry) => entry.action)
          .toList();
      expect(auditActions, contains('Cobrador actualizado desde la web'));

      // Un segundo sondeo no debe duplicar la entrada de auditoría.
      await repository.pullServerOrders();
      expect(
        repository.orders.first.auditLog
            .where((entry) => entry.action == 'Cobrador actualizado desde la web')
            .length,
        1,
      );
    },
  );
}
