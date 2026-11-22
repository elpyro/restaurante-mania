import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/models/order.dart';
import 'package:app/core/models/restaurant_table.dart';
import 'package:app/core/utils/formatters.dart';

Order sampleOrder({OrderStatus status = OrderStatus.pending}) {
  final now = DateTime(2026, 11, 22, 12, 30);
  return Order(
    id: 'order-test',
    code: 'RM-20261122-1234',
    customerName: 'Ana Pérez',
    customerPhone: '300 123 4567',
    type: OrderType.table,
    tableNumber: 4,
    items: const [
      OrderItem(
        menuItemId: 'item-ajiaco',
        name: 'Ajiaco',
        price: 32900,
        quantity: 2,
        emoji: '🍲',
      ),
      OrderItem(
        menuItemId: 'item-cafe',
        name: 'Café',
        price: 6900,
        quantity: 1,
        emoji: '☕',
      ),
    ],
    subtotal: 72700,
    tax: 0,
    total: 72700,
    status: status,
    paymentStatus: PaymentStatus.pending,
    paymentMethod: PaymentMethod.cash,
    notes: 'Sin crema',
    createdAt: now,
    updatedAt: now,
    source: 'app',
    synced: true,
  );
}

void main() {
  group('flujo de estados del pedido', () {
    test('avanza en orden hasta entregado', () {
      expect(OrderStatus.pending.next, OrderStatus.confirmed);
      expect(OrderStatus.confirmed.next, OrderStatus.preparing);
      expect(OrderStatus.preparing.next, OrderStatus.ready);
      expect(OrderStatus.ready.next, OrderStatus.delivered);
      expect(OrderStatus.delivered.next, isNull);
      expect(OrderStatus.cancelled.next, isNull);
    });

    test('identifica pedidos activos', () {
      expect(OrderStatus.pending.isActive, isTrue);
      expect(OrderStatus.preparing.isActive, isTrue);
      expect(OrderStatus.delivered.isActive, isFalse);
      expect(OrderStatus.cancelled.isActive, isFalse);
    });
  });

  group('modelo de pedido', () {
    test('calcula unidades y conserva totales', () {
      final order = sampleOrder();
      expect(order.itemCount, 3);
      expect(order.items.first.subtotal, 65800);
      expect(order.total, 72700);
    });

    test('serializa y deserializa sin perder datos', () {
      final order = sampleOrder(status: OrderStatus.preparing);
      final restored = Order.fromJson(order.toJson());
      expect(restored.id, order.id);
      expect(restored.code, order.code);
      expect(restored.status, OrderStatus.preparing);
      expect(restored.type, OrderType.table);
      expect(restored.tableNumber, 4);
      expect(restored.items.length, 2);
      expect(restored.items.first.name, 'Ajiaco');
      expect(restored.total, order.total);
      expect(restored.paymentStatus, PaymentStatus.pending);
      expect(restored.notes, 'Sin crema');
    });

    test('copyWith actualiza estado y sincronización', () {
      final order = sampleOrder();
      final updated = order.copyWith(
        status: OrderStatus.ready,
        synced: false,
        paymentStatus: PaymentStatus.paid,
      );
      expect(updated.status, OrderStatus.ready);
      expect(updated.synced, isFalse);
      expect(updated.paymentStatus, PaymentStatus.paid);
      expect(updated.id, order.id);
    });

    test('puede liberar la mesa con copyWith', () {
      final order = sampleOrder();
      final updated = order.copyWith(clearTableNumber: true);
      expect(updated.tableNumber, isNull);
    });
  });

  group('mesas y carrito', () {
    test('mesa conserva estado y pedido actual', () {
      const table = RestaurantTable(
        id: 'table-3',
        number: 3,
        status: TableStatus.esperandoPedido,
        capacity: 4,
        currentOrderId: 'order-2',
      );
      final restored = RestaurantTable.fromJson(table.toJson());
      expect(restored.status, TableStatus.esperandoPedido);
      expect(restored.currentOrderId, 'order-2');
      expect(restored.copyWith(status: TableStatus.libre).status,
          TableStatus.libre);
      expect(restored.copyWith(clearOrder: true).currentOrderId, isNull);
    });

    test('línea de carrito calcula total', () {
      const line = CartLine(
        menuItemId: 'item-ajiaco',
        name: 'Ajiaco',
        price: 32900,
        quantity: 3,
        emoji: '🍲',
      );
      expect(line.total, 98700);
      expect(line.copyWith(quantity: 1).total, 32900);
    });
  });

  group('formato de moneda', () {
    test('usa separadores de miles colombianos', () {
      expect(formatCop(38900), r'$ 38.900');
      expect(formatCop(14500), r'$ 14.500');
      expect(formatCop(1000), r'$ 1.000');
      expect(formatCop(1000000), r'$ 1.000.000');
      expect(formatCop(0), r'$ 0');
    });

    test('formatea fechas y horas', () {
      final date = DateTime(2026, 11, 22, 9, 5);
      expect(formatDateTime(date), '22/11/2026 09:05');
      expect(formatShortDate(date), '22/11');
    });
  });
}
