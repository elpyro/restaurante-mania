import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/data/repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'el sondeo de turnos no mete el turno abierto en el historial de cerrados',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Map<String, dynamic> shift({
        required String id,
        required String openedAt,
        required String status,
      }) {
        return {
          'id': id,
          'label': 'Turno $id',
          'openedAt': openedAt,
          'openedBy': 'u-admin',
          'openedByName': 'Administrador',
          'closedAt': status == 'closed' ? '2026-11-25T05:00:00.000Z' : null,
          'closedBy': status == 'closed' ? 'u-admin' : null,
          'closedByName': status == 'closed' ? 'Administrador' : null,
          'orderCount': 0,
          'total': 0,
          'totalsByPaymentMethod': <String, dynamic>{},
          'closingAmount': null,
          'notes': '',
          'status': status,
        };
      }

      final open = shift(
        id: 'shift-open',
        openedAt: '2026-11-25T05:02:23.580Z',
        status: 'open',
      );
      final closed = shift(
        id: 'shift-closed',
        openedAt: '2026-11-25T04:48:07.576Z',
        status: 'closed',
      );
      server.listen((request) async {
        await request.drain<void>();
        final response = request.response
          ..headers.contentType = ContentType.json;
        if (request.uri.path == '/api/cash-shifts' && request.method == 'GET') {
          response.write(jsonEncode({
            'currentShift': open,
            'shifts': [open, closed],
          }));
        } else {
          response.write('{}');
        }
        await response.close();
      });

      SharedPreferences.setMockInitialValues({
        'rm_server_url_v1': 'http://127.0.0.1:${server.port}',
        'rm_active_cash_shift_v1': jsonEncode(
          shift(
            id: 'shift-local',
            openedAt: '2026-11-25T04:30:00.000Z',
            status: 'open',
          ),
        ),
        // Estado heredado de la versión que guardaba el activo como cerrado.
        'rm_cash_shifts_v1': jsonEncode([
          shift(
            id: 'shift-open',
            openedAt: '2026-11-25T05:02:23.580Z',
            status: 'closed',
          ),
        ]),
      });

      final repository = await RestaurantRepository.load(
        watchConnectivity: true,
      );
      addTearDown(() async {
        repository.dispose();
        await server.close();
      });

      for (var attempt = 0; attempt < 100; attempt++) {
        if (repository.activeShift.id == 'shift-open' &&
            repository.closedShifts.isNotEmpty) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      if (repository.activeShift.id != 'shift-open') {
        await repository.pullCashShifts();
      }

      expect(repository.activeShift.id, 'shift-open');
      expect(repository.closedShifts.map((s) => s.id), ['shift-closed']);
    },
  );
}
