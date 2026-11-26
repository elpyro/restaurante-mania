import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';

class MediaUploadException implements Exception {
  const MediaUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Sube banner/logo a Firebase Storage usando la REST API y el idToken de
/// Firebase Auth. No requiere el plugin nativo de Storage.
class MediaUploadService {
  MediaUploadService({AuthService? authService})
      : _authService = authService ?? AuthService();

  static const bucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
    defaultValue: 'restaurante-mania-e47a0.firebasestorage.app',
  );

  static const allowedMimeTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
  };

  /// Mensajes diferenciados para permisos, red y tiempo de espera.
  static const networkMessage =
      'Sin conexión con Firebase Storage. Revisa internet e inténtalo de nuevo.';
  static const timeoutMessage =
      'Firebase Storage no respondió. Inténtalo de nuevo en unos segundos.';
  static const authMessage =
      'Sesión de Firebase vencida o sin permisos. '
      'Inicia sesión como administrador para continuar.';

  final AuthService _authService;

  static String mimeTypeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return '';
  }

  /// Tipo real del archivo según sus bytes mágicos. Un GIF re-codificado como
  /// JPEG por image_picker queda con extensión .gif pero no anima en la web.
  @visibleForTesting
  static String mimeTypeFromBytes(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (_startsWith(bytes, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return 'image/png';
    }
    // GIF87a y GIF89a: cualquiera de los dos conserva la animación.
    if (_startsWith(bytes, [0x47, 0x49, 0x46, 0x38, 0x37, 0x61]) ||
        _startsWith(bytes, [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])) {
      return 'image/gif';
    }
    if (bytes.length >= 12 &&
        _startsWith(bytes, [0x52, 0x49, 0x46, 0x46]) && // RIFF
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      // WEBP
      return 'image/webp';
    }
    return '';
  }

  static bool _startsWith(List<int> bytes, List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }

  /// Compara extensión y contenido; rechaza los GIF falsos antes de subirlos.
  @visibleForTesting
  static String resolveMimeType({
    required String filePath,
    required List<int> bytes,
  }) {
    final byPath = mimeTypeFromPath(filePath);
    final byBytes = mimeTypeFromBytes(bytes);
    if (byBytes.isEmpty) {
      throw const MediaUploadException(
        'No se reconoce el formato de la imagen. Usa JPG, PNG, WEBP o GIF.',
      );
    }
    if (byPath.isNotEmpty && byPath != byBytes) {
      if (byPath == 'image/gif') {
        throw const MediaUploadException(
          'El archivo termina en .gif pero no es un GIF válido. '
          'Guárdalo de nuevo como GIF animado y vuelve a subirlo.',
        );
      }
      throw MediaUploadException(
        'La extensión (${byPath.split('/').last}) no coincide con el contenido '
        'de la imagen (${byBytes.split('/').last}).',
      );
    }
    return byBytes;
  }

  static String objectPath(String url) {
    final marker = '/o/';
    final start = url.indexOf(marker);
    if (start < 0) return '';
    final tail = url.substring(start + marker.length);
    final end = tail.indexOf('?');
    final encoded = end < 0 ? tail : tail.substring(0, end);
    try {
      return Uri.decodeComponent(encoded);
    } catch (_) {
      return encoded;
    }
  }

  static String downloadUrl(String objectName, String token) {
    final encoded = Uri.encodeComponent(objectName);
    return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/$encoded'
        '?alt=media&token=$token';
  }

  /// Sube el archivo y devuelve una URL pública con token de descarga.
  Future<String> uploadFile({
    required String filePath,
    required String objectName,
    int maxBytes = 6 * 1024 * 1024,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const MediaUploadException('No se encontró la imagen seleccionada.');
    }
    final length = await file.length();
    if (length == 0 || length > maxBytes) {
      final limit = (maxBytes / (1024 * 1024)).toStringAsFixed(0);
      throw MediaUploadException(
        'La imagen debe pesar menos de $limit MB.',
      );
    }
    final bytes = await file.readAsBytes();
    final mimeType = resolveMimeType(filePath: filePath, bytes: bytes);
    if (!allowedMimeTypes.contains(mimeType)) {
      throw const MediaUploadException(
        'Usa una imagen JPG, PNG, WEBP o GIF.',
      );
    }

    String token;
    try {
      token = await _authService.getIdToken();
    } on AuthException catch (error) {
      throw MediaUploadException(error.message);
    }

    final uri = Uri.https(
      'firebasestorage.googleapis.com',
      '/v0/b/$bucket/o',
      {'name': objectName},
    );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 20);
    try {
      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Firebase $token');
      request.headers.set(HttpHeaders.contentTypeHeader, mimeType);
      request.headers.set('x-goog-meta-uploaded-from', 'apk');
      request.add(bytes);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _storageError(
          response.statusCode,
          body,
          action: 'subir la imagen',
        );
      }
      final decoded = jsonDecode(body);
      final name = decoded is Map ? decoded['name'] : null;
      final downloadToken = decoded is Map ? decoded['downloadTokens'] : null;
      if (name is! String || name.isEmpty) {
        throw const MediaUploadException('Firebase no devolvió el archivo subido.');
      }
      final finalToken = downloadToken is String && downloadToken.isNotEmpty
          ? downloadToken
          : 'none';
      return downloadUrl(name, finalToken);
    } on MediaUploadException {
      rethrow;
    } on SocketException {
      throw const MediaUploadException(networkMessage);
    } on TimeoutException {
      throw const MediaUploadException(timeoutMessage);
    } catch (error) {
      throw MediaUploadException('No se pudo subir la imagen: $error');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> deleteUrl(String url) async {
    final path = objectPath(url);
    if (path.isEmpty) return;
    String token;
    try {
      token = await _authService.getIdToken();
    } on AuthException catch (error) {
      throw MediaUploadException(error.message);
    }
    final uri = Uri.https(
      'firebasestorage.googleapis.com',
      '/v0/b/$bucket/o/${Uri.encodeComponent(path)}',
    );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 20);
    try {
      final request = await client.deleteUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Firebase $token');
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      // 404 significa que ya no existe: se considera eliminado.
      if (response.statusCode >= 400 && response.statusCode != 404) {
        throw _storageError(
          response.statusCode,
          body,
          action: 'eliminar la imagen',
        );
      }
    } on MediaUploadException {
      rethrow;
    } on SocketException {
      throw const MediaUploadException(networkMessage);
    } on TimeoutException {
      throw const MediaUploadException(timeoutMessage);
    } finally {
      client.close(force: true);
    }
  }

  /// 401/403 son de sesión/permisos; el resto de estados y la falta de red
  /// tienen mensajes distintos para que el administrador sepa qué corregir.
  MediaUploadException _storageError(
    int status,
    String body, {
    required String action,
  }) {
    if (status == 401 || status == 403) {
      return const MediaUploadException(authMessage);
    }
    if (status == 413) {
      return const MediaUploadException('La imagen es demasiado grande.');
    }
    return MediaUploadException(
      'Firebase Storage respondió $status al $action: ${_shortBody(body)}',
    );
  }

  @visibleForTesting
  static String friendlyError(int status, String body) {
    final service = MediaUploadService(authService: AuthService());
    return service._storageError(
      status,
      body,
      action: 'subir la imagen',
    ).message;
  }

  String _shortBody(String body) {
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length > 120 ? '${flat.substring(0, 120)}…' : flat;
  }
}
