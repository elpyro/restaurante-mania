# ARCHITECTURE.md — Arquitectura del Sistema

## 1. Vista General

Monorepo con cuatro bloques y responsabilidades separadas:

```
proyecto-restaurante/
├─ docs/       Documentación técnica y de producto
├─ web/        Web pública Next.js (SEO/GEO + pedidos en línea)
├─ app/        App administrativa Flutter (POS offline-first)
└─ firebase/   Reglas, índices, configuración y Cloud Functions
```

```
Cliente web ──┐
              ├──> Firestore <──> Cloud Functions ──> stats / reports
App Flutter ──┘        ▲
                       └── Auth (custom claims: role)
```

- **Web**: renderiza catálogo y SEO desde el catálogo (semilla o Firestore
  REST). Crea pedidos con precios recalculados en servidor.
- **App**: POS por roles con persistencia local y cola de sincronización.
- **Functions**: validación de pedidos, transiciones de estado y métricas.
- **Firestore**: fuente de verdad del catálogo y de los pedidos.

## 2. Web (Next.js 16, App Router)

### Rutas

| Ruta | Tipo | Propósito |
|---|---|---|
| `/` | Dinámica (RSC) | Home con banner, logo, carrusel de favoritos y JSON-LD `Restaurant` |
| `/menu` | Dinámica (RSC) | Catálogo por categorías, filtros y búsqueda |
| `/menu/[slug]` | Dinámica | Ficha de plato con JSON-LD `MenuItem` |
| `/cart` | Estática (cliente) | Carrito persistido en `localStorage` |
| `/checkout` | Estática (cliente) | Contacto, entrega y pago según configuración publicada |
| `/order/[id]` | Dinámica | Confirmación con enlace `wa.me` |
| `/api/menu` | Route handler | Catálogo JSON dinámico |
| `/api/menu/[id]` | Route handler | `PATCH` disponibilidad y favoritos (solo admin) |
| `/api/orders` | Route handler | `POST` crear pedido validado contra la política publicada |
| `/api/orders/[id]` | Route handler | `GET` pedido por ID |
| `/api/orders/validate` | Route handler | Validación de contrato y stock (`stockOnly`) |
| `/api/restaurant/config` | Route handler | `GET` público / `PATCH` solo admin (fusión de mapas) |
| `/api/og` | Route handler | Imagen OpenGraph generada desde la configuración |
| `/api/health` | Route handler | Health check |
| `/sitemap.xml` | `sitemap.ts` | Sitemap dinámico |
| `/robots.txt` | `robots.ts` | Rastreo del catálogo |
| `/llms.txt` | Route handler | Metadatos para agentes de IA |

### Capas internas

- `src/lib/seed.ts`: catálogo semilla (categorías y 13 platos).
- `src/lib/menu.ts`: acceso al catálogo; usa Firestore REST si hay
  configuración y cae a semilla si no.
- `src/lib/orders.ts`: validación del contrato de pedido, resolución de precios
  desde el catálogo, creación en Firestore o store demo.
- `src/lib/cart.ts`: totales y validación del carrito.
- `src/lib/seo.ts` + `src/lib/site.ts`: metadata, JSON-LD y URL canónica.
- `src/lib/firebase/rest.ts`: cliente Firestore REST mínimo (sin SDK en el
  servidor, apto para Netlify/serverless).
- `src/lib/firebase/firebase.config.ts`: lectura de `NEXT_PUBLIC_*` y
  `hasFirebaseConfig()`.

### Estrategia SEO/GEO

1. `generateMetadata()` por página con `title`, `description` (de
   `aiSearch.description` si existe), `keywords` (suma de `aiSearch.keywords` y
   `serviceArea`), `openGraph`, `twitter` y `alternates.canonical`.
2. JSON-LD embebido con `<script type="application/ld+json">`:
   `Restaurant` (home), `Menu` + `MenuItem` (catálogo y fichas),
   `BreadcrumbList` y `WebSite`. `Restaurant` incluye `sameAs` (redes) y
   `hasMap` (GPS) cuando se publican, además de `areaServed`/`keywords` de IA.
