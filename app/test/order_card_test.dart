import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/models/order.dart';
import 'package:app/core/widgets/order_card.dart';

Order _sampleOrder({required String source}) => Order(
      id: 'order-$source',
      code: 'RM-TEST-$source',
      customerName: 'Cliente prueba',
      customerPhone: '3001234567',
      type: OrderType.delivery,
      tableNumber: null,
      items: const [
        OrderItem(
          menuItemId: 'item-1',
          name: 'Hamburguesa',
          price: 25000,
          quantity: 1,
          emoji: '🍔',
        ),
      ],
      subtotal: 25000,
      tax: 0,
      total: 25000,
      status: OrderStatus.pending,
      paymentStatus: PaymentStatus.pending,
      paymentMethod: PaymentMethod.cash,
      notes: '',
      createdAt: DateTime(2026, 11, 25, 13, 30),
      updatedAt: DateTime(2026, 11, 25, 13, 30),
      source: source,
      synced: true,
    );

void main() {
  testWidgets('los pedidos de la web usan un tono azul distinto', (tester) async {
    final webOrder = _sampleOrder(source: 'web');
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: OrderCard(order: webOrder))),
    );

    final material = find.ancestor(
      of: find.text(webOrder.code),
      matching: find.byType(Material),
    ).evaluate().first.widget as Material;
    expect(material.color, const Color(0xFFF0F9FF));
    expect(find.text('Web'), findsOneWidget);
  });

  testWidgets('los pedidos del local mantienen el tono normal', (tester) async {
    final localOrder = _sampleOrder(source: 'app');
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: OrderCard(order: localOrder))),
    );

    final material = find.ancestor(
      of: find.text(localOrder.code),
      matching: find.byType(Material),
    ).evaluate().first.widget as Material;
    expect(material.color, Colors.white);
    expect(find.text('Web'), findsNothing);
  });
}
