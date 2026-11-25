import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/models/inventory_loss.dart';

void main() {
  InventoryLoss buildLoss() => InventoryLoss(
        id: 'loss-1',
        reason: LossReason.caducado,
        lines: [
          LossLine(
            ingredientId: 'leche',
            name: 'Leche entera',
            quantity: 2.5,
            unit: 'l',
          ),
        ],
        notes: 'Lote vencido',
        photoPath: '/tmp/leche.jpg',
        createdAt: DateTime.parse('2026-11-25T10:00:00.000Z'),
        createdById: 'cook-1',
        createdByName: 'Jorge',
        createdByRole: 'cook',
        auditLog: [
          LossAuditEntry(
            action: 'Pérdida registrada',
            timestamp: DateTime.parse('2026-11-25T10:00:00.000Z'),
            actorId: 'cook-1',
            actorName: 'Jorge',
            actorRole: 'cook',
          ),
        ],
      );

  test('toJson y fromJson conservan las líneas y la auditoría', () {
    final loss = buildLoss();
    final restored = InventoryLoss.fromJson(loss.toJson());

    expect(restored, loss);
    expect(restored.reason, LossReason.caducado);
    expect(restored.lines.single.quantity, 2.5);
    expect(restored.auditLog.single.actorName, 'Jorge');
    expect(restored.synced, isFalse);
  });

  test('toWebJson usa el contrato de la web con la URL de la foto', () {
    final web = buildLoss().copyWith(
      photoUrl: 'https://storage.example/leche.jpg',
    ).toWebJson();

    expect(web['id'], 'loss-1');
    expect(web['reason'], 'caducado');
    expect(web['photoUrl'], 'https://storage.example/leche.jpg');
    expect(web['createdBy'], {
      'uid': 'cook-1',
      'name': 'Jorge',
      'role': 'cook',
    });
    expect((web['lines'] as List).single, {
      'ingredientId': 'leche',
      'name': 'Leche entera',
      'quantity': 2.5,
      'unit': 'l',
    });
    expect((web['auditLog'] as List), hasLength(1));
  });

  test('fromWebJson marca el registro como sincronizado', () {
    final loss = InventoryLoss.fromWebJson({
      'id': 'loss-remote',
      'reason': 'dano',
      'lines': [
        {
          'ingredientId': 'huevo',
          'name': 'Huevo',
          'quantity': 3,
          'unit': 'unidad',
        },
      ],
      'createdAt': '2026-11-24T09:00:00.000Z',
      'notes': 'Se rompieron',
      'photoUrl': 'https://storage.example/huevo.jpg',
      'createdBy': {'uid': 'admin-1', 'name': 'Ana', 'role': 'admin'},
      'auditLog': [],
    });

    expect(loss.synced, isTrue);
    expect(loss.reason, LossReason.dano);
    expect(loss.createdByName, 'Ana');
    expect(loss.photoPath, isNull);
    expect(loss.linesSummary, contains('Huevo'));
  });
}
