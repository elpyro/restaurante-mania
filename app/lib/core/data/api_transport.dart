import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:app/core/data/tenant.dart';
import 'package:app/core/services/auth_service.dart';

/// Respuesta uniforme para el transporte web y el transporte directo a Firestore.
class ApiResponse {
  const ApiResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;

  bool get ok => statusCode >= 200 && statusCode < 300;

  Map<String, dynamic>? get json {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  List<dynamic>? get jsonList {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is List<dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

/// Error de autorización del transporte. El repositorio lo traduce a un
/// «relogin de Firebase» sin borrar las colas offline.
class ApiAuthException implements Exception {
  const ApiAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class ApiTransport {
  Future<ApiResponse> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool authorized = true,
  });
}

/// Transporte原有: habla con la web pública (Netlify en producción o el
/// servidor local en QA). Añade el idToken a todas las peticiones cuando existe.
class WebApiTransport implements ApiTransport {
  WebApiTransport({
    required this.baseUrl,
    required this.auth,
    required this.tenantId,
  });

  final String baseUrl;
  final AuthService auth;
  final String tenantId;

  @override
  Future<ApiResponse> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool authorized = true,
  }) async {
    final parsed = Uri.parse('$baseUrl$path');
    final uri = query == null || query.isEmpty
        ? parsed
        : parsed.replace(
            queryParameters: <String, String>{
              ...parsed.queryParameters,
              ...query,
            },
          );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.openUrl(method, uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(tenantHeader, tenantId);
      if (body != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      }
      if (authorized) {
        // El adaptador web debe funcionar también en QA sin sesión Firebase:
        // las rutas públicas no exigen token y las protegidas responderán 401.
        String? token;
        try {
          token = await auth.getIdToken();
        } catch (_) {
          // Sin almacén seguro (tests/desktop) seguimos sin token: las rutas
          // públicas responden igual y las protegidas devuelven 401.
          token = null;
        }
        if (token != null && token.isNotEmpty) {
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
      }
      // `write` usa latin1 en HttpClientRequest: codificamos explícitamente en
      // UTF-8 para no romper acentos ("Título", "¿Hambre?", etc.).
      if (body != null) request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      // Solo 401 = sesión vencida/ausente. 403 es falta de permiso (rol):
      // no debe disparar re-login, la petición simplemente falla.
      if (response.statusCode == 401) {
        throw ApiAuthException('Sesión Firebase vencida ($path)');
      }
      return ApiResponse(response.statusCode, text);
    } on ApiAuthException {
      rethrow;
    } catch (_) {
      return const ApiResponse(0, '');
    } finally {
      client.close(force: true);
    }
  }
}

/// Transporte de producción: habla directamente con Firestore REST usando el
/// idToken de Firebase Auth. El tenant y el rol se validan en `firestore.rules`,
/// así que el dispositivo depende únicamente de Firestore como fuente de verdad.
class FirestoreTransport implements ApiTransport {
  FirestoreTransport({
    required this.auth,
    required this.projectId,
    required this.tenantId,
  });

  final AuthService auth;
  final String projectId;
  final String tenantId;

  /// Proyecto Firebase de producción. Se puede sobreescribir con
  /// `--dart-define=FIREBASE_PROJECT_ID=...`.
  static const _defaultProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'restaurante-mania-e47a0',
  );

  /// Clave pública de Firebase Web (no es un secreto).
  static String get _apiKey => AuthService.firebaseApiKey;

  factory FirestoreTransport.fromEnvironment({
    required AuthService auth,
    required String tenantId,
  }) {
    return FirestoreTransport(
      auth: auth,
      projectId: _defaultProjectId,
      tenantId: tenantId,
    );
  }

  String get _base =>
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/tenants/${Uri.encodeComponent(tenantId)}';

