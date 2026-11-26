# Restaurante Manía — Sistema Integral de Restaurantes

Monorepo con tres productos conectados:

| Producto | Carpeta | Stack |
|---|---|---|
| Web pública (catálogo, SEO/GEO y pedidos) | `web/` | Next.js 16 (App Router), React 19, TypeScript, Tailwind |
| App administrativa (POS offline-first) | `app/` | Flutter, provider, shared_preferences, connectivity_plus |
| Backend | `firebase/` | Firestore, reglas, índices y Cloud Functions v2 (TS) |

Estado verificado: **web compilada con 27 rutas y 95 tests**, **app con 86 tests
y APK release de 61,6 MB instalada en `a791bc16`**, **reglas de
Firestore/Storage desplegadas y Cloud Functions compilando con `tsc`**.

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
npm test             # 95 tests (carrito, catálogo, pedidos, configuración)
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
flutter test         # 86 tests
flutter build apk --release
```

APK resultante: `app/build/app/outputs/flutter-apk/app-release.apk`.

En Inventario, cada insumo tiene un botón **Surtir**: abre un diálogo donde se
escribe la cantidad a agregar (acepta decimales con `.` o `,`), muestra el
nuevo stock esperado y, al confirmar, **suma** al stock existente mediante
`adjustIngredientStock()` (respeta la cola offline y recalcula el estado de los
platos). La ficha se resalta en verde con «¡Surtido!» durante 3 segundos y el
SnackBar confirma el total. Solo lo ven los roles con permiso de menú.

La APK conserva su tema original. Los pedidos creados desde la web se muestran
con fondo azul claro y borde azul para distinguirlos de los pedidos del local.
Se eliminaron los mensajes técnicos y el disparador de crash de la interfaz.

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
firebase deploy --only firestore:rules,firestore:indexes,storage,functions
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
6. Desde el detalle de cualquier pedido se puede imprimir un recibo sencillo
   (productos, totales, pago y datos del cliente) con el botón **Imprimir
   recibo**; usa el diálogo de impresión del sistema.

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

## Web pública controlada desde la APK (2026-11-25)

El administrador controla la **web pública** desde **Más → Apariencia** y
**Más → Configuración**. No cambia el tema de la APK. Los cambios se publican en
`PATCH /api/restaurant/config` y se leen desde `restaurant/config` en Firestore.

### Apariencia

- Presets: `mania`, `fuego`, `verde`, `noche` y `custom`.
- Banner y logo: se suben desde la APK a Firebase Storage (`appearance/...`),
  con opciones de cambiar y eliminar. Se admiten JPG, PNG, WEBP y **GIF** (hasta
  6 MB). El banner se sirve sin optimizar para que los GIF se animen y su
  atenuado es ligero para que se vea el fondo.
- Estilo propio: 7 colores base (`brand`, `accent`, `surface`, `ink`, `heroFrom`,
  `heroTo`, `footer`); la web deriva el resto de tokens. Al tocar la muestra de
  color se abre un selector HSV (cuadro, tono y hex).
- Portada con banner animado, logo, columna derecha vacía para lucir el fondo,
  favoritos en carrusel automático (se pausa al pasar el mouse o al enfocar una
  tarjeta), WhatsApp flotante, cabecera sticky y CTA móvil fijo. En móvil el
  banner se recorta al extremo derecho; en escritorio queda centrado. El pie
  también usa el logo subido.
- Redes y mapa: los campos de Instagram, TikTok, Facebook y GPS se editan en
  Apariencia. Solo se renderizan en el pie cuando tienen valor; se aceptan URLs
  `http(s)` y dejar el campo vacío las elimina. Las redes también alimentan
  `sameAs` del JSON-LD y el mapa `hasMap`.
- Un producto se marca como **Favorito** desde el Menú de la APK (estrella); se
  reutiliza `menuItems.featured`.

### Configuración de contacto, entrega y pagos

- Ciudad, indicativo (`+57`), teléfono, WhatsApp derivado, moneda y horario.
- Check «¿Cómo quieres recibirlo?»: si se desactiva, la web no ofrece la
  selección y solo usa el primer tipo de entrega habilitado.
- Tipos de entrega y métodos de pago activables; etiquetas de pago editables.
  La web filtra las opciones desactivadas y el servidor las valida de nuevo al
  crear un pedido.
- Datos para búsqueda de IA: descripción, palabras clave, zona de servicio y
  aspectos destacados. Se publican en `aiSearch`, se reflejan en los metadatos
  (`description`, `keywords`, `areaServed`, `hasMap`) y en la sección «Datos para
  búsqueda con IA» de `/llms.txt`.

### Icono de la APK

El icono de launcher se genera desde
`C:\Users\eloy_\Pictures\Captura de pantalla 2026-11-20 104117.png` en
`app/android/app/src/main/res/mipmap-*/ic_launcher.png` (48/72/96/144/192 px
según densidad). La imagen se ajusta al cuadrado sobre su propio fondo oscuro,
sin distorsionar el contenido.

### Autorización y Storage

- `GET /api/restaurant/config` es público; `PATCH` exige
  `Authorization: Bearer <idToken>` con rol `admin` (claim `role` o documento
  `users/{uid}`). Sin token: 401; con otro rol: 403.
- `PATCH /api/menu/[id]` (`status` y `featured`) también exige admin.
- Las reglas viven en `firebase/storage.rules`: lectura pública; rol según
  `tenants/{tenantId}/users/{uid}.role`. Nuevas subidas por tenant:
  `tenants/{tenantId}/appearance/...` solo admin;
  `tenants/{tenantId}/inventory-losses/...` para admin o cocinero; se conservan
  las rutas antiguas `appearance/...` / `inventory-losses/...`. Validación de
  tipo/tamaño (6 MB). El puente Storage↔Firestore requiere el rol
  IAM `roles/firebaserules.firestoreServiceAgent` para el service agent de
  Storage (verificado en el proyecto `restaurante-mania-e47a0`).
- Offline: la APK encola cambios en `rm_pending_restaurant_config_v1`,
  `rm_pending_config_patch_v1` y `rm_pending_featured_items_v1`, y los envía al
  reconectar; «Sincronizar ahora» también vacía la cola de configuración y su
  contador incluye esos cambios. «Recargar desde la web» reconcilia los valores.
- Si hay API key Firebase pero no idToken, la APK descarta la sesión local y
  muestra el login (sin borrar la cola). En Apariencia se indica
  «Sin sesión Firebase · inicia sesión para publicar» con un botón
  «Ir a iniciar sesión». Los errores 401/403 de Storage se distinguen de los de
  red o tiempo de espera.

### Login real en la APK

En builds **release** la clave pública de producción `restaurante-mania-e47a0`
se compila por defecto, así que no hace falta `--dart-define` para apuntar a
Firebase production; se puede sobreescribir con
`--dart-define=FIREBASE_WEB_API_KEY=<clave-web-publica>`. En `flutter run`
(debug) sin clave se mantiene el login demo (`1234`).

Con clave Firebase compilada el login usa Firebase Auth REST
(`accounts:signInWithPassword`) y guarda los tokens en `flutter_secure_storage`.
**El rol no exige un usuario local con el mismo correo**: se lee de
`tenants/{tenantId}/users/{uid}` en Firestore con el idToken del usuario. Si la
cuenta no tiene un rol válido (`admin`, `cashier`, `waiter`, `cook`) en la
instancia activa, el login falla con un mensaje claro. `pullServerUsers()`
(lista de usuarios) solo se ejecuta para administradores; un **403 no marca
sesión vencida**, solo la **401** dispara re-login.

El enlace **Recuperar contraseña** usa `accounts:sendOobCode`
(`PASSWORD_RESET`) para que Firebase envíe el correo que establece la clave del
usuario; aparece solo cuando hay API key Firebase compilada.

```bash
flutter build apk --release
# o, apuntando a QA con transporte web:
flutter build apk --release \
  --dart-define=DIRECT_FIRESTORE=false \
  --dart-define=WEB_API_URL=https://tu-dominio-web.netlify.app \
  --dart-define=FIREBASE_WEB_API_KEY=<clave-web-publica>
