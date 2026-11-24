# Restaurante Manía — Sistema Integral de Restaurantes

Monorepo con tres productos conectados:

| Producto | Carpeta | Stack |
|---|---|---|
| Web pública (catálogo, SEO/GEO y pedidos) | `web/` | Next.js 16 (App Router), React 19, TypeScript, Tailwind |
| App administrativa (POS offline-first) | `app/` | Flutter, provider, shared_preferences, connectivity_plus |
| Backend | `firebase/` | Firestore, reglas, índices y Cloud Functions v2 (TS) |

Estado verificado: **web compilada con 24 rutas y 21 tests**, **app con 22 tests
y APK release de 49.8 MB**, **Cloud Functions compilando con `tsc`**.

---

## Arranque rápido

### Web

```bash
cd web
npm install
npm run dev          # http://localhost:3000
```

Sin credenciales de Firebase arranca en **modo demo**: catálogo semilla, pedidos
guardados en el servidor y `localStorage`. Para usar Firestore real, copia
`.env.example` a `web/.env.local` y rellena `NEXT_PUBLIC_FIREBASE_*`.

```bash
npm test             # 21 tests (carrito, catálogo, pedidos)
npm run typecheck    # TypeScript estricto
npm run build        # build de producción
```

Rutas útiles: `/`, `/menu`, `/menu/[slug]`, `/cart`, `/checkout`,
`/order/[id]`, `/api/menu`, `/api/health`, `/sitemap.xml`, `/robots.txt`,
`/llms.txt`.

### App Flutter

```bash
cd app
flutter pub get
flutter run          # dispositivo/emulador conectado
```

Login demo (contraseña `1234` para todos):

| Rol | Correo |
|---|---|
| Administrador | `admin@restaurante.com` |
| Cajero | `cajero@restaurante.com` |
| Mesero | `mesero@restaurante.com` |
| Cocinero | `cocina@restaurante.com` |

También hay botones de **acceso rápido** en la pantalla de login.

```bash
flutter analyze      # sin issues
flutter test         # 22 tests
flutter build apk --release
```

APK resultante: `app/build/app/outputs/flutter-apk/app-release.apk`.

> En Windows, si `java` no está en el PATH:
> ```powershell
> $env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
> $env:PATH="$env:JAVA_HOME\bin;$env:PATH"
> flutter build apk --release
> ```

### Firebase

```bash
cd firebase/functions
npm install
npm run build                        # tsc

cd ..
copy .firebaserc.example .firebaserc  # ajusta el project id
firebase deploy --only firestore:rules,firestore:indexes,functions
```

Funciones: `health`, `placeOrder`, `updateOrderStatus`, `onOrderCreated`,
`dailySalesReport`. La lógica de negocio pura vive en
`firebase/functions/src/domain.ts`.

Emuladores:

```bash
firebase emulators:start --only auth,firestore,functions
```

Proyecto real configurado: `restaurante-mania-e47a0`. Para migrar los datos
demo una vez (idempotente):

```bash
node firebase/scripts/migrate-demo-to-firestore.mjs
```

El script usa `firebase/service-account.json` (no versionado). Para que la web
y la app lean/escriban colecciones privadas en producción, define
`FIREBASE_SERVICE_ACCOUNT_JSON` como el mismo JSON en una sola línea.

---

## Flujo funcional

1. El cliente navega el menú, agrega platos al carrito (persistido en
   `localStorage`) y completa el checkout.
2. El servidor valida el contrato, **resuelve los precios desde el catálogo** y
   crea el pedido en `pending`.
3. La página de confirmación muestra el código y un enlace `wa.me`.
4. La app administrativa recibe el pedido (Firestore real o cola offline) y cada
   rol lo hace avanzar: cocina `preparing → ready`, mesero/caja
   `confirmed → delivered`, admin puede cancelar.
5. Al entregar o cancelar se libera la mesa y se actualizan las métricas
   diarias (`stats/`), con reporte consolidado a las 03:00.

## Funcionalidades por rol

- **Administrador**: dashboard global, menú, mesas, pedidos, reportes, ajustes.
- **Cajero**: cobros, cuentas abiertas, historial y reportes de caja.
- **Mesero**: mapa de mesas, comandas y pedidos activos.
- **Cocinero**: cola de cocina y control de estados de preparación.

## Persistencia offline (app)

- `shared_preferences` guarda catálogo, mesas, pedidos y sesión.
- Los pedidos creados sin conexión quedan en cola (`synced: false`).
- `connectivity_plus` dispara la sincronización al volver online.
- Ajustes → **Simular conexión** permite probar el ciclo offline/online.
- El adaptador real de Firestore está marcado en `_runSync()`
  (`app/lib/core/data/repository.dart`).

## Documentación

- `AGENTS.md` — reglas de desarrollo del proyecto.
- `MEMORY.md` — decisiones técnicas, modelo de datos, bugs corregidos y riesgos.
- `docs/ARCHITECTURE.md` — arquitectura, rutas, capas, reglas y permisos.
- `docs/ROADMAP.md` — estado de cada fase y siguientes pasos.

## Limitaciones conocidas

- Sin credenciales de Firebase, la web y la app usan datos demo; con el proyecto
  real configurado ambas comparten Firestore (catálogo, pedidos, clientes y
  visitas).
- El APK está firmado con la clave debug de Flutter; para publicar hay que
  generar un keystore.
- Notificaciones push (FCM) y WhatsApp Cloud API quedan pendientes; hoy se usa
  enlace `wa.me`.
- Los pedidos demo del servidor viven en memoria y se pierden al reiniciar.
