import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/app.dart';
import 'package:app/core/data/repository.dart';

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

  testWidgets('muestra login y entra al dashboard de administrador',
      (tester) async {
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
    expect(find.text('Acciones rápidas'), findsOneWidget);
  });

  testWidgets('permite iniciar sesión con correo y contraseña',
      (tester) async {
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

  testWidgets('el mesero ve sus pestañas y puede cerrar sesión',
      (tester) async {
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
}
