import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/data/repository.dart';
import 'package:app/core/data/seed_data.dart';
import 'package:app/core/models/restaurant_appearance.dart';
import 'package:app/core/services/auth_service.dart';

/// Igual que las pruebas de inventario: `HttpServer` real y sin binding de
/// flutter_test, que intercepta `HttpClient` y devuelve 400.
class _RecordedRequest {
  _RecordedRequest({
    required this.method,
    required this.path,
    required this.authorization,
    required this.body,
  });

  final String method;
  final String path;
  final String? authorization;
  final Map<String, dynamic> body;
}

class _SignedOutAuth extends AuthService {
  @override
  Future<bool> get isSignedIn async => false;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<AuthService> signedInAuth() async {
    FlutterSecureStorage.setMockInitialValues({
      AuthService.idTokenKey: 'firebase-token',
      AuthService.refreshTokenKey: 'firebase-refresh',
      AuthService.expiryKey: DateTime.now()
          .add(const Duration(hours: 1))
          .toIso8601String(),
    });
    return AuthService(storage: FlutterSecureStorage());
  }

  Future<RestaurantRepository> openRepository(
    HttpServer server,
    AuthService auth,
  ) async {
    SharedPreferences.setMockInitialValues({
      'rm_server_url_v1': 'http://127.0.0.1:${server.port}',
    });
    final repository = await RestaurantRepository.load(
      watchConnectivity: true,
      authService: auth,
    );
    // connectivity_plus no informa red dentro del runner de tests: forzamos
    // online para que la cola se comporte como en un dispositivo conectado.
    await repository.setOnlineForDemo(true);
    return repository;
  }

  Future<void> waitFor(bool Function() condition) async {
    for (var attempt = 0; attempt < 200; attempt++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('el PATCH de apariencia envía Authorization Bearer y el cuerpo del contrato',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final patches = <_RecordedRequest>[];
    server.listen((request) async {
      final bodyText = await utf8.decoder.bind(request).join();
      final response = request.response..headers.contentType = ContentType.json;
      Map<String, dynamic> body = {};
      try {
        body = jsonDecode(bodyText) as Map<String, dynamic>;
      } catch (_) {}
      if (request.method == 'PATCH' &&
          request.uri.path == '/api/restaurant/config') {
        patches.add(
          _RecordedRequest(
            method: request.method,
            path: request.uri.path,
            authorization: request.headers.value(HttpHeaders.authorizationHeader),
            body: body,
          ),
        );
      }
      response.write(
        jsonEncode({
          'configured': true,
          'config': {
            ...RestaurantAppearance.defaults.toJson(),
            ...body,
          },
          'source': 'firestore',
        }),
      );
      await response.close();
    });

    final repository = await openRepository(server, await signedInAuth());
    addTearDown(() async {
      repository.dispose();
      await server.close();
    });

    const custom = RestaurantAppearance(
      slogan: 'Slogan desde la app',
      heroTitle: 'Título desde la app',
      heroDescription: 'Descripción desde la app',
      heroBadge: '🔥 Edición especial',
      preset: AppearancePreset.verde,
      instagramUrl: 'https://instagram.com/mania',
      facebookUrl: 'https://facebook.com/mania',
      gpsUrl: 'https://maps.google.com/?q=medellin',
    );
    await repository.updateRestaurantAppearance(custom);

    expect(patches, hasLength(1));
    expect(patches.single.authorization, 'Bearer firebase-token');
    expect(
      patches.single.body.keys.toSet(),
      {'slogan', 'heroTitle', 'heroDescription', 'heroBadge', 'appearance'},
    );
    expect(patches.single.body['appearance'], {
      'preset': 'verde',
      'bannerUrl': null,
      'logoUrl': null,
      'socialLinks': {
        'instagram': 'https://instagram.com/mania',
        'tiktok': isNull,
        'facebook': 'https://facebook.com/mania',
      },
      'gpsUrl': 'https://maps.google.com/?q=medellin',
    });
    expect(patches.single.body['slogan'], custom.slogan);
    expect(repository.restaurantAppearance, custom);
    expect(repository.hasPendingRestaurantConfig, isFalse);
  });

  test('offline encola el cambio, conserva el valor local y hace flush al volver',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final patches = <_RecordedRequest>[];
    var serverAppearance = RestaurantAppearance.defaults;
    server.listen((request) async {
      final bodyText = await utf8.decoder.bind(request).join();
      final response = request.response..headers.contentType = ContentType.json;
      if (request.method == 'PATCH' &&
          request.uri.path == '/api/restaurant/config') {
        final body = jsonDecode(bodyText) as Map<String, dynamic>;
        patches.add(
          _RecordedRequest(
            method: request.method,
            path: request.uri.path,
            authorization: request.headers.value(HttpHeaders.authorizationHeader),
            body: body,
          ),
        );
        serverAppearance = RestaurantAppearance.fromJson(body);
      }
      response.write(
        jsonEncode({
          'configured': true,
          'config': serverAppearance.toJson(),
          'source': 'firestore',
        }),
      );
      await response.close();
    });

    final repository = await openRepository(server, await signedInAuth());
    addTearDown(() async {
      repository.dispose();
      await server.close();
    });

    const offlineChange = RestaurantAppearance(
      slogan: 'Cambio sin conexión',
      heroTitle: 'Título offline',
      heroDescription: 'Descripción offline',
      heroBadge: '⚡ Offline',
      preset: AppearancePreset.fuego,
    );

    await repository.setOnlineForDemo(false);
    await repository.updateRestaurantAppearance(offlineChange);
    expect(patches, isEmpty);
    expect(repository.hasPendingRestaurantConfig, isTrue);

    // Un pull remoto no debe sobrescribir el cambio pendiente.
    await repository.pullServerRestaurantConfig();
    expect(repository.restaurantAppearance, offlineChange);

    await repository.setOnlineForDemo(true);
    await waitFor(() => !repository.hasPendingRestaurantConfig && patches.isNotEmpty);

    expect(patches, hasLength(1));
    expect(patches.single.authorization, 'Bearer firebase-token');
    expect(patches.single.body['appearance'], {
      'preset': 'fuego',
      'bannerUrl': null,
      'logoUrl': null,
      'socialLinks': {
        'instagram': isNull,
        'tiktok': isNull,
        'facebook': isNull,
      },
      'gpsUrl': isNull,
    });
    expect(repository.restaurantAppearance, offlineChange);
    expect(repository.hasPendingRestaurantConfig, isFalse);
  });

