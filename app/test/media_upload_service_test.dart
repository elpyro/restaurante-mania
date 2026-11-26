import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/services/media_upload_service.dart';

void main() {
  test('401/403 se explican como sesión/permisos, no como error de red', () {
    final forbidden = MediaUploadService.friendlyError(403, 'denied');
    expect(forbidden, contains('Inicia sesión'));
    expect(forbidden, isNot(contains('Sin conexión')));

    final unauthorized = MediaUploadService.friendlyError(401, 'unauthorized');
    expect(unauthorized, MediaUploadService.authMessage);
  });

  test('otros estados muestran el código y el detalle del servidor', () {
    final message = MediaUploadService.friendlyError(500, 'storage down');
    expect(message, contains('500'));
    expect(message, contains('storage down'));
  });

  test('los mensajes de red y tiempo de espera son distintos', () {
    expect(MediaUploadService.networkMessage, contains('Sin conexión'));
    expect(MediaUploadService.timeoutMessage, contains('no respondió'));
    expect(
      MediaUploadService.networkMessage,
      isNot(MediaUploadService.authMessage),
    );
  });

  test('detecta el tipo real por magic bytes', () {
    expect(
      MediaUploadService.mimeTypeFromBytes(
        [0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00],
      ),
      'image/gif',
    );
    expect(
      MediaUploadService.mimeTypeFromBytes(
        [0x47, 0x49, 0x46, 0x38, 0x37, 0x61],
      ),
      'image/gif',
    );
    expect(
      MediaUploadService.mimeTypeFromBytes([0xFF, 0xD8, 0xFF, 0xE1]),
      'image/jpeg',
    );
    expect(
      MediaUploadService.mimeTypeFromBytes([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      ]),
      'image/png',
    );
    expect(
      MediaUploadService.mimeTypeFromBytes([
        0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50,
      ]),
      'image/webp',
    );
    expect(MediaUploadService.mimeTypeFromBytes([0x00, 0x01, 0x02]), isEmpty);
  });

  test('rechaza un .gif que en realidad es JPEG', () {
    expect(
      () => MediaUploadService.resolveMimeType(
        filePath: 'appearance/banner.gif',
        bytes: [0xFF, 0xD8, 0xFF, 0xE1],
      ),
      throwsA(
        isA<MediaUploadException>().having(
          (error) => error.message,
          'message',
          contains('no es un GIF válido'),
        ),
      ),
    );
  });

  test('acepta un GIF válido y usa su tipo real', () {
    expect(
      MediaUploadService.resolveMimeType(
        filePath: 'appearance/banner.gif',
        bytes: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61],
      ),
      'image/gif',
    );
  });

  test('rechaza bytes que no corresponden a una imagen conocida', () {
    expect(
      () => MediaUploadService.resolveMimeType(
        filePath: 'appearance/banner.png',
        bytes: [0x00, 0x01, 0x02],
      ),
      throwsA(isA<MediaUploadException>()),
    );
  });
}
