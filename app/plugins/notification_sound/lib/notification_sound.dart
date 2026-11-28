import 'package:flutter/services.dart';

/// Sonido de alertas reproducido por la app, no por el canal de notificaciones.
///
/// MIUI/HyperOS puede restaurar el sonido elegido por el usuario en el canal
/// de Android e ignorar el que configura la app. Este plugin usa `SoundPool`
/// con los recursos OGG/WAV empaquetados, así que el aviso suena también en
/// segundo plano y con la app cerrada. Respeta Silencio/No molestar y volumen 0.
class NotificationSound {
  static const MethodChannel _channel = MethodChannel('com.example.app/notification_sound');

  /// Reproduce una sola alerta con el tono indicado (`classic`, `chime`,
  /// `double` o `soft`). Respeta Silencio/No molestar y volumen 0.
  static Future<void> play({String tone = 'classic'}) =>
      _channel.invokeMethod<void>('play', <String, Object>{'tone': tone});
}