  test('un 401 conserva la cola y exige volver a iniciar sesión', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var patchCount = 0;
    server.listen((request) async {
      await request.drain<void>();
      final response = request.response..headers.contentType = ContentType.json;
      if (request.method == 'PATCH' &&
          request.uri.path == '/api/restaurant/config') {
        patchCount++;
        response.statusCode = 401;
      }
      response.write('{}');
      await response.close();
    });

    final repository = await openRepository(server, await signedInAuth());
    addTearDown(() async {
      repository.dispose();
      await server.close();
    });

    await repository.setOnlineForDemo(false);
    await repository.updateRestaurantAppearance(
      RestaurantAppearance.defaults.copyWith(slogan: 'Cambio sin autorizar'),
    );
    await repository.setOnlineForDemo(true);
    await waitFor(() => patchCount > 0);

    expect(patchCount, 1);
    expect(repository.hasPendingRestaurantConfig, isTrue);
    expect(repository.needsFirebaseReLogin, isTrue);
    expect(repository.hasFirebaseSession, isFalse);
  });

  test('sin idToken Firebase se descarta la sesión local y vuelve al login',
      () async {
    SharedPreferences.setMockInitialValues({
      'rm_session_v1': jsonEncode(SeedData.users.first.toJson()),
    });
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
      authService: _SignedOutAuth(),
      requireFirebaseSignIn: true,
    );
    addTearDown(repository.dispose);

    expect(repository.isAuthenticated, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('rm_session_v1'), isNull);
  });

  test('Sincronizar ahora también vacía la cola de apariencia', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var patchCount = 0;
    var rejectPatch = true;
    server.listen((request) async {
      await request.drain<void>();
      final response = request.response..headers.contentType = ContentType.json;
      if (request.method == 'PATCH' &&
          request.uri.path == '/api/restaurant/config') {
        patchCount++;
        if (rejectPatch) response.statusCode = 500;
      }
      response.write('{}');
      await response.close();
    });

    final repository = await openRepository(server, await signedInAuth());
    addTearDown(() async {
      repository.dispose();
      await server.close();
    });

    await repository.updateRestaurantAppearance(
      RestaurantAppearance.defaults.copyWith(slogan: 'Cambio en la cola'),
    );
    await waitFor(() => patchCount >= 1 && repository.hasPendingRestaurantConfig);

    rejectPatch = false;
    await repository.syncPendingOrders();

    expect(patchCount, greaterThanOrEqualTo(2));
    expect(repository.hasPendingRestaurantConfig, isFalse);
  });
}