  @override
  Future<ApiResponse> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool authorized = true,
  }) async {
    if (_apiKey.isEmpty) {
      return const ApiResponse(0, 'Falta FIREBASE_WEB_API_KEY');
    }
    final cleanPath = path.split('?').first;

    // Health check no requiere token.
    if (cleanPath == '/api/health') {
      return ApiResponse(
        200,
        jsonEncode({
          'mode': 'firestore',
          'tenantId': tenantId,
          'projectId': projectId,
        }),
      );
    }

    String token = '';
    if (authorized) {
      try {
        token = await auth.getIdToken();
      } on AuthException catch (error) {
        throw ApiAuthException(error.message);
      }
      if (token.isEmpty) throw const ApiAuthException('Sin idToken de Firebase');
    }

    final route = _resolve(cleanPath, method, query ?? const <String, String>{});
    if (route == null) {
      return ApiResponse(405, jsonEncode({'error': 'Ruta no soportada: $path'}));
    }

    // Firestore REST PATCH **reemplaza** el documento si no se envía
    // `updateMask`. Enviamos `updateMask.fieldPaths` repetido por cada campo
    // del body para convertir todos los PATCH en merge parcial.
    final maskPaths = route.verb == 'PATCH' && body != null && body.isNotEmpty
        ? body.keys.toList(growable: false)
        : const <String>[];

    final queryString = buildQueryString(
      parameters: route.queryParameters,
      maskPaths: maskPaths,
    );
    final uri = Uri.parse(
      '$_base/${route.collection}${route.id == null ? '' : '/${Uri.encodeComponent(route.id!)}'}',
    ).replace(query: queryString.isEmpty ? null : queryString);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.openUrl(route.verb, uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      request.headers.set('X-Goog-Api-Key', _apiKey);
      if (body != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.add(utf8.encode(jsonEncode({'fields': encodeFields(body)})));
      }
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      // Solo 401 = sesión vencida/ausente. 403 es falta de permiso (rol
      // dentro del tenant): la petición falla sin marcar re-login.
      if (response.statusCode == 401) {
        throw ApiAuthException('Firestore rechazó la sesión ($path)');
      }
      if ((response.statusCode < 200 || response.statusCode >= 300) &&
          text.isNotEmpty) {
        return ApiResponse(response.statusCode, text);
      }
      return ApiResponse(response.statusCode, _toApiBody(route, text, method));
    } on ApiAuthException {
      rethrow;
    } catch (_) {
      return const ApiResponse(0, '');
    } finally {
      client.close(force: true);
    }
  }

  /// Construye un query string con `updateMask.fieldPaths` **repetido** por
  /// cada campo (Firestore REST no admite una lista como valor único).
  @visibleForTesting
  static String buildQueryString({
    Map<String, String> parameters = const {},
    List<String> maskPaths = const [],
  }) {
    final pairs = <String>[
      for (final entry in parameters.entries)
        '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
      for (final fieldPath in maskPaths)
        'updateMask.fieldPaths=${Uri.encodeQueryComponent(fieldPath)}',
    ];
    return pairs.join('&');
  }

  static Map<String, Map<String, dynamic>> encodeFields(Map<String, dynamic> data) {
    return data.map((key, value) => MapEntry(key, encodeValue(value)));
  }

  static Map<String, dynamic> encodeValue(dynamic value) {
    if (value == null) return {'nullValue': null};
    if (value is String) return {'stringValue': value};
    if (value is bool) return {'booleanValue': value};
    if (value is int) return {'integerValue': value.toString()};
    if (value is num) return {'doubleValue': value.toDouble()};
    if (value is DateTime) return {'timestampValue': value.toUtc().toIso8601String()};
    if (value is List) {
      return {
        'arrayValue': {
          'values': value.map((entry) => encodeValue(entry)).toList(),
        },
      };
    }
    if (value is Map) {
      return {
        'mapValue': {
          'fields': encodeFields(Map<String, dynamic>.from(value)),
        },
      };
    }
    return {'stringValue': value.toString()};
  }

  static dynamic decodeValue(Map<String, dynamic> value) {
    if (value.containsKey('nullValue')) return null;
    if (value.containsKey('stringValue')) return value['stringValue'];
    if (value.containsKey('booleanValue')) return value['booleanValue'];
    if (value.containsKey('integerValue')) {
      return int.tryParse('${value['integerValue']}') ?? 0;
    }
    if (value.containsKey('doubleValue')) {
      return double.tryParse('${value['doubleValue']}') ?? 0.0;
    }
    if (value.containsKey('timestampValue')) return value['timestampValue'];
    final array = value['arrayValue'];
    if (array is Map<String, dynamic>) {
      final values = array['values'];
      if (values is List) {
        return values
            .whereType<Map<String, dynamic>>()
            .map((entry) => decodeValue(entry))
            .toList();
      }
      return const <dynamic>[];
    }
    final map = value['mapValue'];
    if (map is Map<String, dynamic>) {
      final fields = map['fields'];
      if (fields is Map<String, dynamic>) return decodeFields(fields);
      return <String, dynamic>{};
    }
    return null;
  }

  static Map<String, dynamic> decodeFields(Map<String, dynamic> fields) {
    return fields.map(
      (key, value) => MapEntry(
        key,
        value is Map<String, dynamic> ? decodeValue(value) : null,
      ),
    );
  }

  static List<Map<String, dynamic>> decodeDocuments(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return const [];
    final documents = decoded['documents'];
    if (documents is! List) return const [];
    return documents
        .whereType<Map<String, dynamic>>()
        .map((doc) {
          final fields = doc['fields'];
          if (fields is! Map<String, dynamic>) return <String, dynamic>{};
          final data = decodeFields(fields);
          final name = doc['name'];
          if (name is String && !data.containsKey('id')) {
            data['id'] = name.split('/').last;
          }
          return data;
        })
        .toList();
  }

  static Map<String, dynamic> decodeDocument(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return const {};
    final fields = decoded['fields'];
    if (fields is! Map<String, dynamic>) return const {};
    final data = decodeFields(fields);
    final name = decoded['name'];
    if (name is String && !data.containsKey('id')) {
      data['id'] = name.split('/').last;
    }
    return data;
  }

  String _toApiBody(_Route route, String text, String method) {
    if (text.isEmpty) return jsonEncode(<String, dynamic>{});
    if (route.list) {
      final documents = decodeDocuments(text);
      final body = <String, dynamic>{route.responseKey: documents};
      if (route.collection == 'cashShifts') {
        for (final document in documents) {
          if (document['status'] != 'closed') {
            body['currentShift'] = document;
            break;
          }
        }
      }
      return jsonEncode(body);
    }
    if (method == 'GET') {
      final data = decodeDocument(text);
      return jsonEncode({route.singleKey: data});
    }
    if (text.trim().startsWith('{')) {
      final data = decodeDocument(text);
      if (data.isNotEmpty) return jsonEncode({route.singleKey: data});
    }
    return text;
  }

  _Route? _resolve(String path, String method, Map<String, String> query) {
    if (path == '/api/users') {
      if (method == 'GET') return _Route.list('users', 'users');
      if (method == 'POST') {
        return _Route.create('users', 'user', id: query['id']);
      }
      if (method == 'DELETE') {
        return _Route.delete('users', query['id'] ?? '');
      }
    }
    final userMatch = RegExp(r'^/api/users/([^/]+)$').firstMatch(path);
    if (userMatch != null && method == 'GET') {
      return _Route.get('users', Uri.decodeComponent(userMatch.group(1)!), 'user');
    }
    if (path == '/api/orders') {
      if (method == 'GET') return _Route.list('orders', 'orders');
      if (method == 'POST') {
        return _Route.create('orders', 'order', id: query['id']);
      }
    }
    final orderMatch = RegExp(r'^/api/orders/([^/]+)$').firstMatch(path);
    if (orderMatch != null && method == 'PATCH') {
      return _Route.patch('orders', Uri.decodeComponent(orderMatch.group(1)!), 'order');
    }
    if (path == '/api/customers') {
      if (method == 'GET') return _Route.list('customers', 'customers');
      if (method == 'POST') {
        return _Route.create('customers', 'customer', id: query['id']);
      }
    }
    if (path == '/api/visits') {
      // La web guarda el feed en `webVisits`; las reglas y los índices usan esa
      // colección, no `visits`.
      if (method == 'GET') return _Route.list('webVisits', 'visits');
      if (method == 'POST') {
        return _Route.create('webVisits', 'visit', id: query['id']);
      }
    }
    if (path == '/api/menu' && method == 'GET') {
      // Catálogo completo: la web devuelve los platos normalizados y el
      // transporte directo lista los documentos de `menuItems`.
      return _Route.list('menuItems', 'items');
    }
    if (path == '/api/menu/categories' && method == 'GET') {
      // Ruta interna del modo directo (la web ya incluye las categorías en
      // `/api/menu`).
      return _Route.list('categories', 'categories');
    }
    if (path == '/api/menu/status' && method == 'GET') {
      return _Route.list('menuItems', 'items');
    }
    final menuMatch = RegExp(r'^/api/menu/([^/]+)$').firstMatch(path);
    if (menuMatch != null && method == 'PATCH') {
      return _Route.patch('menuItems', Uri.decodeComponent(menuMatch.group(1)!), 'item');
    }
    if (path == '/api/ingredients' && method == 'GET') {
      return _Route.list('ingredients', 'ingredients');
    }
    final ingredientMatch = RegExp(r'^/api/ingredients/([^/]+)$').firstMatch(path);
    if (ingredientMatch != null) {
      final id = Uri.decodeComponent(ingredientMatch.group(1)!);
      if (method == 'PATCH') return _Route.patch('ingredients', id, 'ingredient');
      if (method == 'DELETE') return _Route.delete('ingredients', id);
    }
    if (path == '/api/inventory-losses') {
      if (method == 'GET') return _Route.list('inventoryLosses', 'losses');
      if (method == 'POST') {
        return _Route.create('inventoryLosses', 'loss', id: query['id']);
      }
    }
    if (path == '/api/restaurant/config') {
      if (method == 'GET') {
        return _Route.get('restaurant', 'config', 'config');
      }
      if (method == 'PATCH') {
        return _Route.patch('restaurant', 'config', 'config');
      }
    }
    if (path == '/api/cash-shifts') {
      if (method == 'GET') return _Route.list('cashShifts', 'shifts');
      if (method == 'POST') {
        return _Route.create('cashShifts', 'shift', id: query['id']);
      }
    }
    if (path == '/api/cash-shifts/close' && method == 'POST') {
      return _Route.patch('cashShifts', query['id'] ?? '', 'shift');
    }
    return null;
  }
}

