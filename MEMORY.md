# MEMORY.md â€” Resumen Vivo de Decisiones TÃ©cnicas

> Ãšltima actualizaciÃ³n: 2026-11-22

## Stack Real Entregado

| Capa | TecnologÃ­a | VersiÃ³n |
|---|---|---|
| Web | Next.js (App Router) + React + TypeScript | 16.4.6 / 19.3.1 / 5.7 |
| Estilos web | Tailwind CSS | 3.4.17 |
| Tests web | Vitest | 3.2.4 |
| App administrativa | Flutter + Dart | SDK ^3.12.2 |
| Estado app | provider | 6.1.5 |
| Persistencia app | shared_preferences + cola offline | 2.5.6 |
| Conectividad | connectivity_plus | 7.3.2 |
| Backend | Firebase (Firestore, Auth, Storage, Functions v2) | admin 13 / functions 6 |
| Functions | TypeScript sobre Node 20 | 5.7 |

### DesviaciÃ³n consciente del plan original
`AGENTS.md` fija Next.js 14, pero el entorno ya tenÃ­a **Next 16.4.6** instalado y
funcionando. Se mantiene Next 16 (App Router, mismas APIs de metadata, sitemap,
robots y route handlers) para no reinstalar dependencias ni romper el build.
Queda documentado aquÃ­ por ser un cambio de arquitectura respecto al plan.

## Decisiones Clave

1. **Monorepo** con separaciÃ³n estricta: `/docs`, `/web`, `/app`, `/firebase`.
2. **Modo demo por defecto.** Sin credenciales de Firebase la web y la app
   funcionan con datos semilla locales. Esto permite probar todo el flujo sin
   proyecto de Firebase y evita credenciales en el repositorio.
3. **Web pÃºblica** con SEO/GEO: metadata dinÃ¡mica por pÃ¡gina, JSON-LD
   (`Restaurant`, `Menu`, `MenuItem`, `BreadcrumbList`, `WebSite`), `sitemap.xml`,
   `robots.txt` y `llms.txt`.
4. **Precios siempre recalculados en servidor.** El cliente solo envÃ­a
   `menuItemId` y `quantity`; la web (`src/lib/orders.ts`) y la Function
   `placeOrder` resuelven precios desde el catÃ¡logo. Un total manipulado en el
   navegador no se persiste.
5. **Pedidos con lectura por capacidad.** `get` de `orders/{id}` es pÃºblico
   (UUID no adivinable, necesario para la pÃ¡gina de confirmaciÃ³n), pero `list`
   exige rol de personal. AsÃ­ la web no puede enumerar pedidos ajenos.
6. **App Flutter offline-first sin SDK nativo de Firebase.** La persistencia se
   resuelve con `shared_preferences` y una cola de pedidos pendientes; el
   adaptador de Firestore estÃ¡ aislado en `_runSync()` como punto de extensiÃ³n.
   Motivo: garantizar que el APK compile y se pueda probar sin `google-services.json`.
7. **Roles y transiciones en servidor.** `ROLE_TRANSITIONS` en
   `firebase/functions/src/domain.ts` define quÃ© rol puede mover un pedido a quÃ©
   estado; `updateOrderStatus` valida la transiciÃ³n dentro de una transacciÃ³n.
8. **LÃ³gica de dominio pura y testeable.** `domain.ts` no importa el SDK de
   Firebase, de modo que las reglas de negocio se pueden probar en aislamiento.
9. **Idempotencia en mÃ©tricas.** `onOrderCreated` escribe un marcador en
   `_processedEvents/{eventId}` dentro de la misma transacciÃ³n que actualiza
   `stats/daily-YYYY-MM-DD`, evitando doble conteo en reintentos.
10. **WhatsApp** vÃ­a enlace `wa.me` en la confirmaciÃ³n (MVP). WhatsApp Cloud API
    queda como fase futura.

## Modelo de Datos Efectivo

### `categories`
`id, name, slug, description, order, emoji`

### `menuItems`
`id, name, slug, description, price, categoryId, categorySlug, status
('available'|'unavailable'|'limited'), ingredients[], allergens[], emoji,
featured, prepMinutes, calories`

### `orders`
`id, code, customerName, customerPhone, deliveryAddress (string, obligatorio si type='delivery'),
type ('pickup'|'delivery'|'table'), tableNumber (null salvo type='table'),
items[{menuItemId,name,price,quantity,emoji}], subtotal, tax, total, status,
paymentStatus, paymentMethod, notes, source, createdAt, updatedAt`

Estados: `pending → confirmed → preparing → ready → delivered` para pickup/mesa, y
`pending → confirmed → preparing → ready → sent` para domicilio (`sent` reemplaza
`delivered` en domicilios). `cancelled` aplica a cualquier tipo. Todos los roles
pueden marcar `sent` en domicilios activos desde cualquier estado; la UI pide
confirmación si se saltan estados intermedios.

### `tables`
`id, number, status ('libre'|'ocupada'|'esperando_pedido'|'pidiendo_cuenta'),
capacity, currentOrderId, updatedAt`

