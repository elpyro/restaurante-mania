import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/data/repository.dart';
import 'package:app/core/models/role.dart';
import 'package:app/features/dashboard/dashboard_screen.dart';
import 'package:app/features/inventory_losses/inventory_losses_screen.dart';
import 'package:app/features/more/more_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<RestaurantRepository> loadRepository(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);
    return repository;
  }

  testWidgets('el administrador abre pérdidas desde Más y ve Registrar pérdida',
      (tester) async {
    final repository = await loadRepository(tester);
    repository.loginAs(UserRole.admin);

    await tester.pumpWidget(
      ChangeNotifierProvider<RestaurantRepository>.value(
        value: repository,
        child: const MaterialApp(home: Scaffold(body: MoreScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pérdidas de inventario'), findsOneWidget);
    await tester.tap(find.text('Pérdidas de inventario'));
    await tester.pumpAndSettle();

    expect(find.byType(InventoryLossesScreen), findsOneWidget);
    expect(find.text('Sin pérdidas registradas'), findsOneWidget);
    expect(find.text('Registrar pérdida'), findsOneWidget);
  });

  testWidgets('el cocinero registra pérdidas desde Inicio', (tester) async {
    final repository = await loadRepository(tester);
    repository.loginAs(UserRole.cook);

    await tester.pumpWidget(
      ChangeNotifierProvider<RestaurantRepository>.value(
        value: repository,
        child: MaterialApp(
          home: DashboardScreen(onNavigate: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Registrar pérdida'), findsWidgets);
    expect(find.text('Nuevo pedido'), findsNothing);

    await tester.tap(find.text('Registrar pérdida').first);
    await tester.pumpAndSettle();

    expect(find.byType(RegisterLossScreen), findsOneWidget);
    expect(find.text('Tomar foto'), findsOneWidget);
    expect(find.text('Guardar pérdida'), findsOneWidget);
  });

  testWidgets('el mesero no ve el botón de pérdidas en Más', (tester) async {
    final repository = await loadRepository(tester);
    repository.loginAs(UserRole.waiter);

    await tester.pumpWidget(
      ChangeNotifierProvider<RestaurantRepository>.value(
        value: repository,
        child: const MaterialApp(home: Scaffold(body: MoreScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pérdidas de inventario'), findsNothing);
  });
}
