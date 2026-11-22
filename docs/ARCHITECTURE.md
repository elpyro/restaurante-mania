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
| `/` | Estática | Home con propuesta de valor, destacados y JSON-LD `Restaurant` |
| `/menu` | Dinámica (RSC) | Catálogo por categorías, filtros y búsqueda |
| `/menu/[slug]` | SSG (13 platos) | Ficha de plato con JSON-LD `MenuItem` |
| `/cart` | Estática (cliente) | Carrito persistido en `localStorage` |
| `/checkout` | Estática (cliente) | Datos de contacto, tipo de pedido y pago |
| `/order/[id]` | Dinámica | Confirmación con enlace `wa.me` |
| `/api/menu` | Route handler | Catálogo JSON cacheado (1 min, SWR 1 año) |
| `/api/orders` | Route handler | `POST` crear pedido validado |
| `/api/orders/[id]` | Route handler | `GET` pedido por ID |
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

1. `generateMetadata()` por página con `title`, `description`, `openGraph`,
   `twitter` y `alternates.canonical`.
2. JSON-LD embebido con `<script type="application/ld+json">`:
   `Restaurant` (home), `Menu` + `MenuItem` (catálogo y fichas),
   `BreadcrumbList` y `WebSite`.
3. `sitemap.ts` incluye home, menú y todas las fichas de plato.
4. `robots.ts` permite todo el catálogo y declara el sitemap.
5. `llms.txt` expone resumen, horarios, categorías, platos y endpoints para
   agentes (ChatGPT, Gemini, Perplexity).

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
| Administrador | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Cajero | ✅ | ✅ | ✅ | — | ✅ | ✅ |
| Mesero | ✅ | ✅ | ✅ | — | — | ✅ |
| Cocinero | ✅ | ✅ | — | — | — | ✅ |

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
`name, phone, email, address, status ('open'|'closed'), hours, promotions[],
currency, taxRate, updatedAt`

### `categories/{id}`
`name, slug, description, order, emoji`

### `menuItems/{id}`
`name, slug, description, price, categoryId, categorySlug,
status ('available'|'unavailable'|'limited'), ingredients[], allergens[],
emoji, featured, prepMinutes, calories, createdAt, updatedAt`

### `orders/{id}`
`code, customerName, customerPhone, type ('pickup'|'delivery'|'table'),
tableNumber, items[{menuItemId,name,price,quantity,emoji}], subtotal, tax,
total, status, paymentStatus ('pending'|'paid'|'refunded'),
paymentMethod ('cash'|'card'|'nequi'|'daviplata'), notes, source
('web'|'app'), createdBy, createdAt, updatedAt, lastChangedBy`

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
| `placeOrder` | Callable | Valida contrato, resuelve precios desde Firestore y crea el pedido en `pending` |
| `updateOrderStatus` | Callable | Transacción con control de rol, libera mesa al cerrar |
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

