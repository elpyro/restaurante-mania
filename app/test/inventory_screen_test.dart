import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/data/repository.dart';
import 'package:app/core/models/role.dart';
import 'package:app/features/inventory/inventory_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<RestaurantRepository> loadRepository(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);
    return repository;
  }

  Future<void> pumpInventory(WidgetTester tester, RestaurantRepository repo) {
    return tester.pumpWidget(
      ChangeNotifierProvider<RestaurantRepository>.value(
        value: repo,
        child: const MaterialApp(home: InventoryScreen(showAppBar: true)),
      ),
    );
  }

  testWidgets('el botón Surtir suma la cantidad al stock y confirma', (
    tester,
  ) async {
    final repository = await loadRepository(tester);
    repository.loginAs(UserRole.admin);
    await pumpInventory(tester, repository);
    await tester.pumpAndSettle();

    final before = repository.ingredientById('masa-maiz')!;
    expect(find.text('Surtir'), findsWidgets);

    await tester.tap(find.text('Surtir').first);
    await tester.pumpAndSettle();
    expect(find.text('Surtir ${before.name}'), findsOneWidget);
    expect(find.text('Stock actual: ${before.stockLabel}'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '250');
    await tester.pumpAndSettle();
    expect(find.textContaining('Nuevo stock: 8250 g'), findsOneWidget);

    await tester.tap(find.text('Confirmar surtido'));
    await tester.pumpAndSettle();

    final after = repository.ingredientById('masa-maiz')!;
    expect(after.stock, before.stock + 250);
    expect(find.textContaining('Surtido ${before.name}'), findsOneWidget);
    expect(find.textContaining('Stock: ${after.stockLabel}'), findsWidgets);
    expect(find.text('¡Surtido!'), findsOneWidget);
    expect(find.text('Stock actualizado'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.text('¡Surtido!'), findsNothing);
  });

  testWidgets('rechaza cantidades vacías o menores a cero', (tester) async {
    final repository = await loadRepository(tester);
    repository.loginAs(UserRole.admin);
    await pumpInventory(tester, repository);
    await tester.pumpAndSettle();

    final before = repository.ingredientById('masa-maiz')!;
    await tester.tap(find.text('Surtir').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '0');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar surtido'));
    await tester.pumpAndSettle();

    expect(find.text('Escribe una cantidad mayor a cero.'), findsOneWidget);
    expect(repository.ingredientById('masa-maiz')!.stock, before.stock);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Surtir ${before.name}'), findsNothing);
  });

  testWidgets('los roles sin permiso de menú no ven el botón Surtir', (
    tester,
  ) async {
    final repository = await loadRepository(tester);
    repository.loginAs(UserRole.waiter);
    await pumpInventory(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('Surtir'), findsNothing);
  });
}
