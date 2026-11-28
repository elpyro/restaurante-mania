import 'package:flutter_timezone/flutter_timezone.dart';

import '../models/restaurant_settings.dart';

/// Zona horaria IANA del dispositivo.
///
/// La APK ya no pide al usuario que elija una zona: toma la configuración
/// nativa del celular y la valida antes de publicarla en la web. Si el sistema
/// devuelve un identificador no IANA (por ejemplo `GMT-05:00`) se conserva el
/// valor por defecto, que siempre es válido para Firestore y para la web.
class DeviceTimeZone {
  DeviceTimeZone._();

  static Future<String>? _cached;

  static Future<String> current() {
    return _cached ??= _resolve();
  }

  static Future<String> _resolve() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      final identifier = info.identifier.trim();
      if (RestaurantSettings.isValidTimeZone(identifier)) return identifier;
    } catch (_) {
      // Plataforma sin soporte: se usa la zona por defecto.
    }
    return RestaurantSettings.defaultTimeZone;
  }
}