```

### APK en producción: Firestore directo + Storage por tenant

Por defecto (`DIRECT_FIRESTORE=true`) la APK habla **directamente con
Firestore REST** con el idToken, proyecto `restaurante-mania-e47a0`, sin
depender de la web. `firebase/firestore.rules` es la única barrera de
autorización.

- **`updateMask`:** todo `PATCH` a Firestore envía `updateMask.fieldPaths`
  repetido por cada campo del body. Firestore REST **reemplaza** el documento
  si no se envía la máscara; con ella los `PATCH` parciales conservan los
  campos no enviados (mismo contrato que la web `setDocument`).
- **Pedido offline avanzado:** `_runSync` crea la orden en `pending` (regla
  `isValidOrder`) y luego hace `PATCH` con el estado real
  (`paymentStatus`, `paidAt`, `payments`, `inventoryDeducted`).
- **Límites:** `customerName` ≤ 80, `customerPhone` ≤ 20, `notes` ≤ 300,
  `deliveryAddress` ≤ 160, `items` ≤ 50, nombre ≥ 2 / teléfono ≥ 7 salvo mesa,
  dirección de entrega ≥ 5.
- **Storage por tenant:** las subidas van a
  `tenants/{tenantId}/appearance/...` y `tenants/{tenantId}/inventory-losses/...`.
  `firebase/storage.rules` valida el rol en `tenants/{tenantId}/users/{uid}`
  (admin / cocinero según la ruta), conserva lectura pública y mantiene las
  rutas antiguas `appearance/...` / `inventory-losses/...`. Límite 6 MB,
  `image/(jpeg|png|webp|gif)`.
- **Diagnóstico:** Configuración → Conexión muestra proyecto, transporte,
  instancia, sesión y clave pública (sin secretos).

Para aprovisionar un usuario de QA con rol en Firestore (la contraseña nunca se
guarda en el repositorio):

```bash
EMAIL=admin@restaurante.com PASSWORD=... ROLE=admin \
  node firebase/scripts/provision-auth-users.mjs
