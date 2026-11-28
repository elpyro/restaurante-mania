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

## 1.1 Instancias aisladas (multi-tenant real)

Tres tenants operativos: **`mania`** (por defecto), **`fuego`** y **`verde`**,
en el mismo proyecto Firebase (`restaurante-mania-e47a0`) y la misma base
Firestore `(default)`. La fuente de verdad es `tenants/{tenantId}/{collection}`
(`restaurant/config`, `categories`, `menuItems`, `ingredients`, `orders`,
`cashShifts`, `customers`, `users`, `inventoryLosses`, `webVisits`, `tables`).
No hay colecciones raíz operativas. El helper central es `tenantPath()` en
`web/src/lib/firebase/rest.ts`. El estado en memoria/local (`.data/`,
`localStorage`, `SharedPreferences`) es **solo caché/fallback** cuando Firestore
no está configurado (tests y desarrollo sin credenciales), nunca la fuente de
verdad.

Resolución del tenant activo (primera señal que gana):

1. Ruta pública `/menu/restaurante-<id>` (slug visible; `/menu` es `mania`).
2. Query string `?tenant=` (legado; redirige a la ruta amigable en páginas).
3. Header `X-Tenant-Id` (APIs y APK; no cambia).
4. Cookie `rm_tenant_id`.
5. Subdominio (`fuego.ejemplo.com`).
6. Fallback `mania`.

### Web

- `src/lib/tenants.ts`: registry, `normalizeTenantId`, `resolveTenantId`,
  `resolveTenantFromRequest`, `tenantStorageKey`, `tenantFromPath`,
  `tenantSlug` y `withTenant`. `withTenant("/", "mania")` → `/menu`;
  `withTenant("/", "taquitos-mexicanos")` →
  `/menu/restaurante-taquitos-mexicanos`.
- `src/proxy.ts` resuelve el tenant una vez por petición: `/` sirve la portada
  neutra, `/menu...` reescribe a las rutas internas (`/inicio`, `/menu`, …)
  conservando la URL visible, `/?tenant=<id>` redirige 307 a la ruta amigable
  y `/inicio` no se expone públicamente. Inyecta `x-tenant-id` y la cookie.
- `src/lib/tenant-directory.ts` construye el selector desde los tenants fijos
  más los documentos públicos `tenants/{id}` de Firestore. La portada es
  neutral (sin Header/Footer de restaurante) y muestra el aviso de
  **Software Manía** con WhatsApp `+57 312 586 6072`.
- `tenant-server.ts` lee las cabeceras con `headers()` async (incluido
  `x-rm-landing` para distinguir `/`); `client-tenant.ts` prioriza la ruta y
  añade el header en `fetch` del cliente. Header, Footer, `MenuBrowser` y
  `MenuItemCard` prefijan sus enlaces con `withTenant`.
- `src/lib/demo-store.ts` mantiene un estado por tenant **solo como fallback**
  cuando Firestore no está configurado. `menu.ts`, `orders.ts`,
  `cash-shifts.ts`, `restaurant-config.ts` y todas las rutas API resuelven el
  `tenantId` y escriben/leen bajo `tenants/{tenantId}/...` vía `tenantPath()`.
- Persistencia local (caché/offline): `.data/{tenantId}/orders.json` y
  `.data/{tenantId}/cash-shifts.json`; Manía sigue en `.data/orders.json` y
  `.data/cash-shifts.json`.
- `localStorage`: `mania` mantiene las claves legacy (`rm_cart_v1`); los demás
  usan `rm_{tenantId}_cart_v1`, `rm_{tenantId}_customer_profile_v1`, etc.
- El layout publica `window.__RM_TENANT_ID__`; RSC, metadata, sitemap y
  `llms.txt` resuelven el tenant desde la request.

### App Flutter

- `core/data/tenant.dart`: registry, normalización, `tenantHeader`,
  `tenantStorageKey` y `TenantPreferences` (envuelve `SharedPreferences` y
  prefija `rm_*_v1` por tenant). La preferencia global `rm_tenant_id_v1` no se
  prefija.
- `RestaurantRepository.load({tenantId})` resuelve el tenant y usa
  `SeedData.menuItemsFor/ingredientsFor/ordersFor`. Los 18 puntos HTTP envían
  `X-Tenant-Id`.