3. `sitemap.ts` incluye home, menú y todas las fichas de plato.
4. `robots.ts` permite todo el catálogo y declara el sitemap.
5. `llms.txt` expone resumen, horarios, redes, mapa, la sección «Datos para
   búsqueda con IA», categorías, platos y endpoints para agentes (ChatGPT,
   Gemini, Perplexity).
6. El pie renderiza Instagram, TikTok, Facebook y «Ver en el mapa» solo cuando
   la APK publicó esos enlaces.

## 3. App Administrativa (Flutter)

Arquitectura **feature-first** con estado centralizado en un repositorio
`ChangeNotifier`:

```
lib/
├─ main.dart, app.dart
├─ core/
│  ├─ data/        repository.dart (offline-first), seed_data.dart
│  ├─ models/      app_user, role, category, menu_item, order,
│  │               restaurant_table, restaurant_settings, app_tab
│  ├─ services/    connectivity_service.dart
│  ├─ theme/       app_theme.dart, status_colors.dart
│  ├─ utils/       formatters.dart (COP, fechas)
│  └─ widgets/     common.dart, order_card.dart
└─ features/
   ├─ auth/        login_screen.dart (acceso rápido demo por rol)
   ├─ shell/       app_shell.dart (pestañas por rol, badge online/offline)
   ├─ dashboard/   dashboard_screen.dart (KPIs y colas por rol)
   ├─ orders/      orders_screen, order_detail_screen, new_order_screen
   ├─ tables/      tables_screen.dart (mapa de mesas y hoja de acciones)
   ├─ menu/        menu_admin_screen.dart (disponibilidad y precios)
   ├─ reports/     reports_screen.dart
   ├─ settings/    settings_screen.dart
   └─ more/        more_screen.dart (cuenta, sync, cerrar sesión)
```

### Persistencia offline

- `SharedPreferences` guarda usuarios, catálogo, mesas, pedidos, sesión y
  última sincronización.
- Los pedidos nuevos nacen con `synced: false` y se encolan.
- `connectivity_plus` detecta reconexión y dispara `syncPendingOrders()`.
- `syncPendingOrders()` es idempotente y reentrante: si ya hay una
  sincronización en curso devuelve `_syncFuture` (patrón `Completer`), de modo
  que UI y tests esperan la operación real.
- `_runSync()` es el punto de integración con Firestore:
  ```dart
  // await _firestore.collection('orders').doc(order.id).set(order.toJson());
  ```
- Modo demo: `setOnlineForDemo(bool)` simula pérdida/recuperación de conexión
  desde Ajustes para probar la cola sin desactivar la red.

### Pestañas por rol

| Rol | Dashboard | Pedidos | Mesas | Menú | Reportes | Más |
|---|---|---|---|---|---|---|
| Administrador | ✅ | ✅ | — * | ✅ | ✅ | ✅ |
| Cajero | ✅ | ✅ | ✅ | — | ✅ | ✅ |
| Mesero | ✅ | ✅ | ✅ | — | — | ✅ |
| Cocinero | ✅ | ✅ | — | — | — | ✅ |

\* El administrador abre **Mesas** desde la tarjeta «Mesas ocupadas» del Inicio; el destino sigue en el `IndexedStack`, pero no aparece en la `NavigationBar`.

### Reglas de negocio en la app

- `UserRole.canManageMenu`, `canSeeReports`, `canManageTables`, `canMarkPaid`,
  `canCancelOrders`, `canAccessSettings`, `canCreateOrders`.
- Un pedido avanza `pending → confirmed → preparing → ready → delivered`;
  `cancelled` solo admin/cajero.
- Al entregar o cancelar se libera la mesa asociada.
- Formato de moneda colombiano (`$ 12.500`) y fechas en `es-CO`.

## 4. Modelo de Datos (Firestore)

### `users/{uid}`
`name, email, phone, role ('admin'|'cashier'|'waiter'|'cook'), status,
createdAt, lastLogin`

