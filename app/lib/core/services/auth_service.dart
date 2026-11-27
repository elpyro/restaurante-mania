import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthException implements Exception {
  const AuthException(this.message, {this.code});

  final String message;

  /// Código devuelto por Firebase (por ejemplo `EMAIL_NOT_FOUND`).
  /// Permite distinguir «correo nuevo» de «contraseña incorrecta» al registrar.
  final String? code;

  @override
  String toString() => message;
}

/// Autenticación Firebase mediante la REST API.
///
/// Evita añadir los plugins nativos de Firebase y, por lo tanto, no exige
/// `google-services.json`. Los tokens se guardan en flutter_secure_storage.
class AuthService {
  AuthService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Clave pública de Firebase Web (no es un secreto).
  ///
  /// Orden de resolución:
  ///   1. `--dart-define=FIREBASE_WEB_API_KEY=...` (cualquier build);
  ///   2. clave de producción `restaurante-mania-e47a0` en builds release;
  ///   3. vacía en debug/tests → modo demo.
  ///
  /// La clave pública de la app web se reutiliza para Firestore REST; no
  /// requiere ningún permiso IAM adicional.
  static const _productionFirebaseApiKey =
      'AIzaSyBycOm9eJ1KlhTXwxUcaGx2ZZwvfE5TJns';
  static const _compiledApiKey = String.fromEnvironment(
    'FIREBASE_WEB_API_KEY',
    defaultValue: '',
  );
  static String get firebaseApiKey => _compiledApiKey.isNotEmpty
      ? _compiledApiKey
      : (kReleaseMode ? _productionFirebaseApiKey : '');

  static const idTokenKey = 'rm_firebase_id_token_v1';
  static const refreshTokenKey = 'rm_firebase_refresh_token_v1';
  static const expiryKey = 'rm_firebase_token_expiry_v1';

  static const _tokenMargin = Duration(seconds: 60);
  static const _signInPath = '/v1/accounts:signInWithPassword';
  static const _signUpPath = '/v1/accounts:signUp';
  static const _refreshPath = '/v1/token';
  static const _passwordResetPath = '/v1/accounts:sendOobCode';

  final FlutterSecureStorage _storage;

  /// Sesión válida en el almacén seguro (no comprueba caducidad localmente).
  Future<bool> get isSignedIn async {
    try {
      final token = await _read(idTokenKey);
      return token != null && token.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on MissingPluginException {
      throw const AuthException(
        'El almacenamiento seguro no está disponible en este dispositivo.',
      );
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on MissingPluginException {
      // Nada que limpiar si la plataforma no soporta el almacén seguro.
    }
  }

  /// Inicia sesión con Firebase Auth y persiste el idToken/refreshToken.
  Future<String> signIn(String email, String password) async {
    if (AuthService.firebaseApiKey.isEmpty) {
      throw const AuthException(
        'Falta FIREBASE_WEB_API_KEY. Configura la clave pública de Firebase.',
      );
    }
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      throw const AuthException('Escribe tu correo y contraseña.');
    }

    final body = await _post(
      Uri.https(
        'identitytoolkit.googleapis.com',
        _signInPath,
        {'key': AuthService.firebaseApiKey},
      ),
      {
        'email': normalizedEmail,
        'password': password,
        'returnSecureToken': true,
      },
    );
    return _saveTokenResponse(body, isRefresh: false);
  }

  /// Crea una cuenta nueva con correo y contraseña, guardando los tokens.
  /// Si el correo ya existe, Firebase devuelve `EMAIL_EXISTS`.
  Future<String> signUp(String email, String password) async {
    if (AuthService.firebaseApiKey.isEmpty) {
      throw const AuthException(
        'Falta FIREBASE_WEB_API_KEY. Configura la clave pública de Firebase.',
      );
    }
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty || password.length < 6) {
      throw const AuthException(
        'Escribe un correo válido y una contraseña de al menos 6 caracteres.',
      );
    }
    final body = await _post(
      Uri.https(
        'identitytoolkit.googleapis.com',
        _signUpPath,
        {'key': AuthService.firebaseApiKey},
      ),
      {
        'email': normalizedEmail,
        'password': password,
        'returnSecureToken': true,
      },
    );
    return _saveTokenResponse(body, isRefresh: false);
  }