- `switchTenant(id)` cambia de instancia **sobre el mismo repositorio**:
  cancela el polling, desconecta el listener de conectividad, carga el nuevo
  tenant sin `watchConnectivity`, persiste la preferencia, copia el estado y
  reactiva listener y polling. Así el `ChangeNotifierProvider` no se recrea.
- `LoginScreen` muestra el selector de instancia con `mania`, `fuego` y
  `verde`; el header `X-Tenant-Id` viaja en las 18 peticiones HTTP.

### Aislamiento verificado

Tests dedicados web (`src/lib/__tests__/tenants.test.ts` y
`tenant-isolation.test.ts`) y Flutter (`test/tenant_test.dart`) comprueban la
prioridad de resolución, las claves de almacenamiento y que catálogo, stock,
pedidos, turnos, visitas y configuración de un tenant no aparecen en los demás.
Además se verificó en vivo: un pedido QA creado en `fuego` responde 200 en
`fuego` y 404 en `mania` (documento borrado después). Las reglas de Firestore
confirman el aislamiento a nivel de base de datos: rol de administrador resuelto
desde `tenants/{tenantId}/users/{uid}`, lectura pública del catálogo y
denegación de colecciones raíz.

## 2. Web (Next.js 16, App Router)

### Rutas

| Ruta | Tipo | Propósito |
|---|---|---|
| `/` | Dinámica (RSC) | Portada neutra: logo APK, selector de restaurantes y aviso de Software Manía |
| `/menu` | Dinámica (RSC) | Portada de Manía (tenant por defecto) |
| `/menu/menu` | Dinámica (RSC) | Catálogo de Manía por categorías, filtros y búsqueda |
| `/menu/restaurante-<id>` | Dinámica (RSC) | Portada del restaurante `<id>` |
| `/menu/restaurante-<id>/menu` | Dinámica (RSC) | Catálogo del restaurante `<id>` |
| `/menu/restaurante-<id>/menu/[slug]` | Dinámica | Ficha de plato con JSON-LD `MenuItem` |
| `/inicio` | Interna (rewrite) | Portada del tenant; no se expone directamente (307 a `/menu`) |
| `/?tenant=<id>` | Redirección 307 | Compatibilidad: lleva a `/menu/restaurante-<id>` (o `/menu` si es Manía) |
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
3. Las URL canónicas, `openGraph.url` y todo el JSON-LD usan rutas amigables
   por tenant (`/menu`, `/menu/restaurante-<id>`, `/menu/[slug]`); se construyen
   con `withTenant()`/`tenantUrl()` en `seo.ts`.
4. `sitemap.ts` incluye la portada neutra, la portada y el menú de cada tenant
   del directorio y las fichas del tenant activo.
5. `robots.ts` permite `/`, `/menu`, `/llms.txt` y el catálogo; declara el
   sitemap.
6. `llms.txt` expone resumen, horarios, redes, mapa, la sección «Datos para
   búsqueda con IA», categorías, platos, endpoints para agentes (ChatGPT,
   Gemini, Perplexity) y el WhatsApp de Software Manía. Las URL web usan el
   prefijo `/menu...` del tenant resuelto.
7. El pie y las tarjetas de plato enlazan dentro del mismo restaurante; el
   enlace «Inicio» nunca vuelve al selector.
8. El pie renderiza Instagram, TikTok, Facebook y «Ver en el mapa» solo cuando
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

Todas las Functions leen y escriben bajo `tenants/{tenantId}/...`.
`resolveTenantId()` prioriza el `tenantId` del payload, después el claim
`tenantId` y por último `mania`. `roleInTenant()` resuelve el rol desde
`tenants/{tenantId}/users/{uid}` y usa el claim global solo como fallback, para
que un rol de otra instancia no habilite acciones en ésta.

| Función | Tipo | Descripción |
|---|---|---|
| `health` | HTTP | Estado del servicio |
| `placeOrder` | Callable | Valida contrato, resuelve precios desde Firestore y crea el pedido en `pending` (sin descuento de inventario) |
| `updateOrderStatus` | Callable | Transacción con control de rol, descuenta/repone inventario de forma idempotente al cambiar desde `pending` y libera mesa al cerrar |
| `syncMenuStatusOnIngredientChange` | Trigger Firestore | Escrituras en `tenants/{tenantId}/ingredients/{ingredientId}`; recalcula disponibilidad del menú del tenant |
| `onOrderCreated` | Trigger Firestore | Creaciones en `tenants/{tenantId}/orders/{orderId}`; métricas diarias idempotentes |
| `dailySalesReport` | Scheduler (03:00 America/Bogota) | Consolidado del día anterior por tenant |