### `users`
`uid, name, email, phone, role ('admin'|'cashier'|'waiter'|'cook'), status,
createdAt, lastLogin`

### `stats` / `reports`
Escritura exclusiva de Cloud Functions; lectura para personal.
`stats/daily-YYYY-MM-DD` y `reports/daily-YYYY-MM-DD`.

## Estado Actual (verificado)

- **Web**: `npm run build` âœ… 24 rutas (13 platos SSG, APIs dinÃ¡micas).
  `npm test` âœ… 21 tests en 3 archivos. `npm run typecheck` âœ….
- **Flutter**: `flutter analyze` âœ… sin issues. `flutter test` âœ… 22 tests
  (modelos, repositorio offline, widgets). APK release generado en
  `app/build/app/outputs/flutter-apk/app-release.apk`.
- **Firebase**: reglas endurecidas, Ã­ndices vÃ¡lidos, `firebase.json` y
  Cloud Functions compilando con `tsc` âœ….
- **Git**: repositorio inicializado con commit convencional inicial.

## Bugs Corregidos Durante la VerificaciÃ³n

1. **Listas semilla `const`**: `toggleAvailability` lanzaba
   `Unsupported operation: Cannot modify an unmodifiable list`. Ahora se copian
   con `[...SeedData.x]` al cargar y al resetear.
2. **Carrera en sincronizaciÃ³n**: `setOnlineForDemo(true)` no esperaba el sync
   disparado por el listener de conectividad. `syncPendingOrders()` usa
   `Completer` + `_syncFuture` y devuelve la operaciÃ³n en vuelo.
3. **Desbordamientos de layout** (`RenderFlex overflowed`) en la tarjeta de mesa
   del dashboard, `_TableCard` y `_TableSheet`: se sustituyeron `Spacer` en
   filas estrechas por `Expanded`/`Flexible` con `maxLines` + `ellipsis`.
4. **`firebase.config.ts` invÃ¡lido**: era un stub con identificadores sin
   comillas que rompÃ­a `tsc`. Reescrito leyendo `NEXT_PUBLIC_*` con
   `hasFirebaseConfig()`.
5. **Ãndices Firestore invÃ¡lidos**: el JSON original no era parseable
   (claves sin comillas, `mode` en lugar de `order`). Reescrito al formato
   oficial `collectionGroup` / `queryScope` / `fieldPath` / `order`.

## Reglas de Seguridad (resumen)

- CatÃ¡logo (`categories`, `menuItems`, `restaurant`, `tables`): lectura pÃºblica,
  escritura por rol.
- `orders`: `get` pÃºblico por ID; `list` solo staff; `create` validado por
  contrato (`isValidOrder()`); `update` solo staff y sin cambiar identidad
  (`preservesIdentity()`); `delete` solo admin.
- `users`: cada usuario lee su documento; admin gestiona el resto.
- `stats` / `reports`: lectura staff, escritura solo desde Functions.
- DenegaciÃ³n explÃ­cita por defecto (`match /{document=**} { allow ... if false }`).

## Variables de Entorno

`web/.env.local` (no versionado) o panel de Netlify:

```
NEXT_PUBLIC_FIREBASE_API_KEY=
NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN=
NEXT_PUBLIC_FIREBASE_PROJECT_ID=
NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET=
NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID=
NEXT_PUBLIC_FIREBASE_APP_ID=
NEXT_PUBLIC_FIREBASE_MEASUREMENT_ID=   # opcional
NEXT_PUBLIC_SITE_URL=https://tu-dominio.com
```

Con `API_KEY` y `PROJECT_ID` presentes y no placeholder, la web usa Firestore
REST; si faltan, opera en modo demo.

## Riesgos y Pendientes Conocidos

- **Firestore real sin probar**: no hay credenciales, asÃ­ que el camino REST y
  las reglas solo estÃ¡n verificados por revisiÃ³n y tests unitarios de validaciÃ³n.
- **Modo demo en memoria del servidor**: los pedidos demo viven en
  `globalThis` + `localStorage`; se pierden al reiniciar el proceso. Es
  intencional para la demo, no para producciÃ³n.
- **Firma del APK**: se usa la clave debug de Flutter. Para Play Store hay que
  generar un keystore y configurar `signingConfigs`.
- **Developer Mode de Windows deshabilitado**: `flutter pub get` advierte sobre
  symlinks; no bloquea el build Android.
- **Notificaciones push**: colecciÃ³n `notifications` modelada pero sin FCM
  implementado.
- **WhatsApp Cloud API**: pendiente; hoy solo enlace `wa.me`.

## Actualizaciones Futuras

Este archivo se actualiza en cada fase con decisiones nuevas, cambios de
esquema, rutas nuevas o modificaciones de permisos.

## Actualización 2026-11-22 (sincronización web↔app + inventario + recetas)

### Sincronización de pedidos web → app
- La web expone GET /api/orders con los pedidos demo (persistidos en
  web/.data/orders.json, excepto en tests).
