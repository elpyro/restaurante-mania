# Firebase Crashlytics — configuración y verificación

> Crashlytics **no es una función de Firestore**. Es un producto independiente de
> Firebase y solo reporta crashes de apps nativas/móviles. Para que la consola deje
> de decir «Esperando el primer error», la app debe enviar un crash real desde un
> dispositivo o emulador.

Estado del repo: SDK instalado en la app Flutter (Android). Falta **únicamente** el
archivo nativo de configuración, que se descarga del proyecto
`restaurante-mania-e47a0` y no se versiona.

## Cambios ya aplicados en código

- `app/pubspec.yaml`: `firebase_core: ^5.2.0` y `firebase_crashlytics: ^6.1.0`.
- `app/lib/core/services/crash_reporter.dart`: inicialización best-effort de
  Firebase, captura de errores Flutter/Dart y disparador `sendTestCrash()`.
- `app/lib/main.dart`: llama a `CrashReporter.initialize()` antes de cargar el
  repositorio. Si no hay configuración nativa, la app sigue arrancando en modo demo.
- `app/lib/features/more/more_screen.dart`: tile «Enviar crash de prueba» en **Más**,
  solo compilado con `--dart-define=ENABLE_CRASH_TEST=true`.
- `app/android/settings.gradle.kts` y `app/android/app/build.gradle.kts`: los plugins
  de Google Services y Crashlytics se aplican **solo si** existe
  `app/android/app/google-services.json`, para no romper el build actual.

## Pasos pendientes (consola de Firebase)

1. Entrar en **Firebase console → Project settings → Your apps**.
2. Comprobar si existe una app **Android** con package `com.example.app` (es el
   `applicationId` actual en `app/android/app/build.gradle.kts`).
   - Si no existe: **Add app → Android**, registrar `com.example.app` y descargar
     `google-services.json` (el nombre del package debe coincidir exactamente).
   - Si Crashlytics se activó para una app iOS en vez de Android, hace falta
     `GoogleService-Info.plist` y la configuración en Xcode; este repo aún no la tiene.
3. Copiar el archivo descargado a:

   ```text
   app/android/app/google-services.json
   ```

   No se sube a Git: ya está cubierto por `.gitignore` (verificar con
   `git check-ignore app/android/app/google-services.json`).

## Generar el crash de prueba

Con el archivo en su sitio, recompilar y abrir la app en el dispositivo:

```powershell
cd app
flutter build apk --release `
  --dart-define=WEB_API_URL=http://localhost:3001 `
  --dart-define=FIREBASE_WEB_API_KEY=<clave-web-publica> `
  --dart-define=ENABLE_CRASH_TEST=true
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

En la app: iniciar sesión como administrador → **Más** → **Enviar crash de prueba**
→ **Enviar**. La app se cierra. En unos minutos el evento aparece en
**Firebase console → Crashlytics** y el estado pasa de «Esperando datos» a activo.

Para la APK de producción, recompilar **sin** `--dart-define=ENABLE_CRASH_TEST=true`:
el botón desaparece, pero la captura automática de errores sigue activa.

## Verificación rápida

- Si el tile dice «Crashlytics inactivo: falta el archivo nativo de configuración»,
  `Firebase.initializeApp()` falló: revisar que el JSON esté en la ruta indicada y
  que el package coincida.
- Si el crash se envía pero no aparece: revisar reglas de red del dispositivo y
  que Crashlytics esté activado para la app Android correcta en la consola.