`src/domain.ts` contiene la lógica pura: `computeTotals`, `canTransition`,
`ROLE_TRANSITIONS`, `nextStatus`, `computeMaxServings`, `dayKey`,
`buildOrderCode` y validadores. No importa el SDK, por lo que es testeable en
aislamiento. Un insumo de receta sin documento de stock cuenta como `0`: el
plato se marca agotado en web, APK y Functions, nunca ilimitado.

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

> El bloque siguiente resume el esquema histórico de colecciones raíz. El
> contrato vigente antepone `tenants/{tenantId}` a cada ruta
> (`tenants/{tenantId}/orders/{id}`, `tenants/{tenantId}/menuItems/{id}`, ...),
> resuelve `role(tenantId)` desde el claim o desde
> `tenants/{tenantId}/users/{uid}` y deniega las colecciones raíz.

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
`--dart-define=FIREBASE_WEB_API_KEY=...`; en builds **release** cae en la clave
pública de producción `restaurante-mania-e47a0`, en debug/tests queda vacía. El
endpoint de sign-in es
`POST https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=...`;
el alias `signInWithEmailAndPassword` no existe y devuelve 404. Los tokens se
renuevan automáticamente 60 s antes de caducar. Si no hay API key se conserva
el login demo con contraseña `1234`. «Recuperar contraseña» envía
`accounts:sendOobCode` con `requestType=PASSWORD_RESET`: Firebase manda el correo
para establecer la clave y no requiere permisos de Auth Admin.

**Rol:** `loginWithFirebase` no exige un usuario local con el mismo correo; tras
`accounts:signInWithPassword` lee `tenants/{tenantId}/users/{uid}` con el idToken
(`GET /api/users/{uid}` → `_Route.get('users', uid, 'user')`) y resuelve el rol
(`admin`, `cashier`, `waiter`, `cook`); rol inválido/ausente → `ArgumentError`;
fallback local por email. `pullServerUsers()` solo para admin. **401** (sesión)
dispara re-login; **403** no.

**Transporte:** `DIRECT_FIRESTORE=true` (default producción): la APK habla
directamente con Firestore REST (`https://firestore.googleapis.com/v1/projects/
restaurante-mania-e47a0/databases/(default)/documents/tenants/{tenantId}`) con
idToken + `X-Goog-Api-Key`; `firestore.rules` es la única barrera. Todo `PATCH`
envía `updateMask.fieldPaths` repetido por campo (merge parcial; sin máscara
Firestore reemplaza el documento). Un pedido offline avanzado se crea en
`pending` y luego `PATCH` con estado real. Límites `isValidOrder` replicados en
`createOrder`. `DIRECT_FIRESTORE=false` + `WEB_API_URL=...` usa el transporte
web. `WEB_API_URL` ya no tiene IP LAN por defecto.

`provision-auth-users.mjs` crea usuarios con `accounts:signUp` y escribe su rol
en `tenants/{tenantId}/users/{uid}` (antes `users/{uid}`); acepta `TENANT=all`
para los tres tenants y no depende de custom claims ni de permisos de Auth
Admin.

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
- `firebase/storage.rules`: lectura pública. Escritura por tenant:
  `tenants/{tenantId}/appearance/**` solo admin del tenant;
  `tenants/{tenantId}/inventory-losses/**` admin o cocinero; rol =
  `tenants/{tenantId}/users/{uid}.role` (o claim `role`); se conservan rutas
  antiguas `appearance/**` / `inventory-losses/**`. MIME
  `image/(jpeg|png|webp|gif)`, tamaño < 6 MB. Reglas desplegadas con
  `firebase deploy --only storage`.
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
reconectar: sube la foto a `tenants/{tenantId}/inventory-losses/...` con `MediaUploadService`,
envía el POST con `Bearer` y añade la entrada «Sincronizado con la web»; en
401 conserva la cola y pide re-login; **403 no dispara re-login**. `pullInventoryLosses()` reconcilia con
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

## Migración total a multi-tenant real / limpieza (2026-11-26)

A petición del usuario se borraron **todos** los datos de prueba y se sembró
una estructura limpia con los tres tenants en el mismo proyecto y base
`(default)` (no se creó proyecto nuevo ni base secundaria).

