import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/data/repository.dart';
import 'package:app/core/models/order.dart';
import 'package:app/core/models/restaurant_settings.dart';
import 'package:app/core/services/receipt_print_service.dart';
import 'package:app/features/orders/order_detail_screen.dart';

Order _sampleOrder() => Order(
      id: 'order-qa',
      code: 'RM-20261125-1234',
      customerName: 'Cliente QA',
      customerPhone: '3001234567',
      type: OrderType.table,
      tableNumber: 4,
      items: const [
        OrderItem(
          menuItemId: 'item-1',
          name: 'Hamburguesa',
          price: 25000,
          quantity: 2,
          emoji: '🍔',
        ),
      ],
      subtotal: 50000,
      tax: 0,
      total: 50000,
      status: OrderStatus.delivered,
      paymentStatus: PaymentStatus.paid,
      paymentMethod: PaymentMethod.cash,
      notes: 'Sin cebolla',
      createdAt: DateTime(2026, 11, 25, 13, 30),
      updatedAt: DateTime(2026, 11, 25, 13, 45),
      source: 'app',
      synced: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('genera un PDF de recibo válido con los datos del pedido', () async {
    final bytes = await ReceiptPrintService(
      order: _sampleOrder(),
      settings: RestaurantSettings.defaults,
    ).buildBytes();

    expect(bytes, isA<Uint8List>());
    expect(bytes.isNotEmpty, isTrue);
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
  });

  testWidgets('el detalle de pedido ofrece imprimir recibo', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = await RestaurantRepository.load(watchConnectivity: false);
    addTearDown(repository.dispose);
    final order = repository.orders.first;

    await tester.pumpWidget(
      ChangeNotifierProvider<RestaurantRepository>.value(
        value: repository,
        child: MaterialApp(home: OrderDetailScreen(orderId: order.id)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Imprimir recibo'), findsOneWidget);
    expect(find.byIcon(Icons.print_outlined), findsOneWidget);
  });
}