- La app consulta esa API por HTTP cada 12 s (dart:io HttpClient), con URL
  configurable en Configuración o con --dart-define=WEB_API_URL=...
  (default http://192.168.101.7:3000). Los pedidos importados se marcan con
  badge «Web».
- Android: permiso INTERNET y usesCleartextTraffic=true para HTTP local.

### Inventario e ingredientes
- Nuevo modelo Ingredient + RecipeIngredient; MenuItem incorpora sku,
  imageUrl, ideoUrl, ecipeSteps y ecipe.
- SeedData incluye 43 insumos y recetas por los 13 platos.
- Al pasar un pedido a preparing se descuenta el inventario automáticamente
  (una sola vez, vía inventoryDeducted); se repone si se cancela.
- Pantalla «Inventario» (admin) con CRUD, stock mínimo y alerta de stock bajo.

### Mesas y cliente
- Al crear un pedido de mesa la mesa pasa a esperandoPedido (no ocupada) hasta
  que el pedido se pone en preparación.
- Los datos del cliente son opcionales en mesa; si falta el nombre se usa
  Mesa N. Pickup/delivery siguen exigiendo nombre y teléfono.

### Receta visible al cocinero
- ole.canViewRecipe (admin/cocinero). La receta estructurada y los pasos
  se muestran en el detalle del pedido para esos roles.
- La receta no se expone en la web pública.

### Auditoría por pedido
- Nuevo modelo OrderAuditEntry (acción, timestamp, actorId, actorName, detalle)
  persistido en Order.auditLog; viaja con el pedido en la cola offline.
- Se registra: creación, edición, agregar productos, cambios de estado,
  cancelación, inventario descontado/repuesto, pago, cobro grupal, liberar mesa,
  sincronización e importación desde la web.
- Pedidos antiguos se hidratan al cargar con una entrada inicial; el detalle
  muestra el timeline en orden reverso.

### Fotos de platos
- MenuItem, CartLine y OrderItem (app y web) incorporan imageUrl opcional.
- Widget MenuItemImage con fallback a emoji si no hay imagen o falla la carga.
- Seed de app y web usa URLs de Unsplash (requieren conexión); el admin permite
  pegar una URL o subir un archivo local.
- La web muestra fotos en catálogo, detalle, carrito y confirmación; el og:image
  del plato usa su foto cuando está disponible.

### Firebase
- Reglas: colección ingredients (lectura pública, escritura admin) y
  pedidos de mesa con cliente opcional.
- Functions: placeOrder acepta cliente opcional y marca la mesa ocupada;
  updateOrderStatus descuenta/reponer inventario al preparar/cancelar.

### Disponibilidad y límites por ingredientes
- Un plato con receta queda **agotado por insumos** cuando algún ingrediente de su receta tiene stock <= 0; vuelve a disponible al reponer stock (si el estado manual no es unavailable).
- App: RestaurantRepository.isMenuItemEffectivelyAvailable/availableAdditionalServings/_validateCartStock; vailableMenuItems filtra por disponibilidad efectiva; admin muestra "Agotado (sin insumos)" y deshabilita toggle; nuevo pedido bloquea agregar más de lo preparable.
- Validación de stock en app al crear/editar/agregar items a pedido (ddItemsToOrder valida delta si ya descontado, total resultante si no).
- Web: MenuItem.recipe/maxServings opcionales; getMenu() carga ingredientes en Firestore y calcula maxServings; carrito/botón/stepper respetan límite; createOrder valida consumo de ingredientes en servidor cuando Firestore está configurado. En modo demo sin inventario, no se aplica límite por falta de datos.

### CRM (admin app)
- Modelo `CustomerRecord` (`app/lib/core/models/customer.dart`) con teléfono normalizado, etiquetas, notas, métricas y fechas; persiste en SharedPreferences (`rm_customers_v1`).
- Solo clientes con teléfono válido (>=7 dígitos) aparecen en CRM. Se reconstruyen/actualizan desde pedidos y se upsert al crear/importar/cambiar pedidos.
- `CrmScreen`: búsqueda, orden (recientes/nombre/gasto/pedidos), exportar Excel vía `excel`+`share_plus`, detalle con etiquetas, notas, WhatsApp (`wa.me`), crear pedido con datos precargados (`NewOrderScreen` prefill) e historial.
- Sync CRM por API web: `GET/POST /api/customers` (Firestore REST, `setDocument`), repo hace pull/push best-effort como con pedidos. Reglas Firestore incluyen colección `customers` (staff read/create/update, admin delete).

### Stock en web
- `web/src/lib/seed.ts` incluye `demoIngredientStocks` y `demoRecipes`; `seedMenu()` calcula `maxServings` y marca agotado si no hay insumos.
- Validación exhaustiva: `getInsufficientItems` en `orders.ts`, endpoint `POST /api/orders/validate`, `CheckoutForm` pre-valida antes de crear pedido, muestra faltantes y reduce/quita del carrito; `createOrder`/API devuelven `insufficientItems`. Si falla la verificación de stock, la validación falla cerrada. En demo el stock no se descuenta por pedido.