- **Respaldos previos:** Firestore exportado en
  `gs://restaurante-mania-e47a0-backup-20261126/firestore`; Storage copiado en
  `%TEMP%/opencode/backup-20261126/storage` (3 objetos). Restauración Firestore:
  `gcloud firestore import gs://restaurante-mania-e47a0-backup-20261126/firestore`.
- **Borrado:** 211 documentos Firestore y 3 objetos Storage eliminados;
  `(ninguna)` colección raíz restante.
- **Siembra:** 230 documentos bajo `tenants/{tenantId}/...`. Conteos
  (categorías/platos/insumos/turnos/clientes): `mania` 4/7/42/10/10,
  `fuego` 4/12/43/1/0, `verde` 4/10/43/1/0; 10 mesas y 1 usuario admin por
  tenant (`Y72Vea5qAFcdW6AgBqBy0dSfyH92`, rol `admin`). Las URLs de logo/banner
  apuntaban a Storage borrado: se dejaron vacías para evitar enlaces rotos.
- **Reglas/índices:** `firebase/firestore.rules` y
  `firebase/firestore.indexes.json` reescritos para el prefijo
  `tenants/{tenantId}` y desplegados con
  `firebase deploy --only firestore:rules,firestore:indexes`. Verificación:
  `tenants/mania/restaurant/config` → 200 anónimo, `restaurant/config` → 403.
- **Checks:** web `typecheck` ✅, 107 tests ✅, `build` ✅ (sin warnings 403);
  Flutter `analyze` ✅ y 96 tests ✅. En vivo en `:3001` los siete endpoints de
  los tres tenants responden 200 con el `tenantId` correcto; `config` y `menú`
  declaran `source=firestore` y el resto `configured=true` con los conteos
  sembrados. Resolución por query/header/cookie/subdominio ✅; pedido QA
  aislado y borrado. Sin commit/push salvo solicitud.
- **SEO/GEO tras la siembra:** Next 16 entrega `params.slug` codificado en la
  página pero decodificado en `generateMetadata`; `decodedSlug()` en
  `src/app/menu/[slug]/page.tsx` normaliza ambos casos. Sin él, las fichas con
  `ñ` caían en `notFound()` y `robots: noindex`. Verificado con el build de
  producción en `:3001`: `ajiaco-santafereño` en `mania`/`fuego` y
  `arepa-con-queso` en `verde` → 200, `<h1>`, JSON-LD `MenuItem` y
  `robots: index, follow`. Tras el fix: 107 tests ✅ y `build` ✅.
- **APK en vivo:** release 61,6 MB instalada en `a791bc16` con
  `adb reverse tcp:3001`. El proxy de log registró el cambio
  `fuego → verde → manía` con `X-Tenant-Id` correcto en todas las peticiones y
  la persistencia del tenant tras `am force-stop`/relanzamiento; no hubo
  `FATAL EXCEPTION`. Quedó sin verificar el flujo autenticado (sin contraseña y
  el token de `gcloud` carece de permisos de Auth Admin), por lo que la prueba
  cubrió endpoints públicos y el header de tenant.
- **Usuarios QA y login real (2026-11-26):** se añadieron cuatro cuentas a la
  semilla local de la APK (`SeedData.users`) y a Firebase Auth con rol en los
  tres tenants: `admin.qa@restaurante.com` (admin), `cajero.qa@restaurante.com`
  (cashier), `mesero.qa@restaurante.com` (waiter) y `cocina.qa@restaurante.com`
  (cook). La contraseña se entregó fuera del repositorio. `flutter test` quedó
  en 96/96 tras aislar el test del «último administrador». En la web,
  `GET /api/inventory-losses` responde 200 para admin/cook y 403 para
  cashier/waiter en `mania`, `fuego` y `verde`.
- **Pantallas autenticadas verificadas:** APK recompilada, instalada con
  `pm clear`, tenant **Manía** y login con `admin.qa@restaurante.com`. Se
  recorrieron Inicio, Pedidos, Mesas, CRM y Más → Usuarios (8 cuentas, QA con
  su rol); sin `FATAL EXCEPTION`. El aviso «INSTANCIA DE LA DEMO» del login es
  texto heredado, no modo demo: la API key compilada habilita Firebase Auth y
  oculta los accesos rápidos.