```

El service account de web (`firebase-web-admin@...`) solo tiene permisos de
Firestore (no Firebase Auth Admin ni `firebaserules.releases.list`); la APK usa
el idToken del usuario, no el service account. Los roles viven en
`tenants/{tenantId}/users/{uid}` (colección `users` raíz vacía); no se usan
custom claims.

### Pérdidas y caducados de ingredientes (2026-11-25)

- Administradores y cocineros registran mermas desde la APK con motivo
  (`caducado`, `perdida`, `dano`, `otro`), una o varias líneas de ingredientes con
  cantidad, observaciones y foto tomada con la cámara (también se puede elegir de
  la galería). Meseros y cajeros no ven la función.
- El administrador abre **Más → Pérdidas de inventario**; dentro están el
  historial, la foto, el estado de sincronización y la auditoría. Desde esa
  pantalla está el botón **Registrar pérdida**. El cocinero lo tiene en
  **Inicio** (tarjeta y botón flotante).
- El registro se guarda primero en `rm_inventory_losses_v1` y descuenta el stock
  local con la cola existente `rm_pending_ingredient_stocks_v1`. Al reconectar
  se sube la foto a `tenants/{tenantId}/inventory-losses/...` en Storage y se envía la auditoría a
  `POST /api/inventory-losses` con `Bearer`; el stock **no** se descuenta dos
  veces porque el POST es solo auditoría. `GET /api/inventory-losses` reconcilia
  el historial y las pérdidas pendientes ganan sobre el servidor.
- El endpoint exige `Authorization: Bearer <idToken>` y rol `admin` o `cook`
  (claim o documento `users/{uid}`); valida motivo, cantidades > 0 y entre 1 y 30
  ingredientes. Cada documento guarda `createdBy`, `receivedBy` y `auditLog`.

### Interacción de compra en la web

- Al agregar platos aparece una barra flotante inferior central con el total
  del carrito; se oculta en `/cart`, `/checkout` y `/order/*` para no duplicar
  controles. Cada tarjeta muestra sobre la imagen cuántas unidades tiene en el
  carrito (también en el carrusel de favoritos).
- Se quitó la barra móvil «Ver menú» del fondo y el WhatsApp flotante se movió
  arriba a la derecha para no tapar la barra del carrito.
- El pie enlaza a `wa.me/573125866072` con el texto «Otro software de Software
  Mania. Adquierelo: +573125866072».

Los GIF elegidos en **Más → Apariencia** conservan su animación: la APK ya no
comprime la imagen al seleccionarla y `MediaUploadService` valida los bytes
mágicos (un `.gif` que en realidad es JPEG se rechaza con un mensaje claro).

**Verificado:** 95 tests web, 86 tests Flutter, `typecheck`/`analyze` y builds OK
(APK release de 61,6 MB). Storage desplegado y subida/lectura/borrado de una
imagen QA comprobados con token admin; el banner actual es un GIF89a válido
servido sin optimizar, así que anima en el hero. Para pérdidas: `GET/POST` con
token cocinero y admin → 200, mesero → 403, sin token → 401; subida a
`inventory-losses/...` con token cocinero → 200 (registros QA borrados después).
La APK quedó compilada en `app/build/app/outputs/flutter-apk/app-release.apk`,
reinstalada en `a791bc16` y arrancó sin `FATAL EXCEPTION`. Cambios commiteados y
pusheados en `feature/app-reportes-cierre-caja`; sin despliegue a Netlify.
