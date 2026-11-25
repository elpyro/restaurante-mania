import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Reporting de errores fatales con Firebase Crashlytics.
///
/// La inicialización es best-effort: si no están los archivos nativos de
/// configuración (`google-services.json` en Android, `GoogleService-Info.plist`
/// en iOS) la app sigue arrancando en modo demo y los reportes se omiten.
class CrashReporter {
  CrashReporter._();

  static bool _enabled = false;

  static bool get isEnabled => _enabled;

  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
      _enabled = true;
    } catch (_) {
      // Sin configuración nativa no hay proyecto al que enviar los crashes.
      _enabled = false;
    }
  }

  /// Fuerza un crash fatal para verificar que la consola recibe el evento.
  /// Solo se debe llamar desde un disparador explícito de QA.
  static Future<void> sendTestCrash() async {
    if (!_enabled) return;
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    FirebaseCrashlytics.instance.crash();
  }
}