  /// Envía el correo de Firebase para establecer/restablecer la contraseña.
  /// Funciona sin sesión previa: es la vía oficial cuando el service account
  /// de desarrollo no tiene permisos de Auth Admin.
  Future<void> sendPasswordReset(String email) async {
    if (AuthService.firebaseApiKey.isEmpty) {
      throw const AuthException(
        'Falta FIREBASE_WEB_API_KEY. Configura la clave pública de Firebase.',
      );
    }
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) {
      throw const AuthException('Escribe tu correo.');
    }
    await _post(
      Uri.https(
        'identitytoolkit.googleapis.com',
        _passwordResetPath,
        {'key': AuthService.firebaseApiKey},
      ),
      {
        'requestType': 'PASSWORD_RESET',
        'email': normalizedEmail,
      },
    );
  }

  /// Renueva el idToken usando el refreshToken guardado.
  Future<String> refresh() async {
    if (AuthService.firebaseApiKey.isEmpty) {
      throw const AuthException(
        'Falta FIREBASE_WEB_API_KEY. Configura la clave pública de Firebase.',
      );
    }
    final refreshToken = await _read(refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) {
      await logout();
      throw const AuthException('Sesión caducada. Vuelve a iniciar sesión.');
    }

    try {
      final body = await _post(
        Uri.https(
          'securetoken.googleapis.com',
          _refreshPath,
          {'key': AuthService.firebaseApiKey},
        ),
        {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
        },
      );
      return _saveTokenResponse(body, isRefresh: true);
    } catch (_) {
      await logout();
      rethrow;
    }
  }

  /// Devuelve un idToken vigente, renovándolo 60 segundos antes de caducar.
  Future<String> getIdToken() async {
    final idToken = await _read(idTokenKey);
    if (idToken == null || idToken.isEmpty) {
      throw const AuthException(
        'Inicia sesión con Firebase para publicar los cambios pendientes.',
      );
    }
    final expiry = DateTime.tryParse(await _read(expiryKey) ?? '');
    if (expiry != null &&
        DateTime.now().add(_tokenMargin).isBefore(expiry)) {
      return idToken;
    }
    return refresh();
  }

  /// UID (`sub`/`user_id`) del idToken vigente; `null` si no hay sesión.
  Future<String?> currentUid() async {
    final idToken = await _read(idTokenKey);
    if (idToken == null || idToken.isEmpty) return null;
    return decodeUidFromIdToken(idToken);
  }

  /// Extrae el UID de un JWT de Firebase sin verificar la firma (el token
  /// viene del propio backend de Firebase Auth y Firestore lo re-valida).
  @visibleForTesting
  static String? decodeUidFromIdToken(String idToken) {
    final parts = idToken.split('.');
    if (parts.length < 2) return null;
    try {
      final normalized = base64Url.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      if (payload is! Map) return null;
      final userId = payload['user_id'] ?? payload['sub'];
      return userId is String && userId.isNotEmpty ? userId : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    await _delete(idTokenKey);
    await _delete(refreshTokenKey);
    await _delete(expiryKey);
  }

  Future<void> clear() => logout();

  Future<Map<String, dynamic>> _post(
    Uri uri,
    Map<String, dynamic> payload,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      Map<String, dynamic> decoded;
      try {
        decoded = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        throw const AuthException('Respuesta de autenticación no válida.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = decoded['error'];
        final code = error is Map
            ? error['message'] as String?
            : decoded['message'] as String?;
        throw AuthException(
          _friendlyMessage(code ?? 'ERROR_DE_AUTENTICACION'),
          code: code,
        );
      }
      return decoded;
    } on SocketException {
      throw const AuthException(
        'Sin conexión. No se pudo verificar tu cuenta.',
      );
    } on AuthException {
      rethrow;
    } catch (error) {
      throw AuthException('No se pudo iniciar sesión: $error');
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _saveTokenResponse(
    Map<String, dynamic> body, {
    required bool isRefresh,
  }) async {
    final idToken = (isRefresh ? body['id_token'] : body['idToken']) as String?;
    final refreshToken =
        (isRefresh ? body['refresh_token'] : body['refreshToken']) as String?;
    final expiresIn = (isRefresh ? body['expires_in'] : body['expiresIn'])
        as Object?;
    if (idToken == null ||
        idToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty) {
      throw const AuthException('Firebase no devolvió tokens válidos.');
    }
    final seconds = switch (expiresIn) {
      final String value => int.tryParse(value) ?? 3600,
      final int value => value,
      _ => 3600,
    };
    final expiry = DateTime.now()
        .add(Duration(seconds: seconds > 0 ? seconds : 3600))
        .toIso8601String();
    await _write(idTokenKey, idToken);
    await _write(refreshTokenKey, refreshToken);
    await _write(expiryKey, expiry);
    return idToken;
  }

  @visibleForTesting
  static String friendlyMessage(String code) => _friendlyMessage(code);

  static String _friendlyMessage(String code) => switch (code) {
        'EMAIL_NOT_FOUND' || 'INVALID_EMAIL' =>
          'No existe una cuenta con ese correo.',
        'EMAIL_EXISTS' =>
          'Ya existe una cuenta con ese correo. Usa tu contraseña actual.',
        'WEAK_PASSWORD' => 'La contraseña debe tener al menos 6 caracteres.',
        'INVALID_PASSWORD' || 'INVALID_LOGIN_CREDENTIALS' =>
          'Correo o contraseña incorrectos.',
        'USER_DISABLED' => 'Esta cuenta está desactivada.',
        'TOO_MANY_ATTEMPTS_TRY_LATER' =>
          'Demasiados intentos. Intenta de nuevo más tarde.',
        'NETWORK_ERROR' => 'Sin conexión con Firebase.',
        _ => 'Error de Firebase: $code',
      };
}
