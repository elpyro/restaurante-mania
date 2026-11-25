import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/data/repository.dart';
import 'package:app/core/models/restaurant_appearance.dart';
import 'package:app/core/models/role.dart';
import 'package:app/features/appearance/appearance_screen.dart';
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

  testWidgets('el tile de Apariencia abre la pantalla y guarda el preset elegido', (
    tester,
  ) async {
    final repository = await loadRepository(tester);
    repository.loginAs(UserRole.admin);

    await tester.pumpWidget(
      ChangeNotifierProvider<RestaurantRepository>.value(
        value: repository,
        child: const MaterialApp(home: Scaffold(body: MoreScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Apariencia'), findsOneWidget);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);

    await tester.tap(find.text('Apariencia'));
    await tester.pumpAndSettle();

    expect(find.byType(AppearanceScreen), findsOneWidget);
    for (final label in ['Manía', 'Fuego', 'Verde', 'Noche']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      find.text('Sin sesión · inicia sesión para publicar'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNWidgets(8));
    expect(find.text('Redes sociales y ubicación'), findsOneWidget);

    await tester.tap(find.text('Noche'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Restablecer'),
      500.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Guardar en la web'), findsOneWidget);
    expect(find.text('Recargar desde la web'), findsOneWidget);
    expect(find.text('Restablecer'), findsOneWidget);

    await tester.ensureVisible(find.text('Guardar en la web'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar en la web'));
    await tester.pumpAndSettle();

    expect(repository.restaurantAppearance.preset, AppearancePreset.noche);
    expect(repository.hasPendingRestaurantConfig, isTrue);
  });

  testWidgets('guarda redes sociales y mapa completando el protocolo', (
    tester,
  ) async {
    final repository = await loadRepository(tester);
    repository.loginAs(UserRole.admin);

    await tester.pumpWidget(
      ChangeNotifierProvider<RestaurantRepository>.value(
        value: repository,
        child: const MaterialApp(home: AppearanceScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(4), 'instagram.com/mania');
    await tester.enterText(fields.at(5), 'https://tiktok.com/@mania');
    await tester.enterText(fields.at(6), 'facebook.com/mania');
    await tester.enterText(fields.at(7), 'maps.google.com/?q=medellin');
    await tester.tap(find.text('Guardar en la web'));
    await tester.pumpAndSettle();

    final appearance = repository.restaurantAppearance;
    expect(appearance.instagramUrl, 'https://instagram.com/mania');
    expect(appearance.tiktokUrl, 'https://tiktok.com/@mania');
    expect(appearance.facebookUrl, 'https://facebook.com/mania');
    expect(appearance.gpsUrl, 'https://maps.google.com/?q=medellin');
  });

  testWidgets('restablecer devuelve los textos y colores por defecto', (
    tester,
  ) async {
    final repository = await loadRepository(tester);
    await repository.updateRestaurantAppearance(
      RestaurantAppearance.defaults.copyWith(
        slogan: 'Eslogan temporal',
        heroTitle: 'Título temporal',
        preset: AppearancePreset.fuego,
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<RestaurantRepository>.value(
        value: repository,
        child: const MaterialApp(home: AppearanceScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      'Eslogan temporal',
    );

    await tester.scrollUntilVisible(
      find.text('Restablecer'),
      500.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restablecer'));
    await tester.pumpAndSettle();

    expect(
      repository.restaurantAppearance,
      RestaurantAppearance.defaults,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      RestaurantAppearance.defaults.slogan,
    );
    await tester.scrollUntilVisible(
      find.text('Fuego'),
      -500.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Fuego'), findsOneWidget);
  });
}