### Sincronización de cuentas y diagnóstico de tenant (2026-11-26)
- El celular apunta a `http://localhost:3001` vía `adb reverse` con tenant
  **Manía**; la web en `:3001` prioriza `?tenant=` sobre la cookie
  `rm_tenant_id`. Un pedido creado sin el query quedó en `verde` y por eso no
  apareció en la APK. Para forzar Manía: `http://localhost:3001/?tenant=mania`.
- `web/src/app/api/users/route.ts` expone GET/POST/DELETE de
  `tenants/{tenantId}/users`, exige `Authorization: Bearer <idToken>` y rol
  `admin`, y valida id, nombre, correo y rol. `_pushUserToServer()` en
  `repository.dart` publica altas, ediciones y bajas desde la APK con el token
  y `X-Tenant-Id`; si falla, el cambio permanece en `SharedPreferences`.
- El documento en Firestore guarda `{uid, name, email, role, status,
  createdAt, updatedAt}` con el mismo contrato que
  `provision-auth-users.mjs`. Verificado GET/POST/DELETE con token QA y
  aislamiento entre `mania` y `verde`. El alta desde la APK **no** crea cuenta
  en Firebase Auth: hace falta la contraseña y el aprovisionamiento por script.
- El login ya distingue «INSTANCIA CON FIREBASE» de «INSTANCIA DE LA DEMO» según
  la API key compilada, y la pantalla de usuarios aclara que las cuentas se
  sincronizan con Firebase.
- **Prueba en vivo (2026-11-26):** con la APK reinstalada y el tenant Manía, un
  pedido creado en la web con `?tenant=mania` (`RM-20261126-OZH5`) apareció en
  Pedidos como «Web». Una cuenta creada desde Más → Usuarios
  (`sync.verificada@restaurante.com`) se creó en Firestore, el cambio de nombre
  se propagó con una edición y la baja eliminó el documento; en `verde` nunca
  existió. Sin `FATAL EXCEPTION`.

### Contrato multi-tenant de Functions y cierre QA (2026-11-26)
- **Despliegue verificado:** `6 Functions Deployed`, `0 Errors` en
  `restaurante-mania-e47a0`, base `(default)`. `firebase functions:list --json`
  confirma los triggers `tenants/{tenantId}/ingredients/{ingredientId}` y
  `tenants/{tenantId}/orders/{orderId}`. El primer deploy sin `--debug` agotó
  el timeout al resolver el backend; el retry con `--debug` finalizó
  correctamente.
- **Contrato compartido:** las callables y los triggers derivan `tenantId` de
  payload → claim → `mania`, y el rol se lee del documento del tenant con
  fallback al claim global. Las Functions siguen siendo stateless y usan la SDK
  de Firestore con `async/await`. Son la API de referencia; el flujo diario de
  web/APK usa sus propios endpoints/repositorio con el mismo contrato.
- **Inventario:** el usuario confirmó que el descuento no debe ocurrir al
  confirmar, sino al pasar de `pending` a un estado superior. Un insumo de
  receta sin documento se trata como stock `0` en `web/src/lib/orders.ts`,
  `web/src/lib/menu.ts`, `app/lib/core/data/repository.dart` y
  `firebase/functions/src/domain.ts`; el plato queda agotado, nunca ilimitado.
- **ID canónico de insumos:** `PATCH /api/ingredients/[id]` pasó de
  `createDocument` a `setDocument(tenantPath(...), documentId, ...)`, con test
  de regresión en `web/src/app/api/ingredients/[id]/__tests__/route.test.ts`.
  Se eliminó el documento aleatorio `adrxhCHsTiAuP6uRg46K` y se recreó `cafe`
  con stock `2000`; `mania` volvió a 43 insumos y 5 platos.
- **Prueba end-to-end:** `pollo3` → 409 (`available: 2`) y `cafe20` → 200. El
  pedido QA `RM-20261126-LXON` se creó `pending` con
  `inventoryDeducted=false`; `preparing` descontó pechuga 400→200, papa
  2300→2150, mantequilla 30→15 y lechuga 5.5→5.25; `cancelled` restauró los
  valores exactos. Los pedidos QA se borraron.