class _Route {
  const _Route._({
    required this.verb,
    required this.collection,
    this.id,
    this.list = false,
    this.responseKey = 'items',
    this.singleKey = 'item',
  });

  /// Parámetros extra de query (actualmente vacío; los `updateMask` se añaden
  /// en `send`, no aquí).

  factory _Route.list(String collection, String key) => _Route._(
        verb: 'GET',
        collection: collection,
        list: true,
        responseKey: key,
      );

  factory _Route.get(String collection, String id, String key) => _Route._(
        verb: 'GET',
        collection: collection,
        id: id,
        singleKey: key,
      );

  factory _Route.create(String collection, String key, {String? id}) => _Route._(
        // Firestore no acepta `documentId` como query param: para conservar el
        // id local (y que reintentos offline sean idempotentes) se usa PATCH
        // sobre la ruta del documento, que crea el documento si no existe.
        verb: id == null ? 'POST' : 'PATCH',
        collection: collection,
        id: id,
        singleKey: key,
      );

  factory _Route.patch(String collection, String id, String key) => _Route._(
        verb: 'PATCH',
        collection: collection,
        id: id,
        singleKey: key,
      );

  factory _Route.delete(String collection, String id) => _Route._(
        verb: 'DELETE',
        collection: collection,
        id: id,
      );

  final String verb;
  final String collection;
  final String? id;
  final bool list;
  final String responseKey;
  final String singleKey;
  final Map<String, String> queryParameters = const <String, String>{};
}