### `restaurant/config`
`name, slogan, heroTitle, heroDescription, heroBadge, countryCode, phone,
whatsapp, email, address, city, status ('open'|'closed'), hours,
currency, showOrderTypeOptions, deliveryOptions {pickup,delivery,table},
paymentMethods[], paymentMethodLabels{}, taxRate, updatedAt,
appearance {preset, bannerUrl, logoUrl, customColors{brand,accent,surface,ink,
heroFrom,heroTo,footer}, socialLinks{instagram,tiktok,facebook}, gpsUrl},
aiSearch {description, keywords, serviceArea, highlights}`. Los mapas anidados
se fusionan en el `PATCH`, por lo que publicar el preset no borra banner/logo,
redes ni las etiquetas de pago. Los enlaces solo aceptan `http(s)`.

### `categories/{id}`
`name, slug, description, order, emoji`

### `menuItems/{id}`
`name, slug, description, price, categoryId, categorySlug,
status ('available'|'unavailable'|'limited'), ingredients[], allergens[],
emoji, featured, prepMinutes, calories, recipe[], manualStatus
('unavailable'|null), statusReason ('manual'|'ingredients'|null),
statusUpdatedAt, createdAt, updatedAt`. `statusUpdatedAt` solo cambia cuando
el estado efectivo (`status` + `manualStatus` + `statusReason`) cambia.

### `orders/{id}`
`code, customerName, customerPhone, type ('pickup'|'delivery'|'table'),
tableNumber, items[{menuItemId,name,price,quantity,emoji}], subtotal, tax,
total, status, paymentStatus ('pending'|'paid'|'refunded'),
paymentMethod ('cash'|'card'|'nequi'|'daviplata'), notes, source
('web'|'app'), inventoryDeducted, createdBy, createdAt, updatedAt,
lastChangedBy`. `inventoryDeducted` es el flag de idempotencia: `pending` no
consume insumos; el primer estado superior a `pending` descuenta una sola vez
y `cancelled` repone y limpia el flag. Para pedidos `source: 'web'`, la web/Firestore
es la única dueña del descuento: la app solo reenvía el estado y consulta el
inventario actualizado; para pedidos `source: 'app'`, la app descuenta localmente
y publica el stock absoluto.

### `tables/{id}`
`number, status ('libre'|'ocupada'|'esperando_pedido'|'pidiendo_cuenta'),
capacity, currentOrderId, updatedAt`

### `stats/daily-YYYY-MM-DD`
`day, orders, items, grossSales, byType{}, byPaymentMethod{}, updatedAt`
(escrito por `onOrderCreated`)

### `reports/daily-YYYY-MM-DD`
`day, orders, items, total, averageTicket, byPaymentMethod{}, topProducts[],
generatedAt` (escrito por `dailySalesReport`)

### `_processedEvents/{eventId}`
Marcador de idempotencia para triggers.

## 5. Cloud Functions (v2, TypeScript, stateless)

| Función | Tipo | Descripción |
|---|---|---|
| `health` | HTTP | Estado del servicio |
| `placeOrder` | Callable | Valida contrato, resuelve precios desde Firestore y crea el pedido en `pending` (sin descuento de inventario) |
| `updateOrderStatus` | Callable | Transacción con control de rol, descuenta/repone inventario de forma idempotente y libera mesa al cerrar |
| `onOrderCreated` | Trigger Firestore | Métricas diarias idempotentes |
| `dailySalesReport` | Scheduler (03:00 America/Bogota) | Consolidado del día anterior |

`src/domain.ts` contiene la lógica pura: `computeTotals`, `canTransition`,
`ROLE_TRANSITIONS`, `nextStatus`, `dayKey`, `buildOrderCode` y validadores.
No importa el SDK, por lo que es testeable en aislamiento.

## 6. Matriz de Permisos por Rol

| Recurso | Administrador | Cajero | Mesero | Cocinero |
|---|---|---|---|---|
| Ver pedidos | Todos | Todos | Todos | Todos |
| Cambiar estado | Cualquiera | Confirmar, entregar, cancelar | Confirmar, entregar | Preparando, listo |
| Gestionar menú | CRUD | — | — | — |
| Gestionar mesas | Sí | Sí | Sí | — |
| Ver reportes | Completo | Caja | — | — |
| Configurar restaurante | Sí | — | — | — |
| Dashboard | Global | Caja | Mesas | Cocina |

## 7. Reglas de Seguridad (resumen)

