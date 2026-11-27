import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/data/repository.dart';
import 'package:app/core/models/order.dart';
import 'package:app/core/models/role.dart';
import 'package:app/core/widgets/order_card.dart';
import 'package:app/features/orders/orders_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('el combobox de orden cambia el orden de los pedidos', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);
    repository.loginAs(UserRole.admin);

    await tester.pumpWidget(
      ChangeNotifierProvider<RestaurantRepository>.value(
        value: repository,
        child: const MaterialApp(
          home: OrdersScreen(initialFilter: 'all'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    List<String> visibleCodes() => tester
        .widgetList<OrderCard>(find.byType(OrderCard))
        .map((card) => card.order.code)
        .toList();

    // La pantalla agrupa por mesa: el orden de los grupos sigue la primera
    // aparición en la lista ordenada y los pedidos de cada mesa conservan
    // el orden elegido.
    List<String> groupedCodes(List<Order> sorted) {
      final groups = <int?, List<Order>>{};
      for (final order in sorted) {
        groups.putIfAbsent(order.tableNumber, () => <Order>[]).add(order);
      }
      return groups.values.expand((group) => group).map((o) => o.code).toList();
    }

    final byCreation = [...repository.orders]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final oldestFirst = visibleCodes();
    expect(oldestFirst, groupedCodes(byCreation));

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Mayor total primero'), findsOneWidget);
    await tester.tap(find.text('Mayor total primero'));
    await tester.pumpAndSettle();

    final byTotal = [...repository.orders]
      ..sort((a, b) => b.total.compareTo(a.total));
    final totalFirst = visibleCodes();
    expect(totalFirst, groupedCodes(byTotal));
    expect(totalFirst, isNot(oldestFirst));
    expect(find.text('Mayor total primero'), findsWidgets);
  });
}