- **Checks finales:** web `typecheck` ✅, 116 tests ✅ y `build` ✅; Flutter
  `analyze --no-fatal-infos` ✅ y 97 tests ✅. APK release recompilada con
  `WEB_API_URL=http://localhost:3001` y la API key pública, instalada en
  `a791bc16` con `adb reverse tcp:3001`; arranque sin `FATAL EXCEPTION`. El
  servidor QA quedó en `:3001` con `/api/health` 200. Sin commit, push ni
  despliegue a Netlify.

### Horario configurable, estado en portada y propiedad del inventario (2026-11-26)
- **Configuración publicada por la APK:** `PATCH /api/restaurant/config`
  acepta `isOpen`, `timeZone` (IANA), `openingDays`, `openTime`, `closeTime`,
  `ctaTitle` y `ctaDescription`. La web normaliza y valida (`restaurant-config.ts`)
  y deriva `hours` del horario estructurado; por defecto `America/Bogota`,
  Lun–Sáb 11:30–20:30. `seo.ts`/`/llms.txt` usan días y horas reales.
- **Portada (SSR):** `opening-hours.ts` calcula
  `Abierto: recibiendo pedidos` / `Cerrado: abre a las HH:mm` en la zona
  configurada; si el siguiente día hábil cambia, incluye el día. El cierre
  manual (`isOpen=false`) usa la misma hora sin día. Es informativo: el
  checkout sigue abierto. Los dos textos del bloque final son editables desde
  Apariencia en la APK.
- **Cobro:** el hoja de pago solo muestra métodos activos y sus etiquetas
  configuradas; el detalle del pedido, el recibo PDF y el detalle de ventas
  muestran esa misma etiqueta.
- **Inventario sin doble descuento:** la APK descuenta sus propios pedidos al
  crearlos en `pending` (`createOrder`, flag `inventoryDeducted`) y repone al
  cancelar. Los pedidos `source='web'` los descuenta la web al pasar a
  `confirmed` (`updateOrder` decide desde el documento persistido, ignora el
  flag del PATCH con cambio de estado); la APK omite el flag en el PATCH y
  reconcilia el valor devuelto. Las Functions conservan su contrato por
  `tenants/{tenantId}`.
- **Checks:** web `typecheck` ✅, 125 tests ✅, `build` ✅; Flutter `analyze` ✅
  y 101 tests ✅. APK release instalada en `a791bc16` sin crashes y servidor QA
  `:3001` verificado (config, portada, `/api/og`, `/llms.txt`). Sin commit/push.

### Producción final: APK directa a Firestore y despliegue completo (2026-11-26)
- **Topología en producción:** la APK ya no depende de la web ni de una IP LAN:
  `RestaurantRepository` usa `FirestoreTransport` por defecto
  (`DIRECT_FIRESTORE=true`) con el idToken de Firebase Auth y la API key pública
  contra `https://firestore.googleapis.com/v1/projects/restaurante-mania-e47a0/.../tenants/mania`.
  El adaptador HTTP (`WEB_API_URL`, vacío por defecto) queda para QA/tests.
- **Datos que cruzan el límite:** pedidos, usuarios, ingredientes, caja,
  clientes, configuración, **catálogo completo y categorías**. `pullServerMenuCatalog()`
  reemplaza la semilla local por `menuItems` remotos y `pullServerCategories()`
  hace lo propio con `categories`, conservando los cambios offline pendientes.
  `updateMask.fieldPaths` se envía repetido en cada `PATCH` para no reemplazar
  documentos; solo `401` fuerza re-login (`403` = sin permiso).
- **Backend desplegado:** `firebase deploy --only "functions,storage,firestore:rules,firestore:indexes"`
  sobre `restaurante-mania-e47a0`: reglas multi-tenant y de Storage por tenant
  releaseadas, índices publicados y 6 Functions v2 activas que validan pedidos,
  sincronizan disponibilidad, calculan ventas diarias y sirven health.
- **Verificación en dispositivo (`a791bc16`):** login real con
  `castellanoseloy@gmail.com` (admin), estado «En línea», 43 insumos, 7 platos,
  7 cuentas y pedidos web reales. Los datos se leen de `tenants/mania`; la
  apariencia se sube a `tenants/mania/appearance/...`. No queda el pedido QA
  `RM-20261126-8816`.
- **Calidad y entrega:** web `typecheck`, 125 tests y `build` OK; Flutter
  `analyze` limpio y 108 tests OK. Commit convencional y push a
  `origin/feature/app-reportes-cierre-caja`. Netlify queda pendiente de dominio
  real (decisión del usuario: solo commit y Firebase).