Archivo completo: `firebase/firestore.rules`.

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Catálogo público, escritura admin
    match /categories/{id}  { allow read: if true; allow write: if isAdmin(); }
    match /menuItems/{id}   { allow read: if true; allow write: if isAdmin(); }
    match /restaurant/{id}  { allow read: if true; allow write: if isAdmin(); }
    match /tables/{id}      { allow read: if true; allow write: if canManageTables(); }

    // Usuarios
    match /users/{uid} {
      allow read: if isSignedIn() && (request.auth.uid == uid || isAdmin());
      allow write: if isAdmin();
    }

    // Pedidos: get público por ID, list solo staff, create validado
    match /orders/{id} {
      allow get: if true;
      allow list: if isStaff();
      allow create: if isValidOrder();
      allow update: if isStaff() && preservesIdentity();
      allow delete: if isAdmin();
    }

    // Métricas: solo Functions escriben
    match /stats/{id}   { allow read: if isStaff(); allow write: if false; }
    match /reports/{id} { allow read: if isStaff(); allow write: if false; }

    match /{document=**} { allow read, write: if false; }
  }
}
```

Decisiones de seguridad:

- `isValidOrder()` valida claves obligatorias, tipos, longitudes, rangos y que
  `total == subtotal + tax`, estado inicial `pending` y `paymentStatus pending`.
- `preservesIdentity()` impide cambiar `code`, `customerName` y `createdAt` en
  una actualización.
- La lectura pública por ID se apoya en que los IDs de Firestore son aleatorios
  y no enumerables (patrón capability-URL). Nunca se permite `list` anónimo.

## 8. Índices

`firebase/firestore.indexes.json` declara índices compuestos para:

- `orders`: `status + createdAt`, `type + status + createdAt`,
  `paymentStatus + createdAt`, `tableNumber + status`.
- `menuItems`: `categoryId + status`, `featured + status`.
- `categories`: `restaurantId + order`.
- `users`: `role + status`.
- `tables`: `status`.

## 9. Entornos

| Entorno | Web | Backend | App |
|---|---|---|---|
| Demo (sin credenciales) | Datos semilla, pedidos en memoria + `localStorage` | No requerido | Datos semilla en `SharedPreferences` |
| Firebase real | `NEXT_PUBLIC_FIREBASE_*` configuradas | Firestore + Functions desplegadas | Adaptador en `_runSync()` + Auth |

## 10. Despliegue

- **Web**: Netlify (`npm run build`). Variables `NEXT_PUBLIC_*` en el panel.
- **Backend**: `firebase deploy --only firestore:rules,firestore:indexes,functions`.
- **App**: `flutter build apk --release` (firma debug para pruebas) o
  `flutter build appbundle` con keystore propio para Play Store.


## Actualización 2026-11-22
- Sincronización web→app vía GET /api/orders + polling HTTP 12 s.
- Inventario con descuento automático al preparar.
- Recetas, SKU, fotos y video en platos (solo app cook/admin).
- Mesa pasa a ocupada al tomar pedido; cliente opcional en mesa.

## Actualización 2026-11-25 — configuración de apariencia y auth real

### Contrato shared

```
Firestore: restaurant/config
{
  name, slogan, heroTitle, heroDescription, heroBadge,
  countryCode, phone, whatsapp, city, address, hours, currency,
  showOrderTypeOptions, deliveryOptions {pickup, delivery, table},
  paymentMethods[], paymentMethodLabels{},
  appearance: {
    preset: "mania" | "fuego" | "verde" | "noche" | "custom",
    bannerUrl, logoUrl,
    customColors {brand, accent, surface, ink, heroFrom, heroTo, footer},
    socialLinks {instagram, tiktok, facebook}, gpsUrl
  },
  aiSearch {description, keywords, serviceArea, highlights},
  updatedAt
}

GET  /api/restaurant/config  → público, { configured, config, source }
PATCH /api/restaurant/config → Authorization: Bearer <idToken>
                               body: campos sueltos + mapas anidados parciales
                               (appearance + appearance.socialLinks, deliveryOptions,
                               paymentMethodLabels, aiSearch)
PATCH /api/menu/[id]         → Authorization: Bearer <idToken> (solo admin)
                               body: { status?, featured?, manual?, reason? }
