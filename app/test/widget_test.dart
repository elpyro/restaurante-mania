import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/app.dart';
import 'package:app/core/data/repository.dart';
import 'package:app/core/models/role.dart';
import 'package:app/features/inventory/inventory_screen.dart';
import 'package:app/features/menu/menu_admin_screen.dart';

/// Los tests corren en un viewport de 800x600 por defecto, demasiado bajo para
/// el login completo y el dashboard. Usamos una superficie tipo teléfono alto
/// para que los widgets estén montados y sean interactivos.
Future<RestaurantRepository> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final repository = await RestaurantRepository.load(watchConnectivity: false);
  addTearDown(repository.dispose);

  await tester.pumpWidget(RestauranteApp(repository: repository));
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('muestra login y entra al dashboard de administrador', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Inicia sesión'), findsOneWidget);
    expect(find.text('Administrador'), findsOneWidget);
    expect(find.text('Cajero'), findsOneWidget);
    expect(find.text('Mesero'), findsOneWidget);
    expect(find.text('Cocinero'), findsOneWidget);

    await tester.tap(find.text('Administrador'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Valentina'), findsWidgets);
    expect(find.text('Ventas hoy'), findsOneWidget);
    expect(find.text('Nuevo pedido'), findsOneWidget);
    expect(find.text('Pedidos'), findsWidgets);
    expect(find.text('Ventas últimos 7 días'), findsNothing);
    expect(find.text('Mesas ocupadas'), findsOneWidget);
    expect(find.text('0/10'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
  });

  testWidgets('admin abre mesas desde la tarjeta sin pestaña en la barra', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Administrador'));
    await tester.pumpAndSettle();

    expect(find.text('Mesas'), findsNothing);
    await tester.tap(find.text('Mesas ocupadas'));
    await tester.pumpAndSettle();

    expect(find.text('10 mesas'), findsOneWidget);
    expect(find.text('Mesas'), findsOneWidget);
  });

  testWidgets('permite iniciar sesión con correo y contraseña', (tester) async {
    await pumpApp(tester);

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'cocina@restaurante.com');
    await tester.enterText(fields.at(1), '1234');
    await tester.tap(find.widgetWithText(FilledButton, 'Ingresar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Jorge'), findsWidgets);
    expect(find.text('Cola de cocina'), findsOneWidget);
    expect(find.text('En preparación'), findsWidgets);
  });

  testWidgets('muestra error con credenciales inválidas', (tester) async {
    await pumpApp(tester);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'nadie@restaurante.com');
    await tester.enterText(fields.at(1), '0000');
    await tester.tap(find.widgetWithText(FilledButton, 'Ingresar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Credenciales inválidas'), findsOneWidget);
  });

  testWidgets('el mesero ve sus pestañas y puede cerrar sesión', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Mesero'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Camila'), findsWidgets);
    expect(find.text('Mesas'), findsWidgets);

    await tester.tap(find.byTooltip('Cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Inicia sesión'), findsOneWidget);
  });

  testWidgets('un plato agotado explica sus insumos y abre Inventario', (
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

    final cafe = repository.ingredientById('cafe')!;
    await repository.adjustIngredientStock('cafe', -cafe.stock);

    await tester.pumpWidget(
      ChangeNotifierProvider<RestaurantRepository>.value(
        value: repository,
        child: const MaterialApp(home: MenuAdminScreen(showAppBar: true)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Agotado (sin insumos)'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'Café');
    await tester.pumpAndSettle();

    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(find.text('No se puede poner disponible'), findsOneWidget);
    expect(find.textContaining('Café'), findsWidgets);
    expect(find.text('Ir a ingredientes'), findsOneWidget);

    // El switch no debió cambiar el estado del plato.
    expect(repository.menuItemById('item-cafe')!.manualUnavailable, isFalse);

    await tester.tap(find.text('Ir a ingredientes'));
    await tester.pumpAndSettle();

    expect(find.byType(InventoryScreen), findsOneWidget);
  });

  testWidgets('reportes arrancan en el turno y ofrecen rangos largos', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Cajero'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reportes'));
    await tester.pumpAndSettle();

    expect(find.text('Ventas del turno actual'), findsOneWidget);
    expect(find.text('Cerrar caja'), findsOneWidget);
    expect(find.text('7 días'), findsNothing);

    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();

    expect(find.text('7 días'), findsOneWidget);
    expect(find.text('30 días'), findsOneWidget);
    expect(find.text('90 días'), findsOneWidget);
    expect(find.text('Personalizado'), findsOneWidget);
  });
}