```

Web: `src/lib/restaurant-config.ts` (defaults, presets, sanitización y lectura
con `cache()` por request) + `src/lib/firebase/admin.ts` (verifyIdToken). El rol
se acepta desde el claim `role` o desde `users/{uid}` / email en Firestore: el
service account del proyecto es `datastore.user`, no tiene permisos de Auth
Admin para escribir custom claims. Firebase Admin solo se importa en servidor.

El layout de Next inyecta los tokens del preset como variables CSS y deriva
`generateMetadata()` / `generateViewport()` del documento. Por eso el cambio se
refleja en SSR (HTML), `/api/og`, JSON-LD, `sitemap.xml` y `llms.txt`.

La home deja la columna derecha del hero vacía para que se vea el banner (GIF
animado, servido con `unoptimized`) con atenuado ligero. La imagen usa
`object-right` en móvil (recorte al extremo derecho) y `lg:object-center` en
escritorio; el carrusel de favoritos es un Client
Component (`FavoritesCarousel`) que avanza solo, vuelve al inicio y se pausa al
pasar el mouse o enfocar una tarjeta. El pie usa `appearance.logoUrl` cuando
está publicado.

### App Flutter

```
core/models/restaurant_appearance.dart   → RestaurantAppearance + preset + colores
core/models/restaurant_settings.dart     → contacto, entrega y pagos
core/services/auth_service.dart          → Firebase Auth REST, flutter_secure_storage
                                            y accounts:sendOobCode (recuperar clave)
core/services/media_upload_service.dart  → upload/delete REST a Firebase Storage
core/services/receipt_print_service.dart → PDF del recibo (fuente Geist embebida)
                                             y Printing.layoutPdf del sistema
features/appearance/appearance_screen.dart → banner, logo, textos, selector HSV, redes y GPS del pie
                                            (sin tema oscuro ni dependencias extra)
features/auth/login_screen.dart          → login Firebase + «Recuperar contraseña»
features/settings/settings_screen.dart   → país/teléfono, ciudad, moneda, entrega,
                                             pagos y datos para búsqueda de IA
features/menu/menu_admin_screen.dart     → estrella «Favorito» por producto
core/data/repository.dart                → loginWithFirebase, PATCH autenticado,
                                            colas de configuración/favoritos,
                                            pull y reconciliación
```

`AuthService.firebaseApiKey` se inyecta con
`--dart-define=FIREBASE_WEB_API_KEY=...`. El endpoint de sign-in es
`POST https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=...`;
el alias `signInWithEmailAndPassword` no existe y devuelve 404. Los tokens se
renuevan automáticamente 60 s antes de caducar. Si no hay API key se conserva
el login demo con contraseña `1234`. «Recuperar contraseña» envía
`accounts:sendOobCode` con `requestType=PASSWORD_RESET`: Firebase manda el correo
para establecer la clave y no requiere permisos de Auth Admin.

`provision-auth-users.mjs` crea usuarios con `accounts:signUp` y escribe su rol
en `users/{uid}`; no depende de custom claims ni de permisos de Auth Admin.

El detalle de pedido (`features/orders/order_detail_screen.dart`) expone
**Imprimir recibo**. `ReceiptPrintService` genera un PDF de 80 mm con fuente
Geist embebida (para acentos y texto de usuario sin depender de Google Fonts) y
lo entrega a `Printing.layoutPdf`; no es impresión térmica ESC/POS ni Bluetooth,
es el diálogo de impresión del sistema operativo. La generación del PDF es
async pero no usa canales de plataforma, así que se prueba en `flutter test`.

### Flujo offline

1. Guardar en la web persiste localmente y encola el cambio.
2. Online y con token válido: `PATCH` inmediato con `Authorization: Bearer`.
3. Offline: la cola se conserva y se envía al reconectar o en el sondeo de 12 s.
4. 401/403: la cola se conserva y la UI pide re-login; no se pierde el cambio.
5. «Sincronizar ahora» (`syncPendingOrders` → `_runSync`) también vacía la cola
   de configuración; al reconectar se llama siempre, aunque no haya pedidos.
   `_syncRestaurantConfig` solo reconcilia (`GET`) para no duplicar el `PATCH`.
6. `Recargar desde la web` adopta el documento remoto salvo que haya cambios
   pendientes de envío (offline-first). Si hay API key pero no idToken, `load()`
   descarta la sesión local y `AuthGate` muestra el login; la cola se conserva.

### Seguridad

- Solo administradores pueden publicar configuración, favoritos y disponibilidad;
  `GET` es público y no expone secretos ni tokens.
- `firebase/storage.rules`: lectura pública de `appearance/**`, escritura solo
  admin (claim `role` o `users/{uid}`), MIME `image/(jpeg|png|webp|gif)` y
  tamaño < 6 MB. Reglas desplegadas con `firebase deploy --only storage`.
- Como el service account no puede escribir custom claims, las reglas leen el rol
  desde Firestore. Eso exige el puente Storage↔Firestore: rol IAM
  `roles/firebaserules.firestoreServiceAgent` para
  `service-<project-number>@gcp-sa-firebasestorage.iam.gserviceaccount.com`.
- La clave de Firebase Web es pública y se compila en la APK; el service account
  y las credenciales de administración permanecen solo en el servidor.
- El checkout filtra entregas/pagos desactivados en cliente y `orders.ts` vuelve
  a validarlos en servidor (`OrderPolicy`).

### Verificación

Web: 95 tests + `typecheck` + `build`. App: 86 tests + `analyze` +
APK release de 61,6 MB. E2E en `a791bc16`: login Firebase real, publicación de
configuración, imagen subida/leída/borrada en Storage con token admin, PATCH con
admin 200 / mesero 403 / sin token 401, mapas anidados preservados y favoritos
restaurados. `/api/og` genera PNG sin errores de fuentes emoji. La APK quedó
instalada en `a791bc16` y arranca sin `FATAL`; sin idToken muestra el login.
Sin commit/push ni despliegue de Netlify.

### Carrito y multimedia (ronda 15)

- `FloatingCartBar` y `CartQuantityBadge` son Client Components que leen
  `CartProvider`; el HTML del carrusel y de las fichas sigue siendo
  server-rendered para SEO/GEO. La barra se oculta en las rutas donde el
  carrito ya está visible.
- `image_picker` sin parámetros de compresión entrega el archivo original;
  `MediaUploadService.resolveMimeType()` compara extensión con magic bytes y
  bloquea los JPEG renombrados a `.gif`. El banner publicado pasó de un JPEG
  disfrazado a un GIF89a real de 3,5 MB, servido con `unoptimized` en el hero.
- El enlace legal del pie apunta a `wa.me/573125866072`.

### Pérdidas/caducados de ingredientes (ronda 16)

**Web (Firestore):** colección `inventoryLosses`. `GET/POST /api/inventory-losses`
exige `Bearer` y rol `admin`/`cook` resuelto desde claim o `users/{uid}`; el POST
guarda `lines`, `reason`, `notes`, `photoUrl`, `createdBy`, `receivedBy` y
`auditLog`, y valida cantidades > 0 y 1..30 ingredientes. No descuenta stock: eso
ya lo hace la APK con el PATCH de inventario.

**APK:** `core/models/inventory_loss.dart` define `LossReason`, `LossLine`,
`LossAuditEntry` e `InventoryLoss` (`toJson`, `fromJson`, `fromWebJson`,
`toWebJson`). `role.dart` añade `canRegisterInventoryLoss` (admin/cook) y
`canViewInventoryLosses` (admin). El repositorio persiste
`rm_inventory_losses_v1`, descuenta el stock local con
`upsertIngredient()` → `_queueIngredientPatch()`, y encola el registro. Al
reconectar: sube la foto a `inventory-losses/...` con `MediaUploadService`,
envía el POST con `Bearer` y añade la entrada «Sincronizado con la web»; en
401/403 conserva la cola y pide re-login. `pullInventoryLosses()` reconcilia con
`GET`, priorizando los pendientes locales.

**UI:** `features/inventory_losses/` contiene `RegisterLossScreen` (motivo,
líneas de ingredientes/cantidad, notas, cámara/galería) e
`InventoryLossesScreen` (foto, estado, registrador y auditoría expandible). El
tile «Pérdidas de inventario» vive en **Más** solo para admin; en **Inicio** el
cocinero ve la tarjeta y el FAB cambia a «Registrar pérdida».

**Storage:** `firebase/storage.rules` añade `match /inventory-losses/{fileName}`
con lectura pública, `create/update` para admin o cocinero y `delete` solo admin.
Desplegado con `firebase deploy --only storage`.

**Verificación real:** `GET/POST /api/inventory-losses` → 200 con tokens de
admin y cocinero, 403 con mesero y 401 sin token; los dos documentos QA se
borraron de Firestore. Subida directa a `inventory-losses/...` con token de
cocinero → 200 y borrado con admin → 204. APK release compilada; `adb devices`
no listó dispositivo en la última pasada, así que no se reinstaló en `a791bc16`.

### Redes, GPS, búsqueda IA e icono (ronda 18)

- `appearance.socialLinks.{instagram,tiktok,facebook}` y `appearance.gpsUrl`
  llegan en el mismo `PATCH` de apariencia. La web valida `http(s)`, acepta
  `null`/`""` para borrar y fusiona el mapa anidado con el documento remoto.
  `Footer.tsx` solo crea los enlaces cuando existen; el JSON-LD `Restaurant`
  publica `sameAs`/`hasMap`.
- `aiSearch.{description,keywords,serviceArea,highlights}` viaja desde
  Configuración. `generateMetadata()` usa descripción y palabras clave;
  `/llms.txt` publica los cuatro campos en una sección dedicada; el JSON-LD
  añade `keywords` y `areaServed`.
- Icono de launcher regenerado desde la captura indicada por el usuario en
  `mipmap-mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi` (48/72/96/144/192 px), escalado al
  cuadrado sobre el fondo oscuro original sin deformar el arte.
- Verificación: web 95 tests + `typecheck` + `build` ✅, home 200 en `:3001` con
  el hero `object-right lg:object-center` intacto; Flutter `analyze` ✅ y
  86 tests ✅. Sin despliegue a Netlify.

### Surtido, pedidos web y limpieza de interfaz (ronda 20)

- `InventoryScreen` añade **Surtir** en cada tarjeta de insumo. El diálogo valida
  cantidades > 0 (acepta coma decimal), muestra `Nuevo stock` en vivo y confirma
  con SnackBar; el rol debe tener `canManageMenu`.
- El sumando usa `Repository.adjustIngredientStock(id, delta)`, por lo que el
  stock se incrementa (nunca se reemplaza), se encola el PATCH offline y se
  recalcula la disponibilidad de los platos. La ficha se resalta en verde con
  «¡Surtido!» y «Stock actualizado» durante 3 segundos; el SnackBar usa el mismo
  verde y dura 4 segundos.
- Se revirtió la paleta experimental derivada del logo: `AppTheme` vuelve a
  `brand #EF6408`, `ink #1C1917` y `canvas #FAF8F5`, con indicador del
  `NavigationBar` al 14 % y avatar con el mismo tono. Se mantiene el tema claro.
- `OrderCard` diferencia los pedidos `source == 'web'` con fondo `#F0F9FF` y
  borde `#BAE6FD`, además de la insignia «Web». La ficha «Pedidos hoy» se quitó
  del inicio del administrador (cajero y cocinero conservan la suya).
- Se eliminaron de la interfaz el disparador «Enviar crash de prueba», los textos
  técnicos de Acerca de/Configuración/Acceso/Apariencia y el aviso de Firestore
  del menú web. La captura de errores en segundo plano sigue activa.
- Tests: `inventory_screen_test.dart` (suma, validación, permisos y efecto),
  `app_theme_test.dart` (paleta original), `order_card_test.dart` (tonos web/local)
  y `appearance_screen_test.dart` ajustado. Flutter `analyze` ✅ y 86 tests ✅;
  web `typecheck` ✅, 95 tests ✅ y `build` ✅. APK release 61,6 MB compilada con
  `WEB_API_URL` y `FIREBASE_WEB_API_KEY`, reinstalada en `a791bc16` con
  `adb reverse tcp:3001`, arranque sin `FATAL EXCEPTION` y `/api/health` 200.
  Commit y push realizados en `feature/app-reportes-cierre-caja`; sin Netlify.

