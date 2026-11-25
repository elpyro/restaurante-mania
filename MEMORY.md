# MEMORY.md â€” Resumen Vivo de Decisiones TÃ©cnicas

> Última actualización: 2026-11-24

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
| Functions | TypeScript sobre Node 22 | 5.7 |

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
  imageUrl, ideoUrl,
ecipeSteps y
ecipe.
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
-
ole.canViewRecipe (admin/cocinero). La receta estructurada y los pasos
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
- Modelo `CustomerRecord` (`app/lib/core/models/customer.dart`) con teléfono normalizado, etiquetas, notas, métricas, fechas y direcciones usadas (`addresses`); persiste en SharedPreferences (`rm_customers_v1`). Los campos antiguos `visitCount`/`visitHistory` se conservan por compatibilidad pero ya no se registran manualmente.
- Solo clientes con teléfono válido (>=7 dígitos) aparecen en CRM. Se reconstruyen/actualizan desde pedidos y se upsert al crear/importar/cambiar pedidos; direcciones de entrega se acumulan en `addresses`.
- `CrmScreen` tiene dos paneles: **Clientes** (búsqueda, orden, exportar Excel, detalle con etiquetas/notas/WhatsApp/crear pedido/historial) y **Visitas**. El panel Visitas muestra contador de visitas de hoy (originadas en la web), separación registrados/anonímicos, lista de registrados con nombre y enlace de referencia, y al tocar el contador abre el historial agrupado por día.
- Modelo `WebVisit` (`app/lib/core/models/web_visit.dart`) con timestamp, `dayKey` (America/Bogota), flag registrado, nombre/teléfono opcionales y `referenceUrl`/`referenceLabel`. Persiste en SharedPreferences `rm_web_visits_v1` y se descarga vía `GET /api/visits` en el polling de la app.
- Web: `VisitTracker` global en `layout.tsx` registra **una visita por cliente/día** (America/Bogota), no una por página. Mantiene `rm_web_visitor_id_v1` y el estado diario `rm_web_visit_state_v1`; si hay perfil con teléfono válido la identidad es `phone:<digits>`, si no `visitor:<uuid>`. El ID de Firestore es determinista (`vis_YYYY-MM-DD_<hash>`) y `POST /api/visits` usa `visitorId` para reemplazar el mismo documento; `GET /api/visits` y la app deduplican por cliente/día. `firestore.rules` permite crear visitas públicamente y listarlas solo para staff.
- Sync CRM por API web: `GET/POST /api/customers` (Firestore REST, `setDocument`), repo hace pull/push best-effort. Reglas Firestore `customers` permiten campos de direcciones/visitas.
- Web: perfil local `rm_customer_profile_v1` guarda nombre/teléfono/dirección/direcciones usadas; `/cuenta` muestra cliente registrado, direcciones usadas (solo lectura) e historial de pedidos del dispositivo; checkout permite cambiar dirección en nuevo pedido y recuerda direcciones.

### Stock en web
- `web/src/lib/seed.ts` incluye `demoIngredientStocks` y `demoRecipes`; `seedMenu()` calcula `maxServings` y marca agotado si no hay insumos.
- Validación exhaustiva: `getInsufficientItems` en `orders.ts`, endpoint `POST /api/orders/validate` (modo `stockOnly`) y `CheckoutForm` consulta el stock al cambiar el carrito: muestra faltantes, bloquea "Confirmar pedido" y permite ajustar cantidades antes de enviar. `createOrder`/API vuelven a validar y devuelven `insufficientItems`. Si falla la verificación de stock, la validación falla cerrada. En demo el stock no se descuenta por pedido.
- Catálogo público: `getPublicMenu()` filtra `status === "unavailable"`; se usa en inicio, `/menu`, detalle (404 para agotados), relacionados, JSON-LD, sitemap, `llms.txt` y `/api/menu`. El menú interno (`getMenu`) conserva los agotados para validación/auditoría.

### Conexión a Firebase real (Nov 2026)
- Proyecto Firebase activo: `restaurante-mania-e47a0` (App Web `1:815344581484:web:d29a716690981d3f375149`). `firebase/.firebaserc` apunta a ese proyecto; `firebase/service-account.json` es local/privado (cuenta `firebase-web-admin@restaurante-mania-e47a0.iam.gserviceaccount.com`, rol `datastore.user`) y NO se versiona.
- Reglas e índices desplegados: `firebase deploy --only firestore:rules,firestore:indexes`. Se eliminó un índice single-field innecesario en `tables` y se quitó BOM de `firestore.rules`.
- `web/src/lib/firebase/rest.ts` usa OAuth2 JWT firmado con la cuenta de servicio (`FIREBASE_SERVICE_ACCOUNT_JSON`) para las llamadas Firestore REST; así el servidor puede leer/escribir `customers`, `orders` y `webVisits` sin depender de reglas públicas. Si no hay cuenta de servicio, cae al API key para lecturas públicas.
- `orders.ts` ahora lista/lee/actualiza pedidos desde Firestore cuando hay configuración real (incluye pedidos `source: app` migrados); el modo demo sigue usando `web/.data/orders.json`.
- Migración idempotente ejecutada con `firebase/scripts/migrate-demo-to-firestore.mjs`: 4 categorías, 13 platos, 43 ingredientes, 10 mesas, configuración del restaurante, 36 pedidos (28 web + 8 app), 28 visitas reconstruidas desde pedidos web y 10 clientes derivados de pedidos. Las visitas de navegación anónimas del demo estaban solo en memoria del servidor y no se pudieron recuperar.
- Estado local actual: web en `http://localhost:3001` apuntando a Firestore real; `adb reverse tcp:3001 tcp:3001` activo; APK recompilada con `WEB_API_URL=http://localhost:3001`.
- Netlify no desplegado aún: `netlify.toml` preparado con `base = "web"`, build `npm run build` y adaptador automático de Next.js 16. Falta iniciar sesión Netlify y definir variables de entorno (incluyendo `FIREBASE_SERVICE_ACCOUNT_JSON` y `NEXT_PUBLIC_*`).

### Ajustes de visitas, menú y checkout (Nov 2026)
- `web/src/lib/visit-identity.ts` centraliza `dayKeyFor`, `normalizeDayKey` y `visitDocumentId`; el mismo documento se reescribe al volver el mismo cliente en el mismo día. `webVisits.visitorId` se agregó al contrato y a `firestore.rules` (reglas desplegadas el 2026-11-24).
- Las visitas históricas sin `visitorId` se deduplican en la API por `dayKey + teléfono normalizado` (registered) o por id (anónimas). La app reemplaza su copia local con el feed canónico, eliminando duplicados antiguos al sincronizar.
- Verificado en local contra Firestore real: `/api/visits` pasó de 40 a 14 visitas canónicas (7 para 2026-11-24); `/api/menu` pasó de 13 a 12 platos y ya no expone `item-cazuela-mariscos`; `POST /api/orders/validate` con `stockOnly` rechaza ese plato por falta de ingredientes y acepta `item-empanadas`.
- Checks: `npm run -s typecheck`, `npm run -s test` (27 tests) y `flutter analyze --no-fatal-infos` OK.

### Sincronización de disponibilidad del menú (Nov 2026)
- Causa del reporte "limonada agotada se pudo comprar": `toggleAvailability()` de la app solo escribía `SharedPreferences` (`rm_menu_items_v1`); nunca tocaba Firestore. La web lee Firestore, por eso seguía viendo `item-limonada-coco` como `available`. No apuntaba a otro proyecto: `/api/health` reporta `mode=firestore`, el pedido con 2 limonadas se creó en `restaurante-mania-e47a0` y el documento real tenía `status: "available"`.
- Nuevo contrato: `PATCH /api/menu/[id]` con `{ "status": "available" | "unavailable" }`. Valida el estado, verifica que el plato exista y escribe solo el campo `status` en `menuItems/<id>` mediante `setDocument` (REST + cuenta de servicio). La web no usa secretos en cliente.
- La app hace push del toggle a ese endpoint y mantiene una cola local `rm_pending_menu_statuses_v1` para cambios offline; al reconectar o cada 12 s hace flush. `pullServerMenuStatus()` reconcilia el estado local con `GET /api/menu/status` (feed interno de los 13 platos, incluidos agotados; `/api/menu` es público y no los devuelve), dando prioridad a los cambios pendientes de envío. `resetDemoData()` limpia la cola.
- Para evitar ventanas de venta con datos viejos, `/api/menu`, `/api/orders/validate`, home, `/menu`, detalle, `llms.txt` y `sitemap.xml` son dinámicos (`force-dynamic`); las lecturas de platos/insumos en `menu.ts` usan `revalidate: 0`. `getPublicMenu()` sigue ocultando agotados y el checkout los rechaza.
- Estado actual corregido: `menuItems/item-limonada-coco.status = "unavailable"` en Firestore real. `/api/menu` pasó de 12 a 11 platos y ya no expone la limonada; `POST /api/orders/validate` con `stockOnly` para ese plato devuelve 400.
- APK release recompilada con `--dart-define=WEB_API_URL=http://localhost:3001`, instalada en `a791bc16`; `adb reverse tcp:3001 tcp:3001` activo. La app al iniciar ya consulta `/api/menu` (visible en logs del servidor) y bajará el estado agotado.
- Checks tras el cambios: `npm run -s typecheck`, `npm run -s test` (30 tests), `flutter analyze --no-fatal-infos`, `flutter test` (22 tests) y `npm run -s build` OK, sin advertencias de render estático.

### Corrección de disponibilidad y checkout (2026-11-24)
- Smoke test web + APK + Firestore real: 10/10 casos OK; pedido `RM-20261124-5BWW` creado en la web, importado a la app con badge «Web» y cambiado a `confirmed` desde la app se reflejó en `/api/orders/[id]`. Detalle en `docs/QA-SMOKE-2026-11-24.md`.
- `isAvailable()` en `web/src/lib/menu.ts` exige ahora `status !== "unavailable"` **y** `maxServings !== 0`. Un plato agotado por insumos nunca entra en `getPublicMenu()` (ni catálogo, ficha, JSON-LD, sitemap ni `llms.txt`), aunque Firestore tenga `status: available`/`limited`.
- El checkout ya no solo bloquea el botón: al detectar insuficiencia vía `POST /api/orders/validate` muestra un `alertdialog`, recorta cada línea a la cantidad preparable con `adjustLinesForStock()` y elimina las que tienen `available: 0`; vuelve a validar antes de crear el pedido. Tests: 33 en web.

### Persistencia automática de `menuItems.status` (2026-11-24, ronda 2)
- **Regla de precedencia:** `manualStatus === "unavailable"` gana siempre. El stock puede poner `unavailable` cuando una receta queda a cero y devolver `available` al reponerse, pero nunca levanta un bloqueo manual. Solo `PATCH /api/menu/[id]` con `{status:"available", manual:false}` (o el toggle de la app) limpia `manualStatus` y recalcula según stock.
- Nuevos campos en `menuItems`: `manualStatus` (`"unavailable" | null`), `statusReason` (`"ingredients" | "manual"`) y `statusUpdatedAt`. `PATCH /api/menu/[id]` acepta `manual` y escribe esos campos. `GET /api/menu/status` los expone para la reconciliación de la app.
- Cloud Functions: `syncMenuStatusOnIngredientChange = onDocumentWritten("ingredients/{ingredientId}")` recalcula los platos cuyo `recipe` usa el insumo cambiado, con `deriveMenuItemStatus()` en `domain.ts`. Compila ✅. Runtime cambiado a `nodejs22` (Node 20 retirado el 2026-10-30). El deploy estuvo bloqueado por IAM (primero el service agent de Functions y luego el de Eventarc); resuelto en la ronda 3: Function `ACTIVE` y trigger verificado.
- Reconciliación equivalente ya activa en la web: `syncMenuStatusesFromStock()` en `web/src/lib/menu.ts`, invocada desde `PATCH /api/ingredients/[id]` y desde `PATCH /api/orders/[id]`. Cubre todos los cambios que pasan por la API web/app. Escrituras directas a Firestore requieren el trigger desplegado.
- Inventario compartido: nuevos `GET /api/ingredients` y `PATCH/DELETE /api/ingredients/[id]`; `deleteDocument()` agregado a `lib/firebase/rest.ts`. La app hace push/pull de stocks con cola offline `rm_pending_ingredient_stocks_v1`, prioriza cambios pendientes y recalcula estados locales con `_recomputeMenuStatuses()`.
- Unificación de IDs: la app usaba `cafe-huila` (receta 18 g / 180 ml) mientras web/Firestore usaban `cafe` (15 g / 200 ml). Seed, receta, migración persistida y test alineados a `cafe`. El backfill `firebase/scripts/backfill-menu-status.mjs --set cafe=0` dejó `ingredients/cafe.stock=0` y `item-cafe.status=unavailable` (`statusReason=ingredients`, sin bloqueo manual).
- Estado real verificado: con stock 0 el plato no aparece en `/api/menu`, `/menu`, ficha, JSON-LD, sitemap ni `llms.txt`; con stock 100 reaparece y `status=available`; bloqueo manual activo resiste stock 200; al desbloquear con stock disponible vuelve `available`. Durante la prueba la app escribió `cafe.stock=20` y la web reflejó `item-cafe=available` (12 platos públicos), confirmando la sincronización app → Firestore → web; el estado final depende del último ajuste de inventario.
- Checks: web `typecheck` ✅, **40 tests** ✅, `build` ✅; Flutter `analyze` ✅, **25 tests** ✅; Functions `build` ✅; APK release recompilada/instalada con `WEB_API_URL=http://localhost:3001`. Detalle en `docs/QA-SMOKE-2026-11-24.md`.

### Ronda 3 — trigger desplegado y motivo de estado (2026-11-24)
- La app encola los cambios automáticos de disponibilidad con `reason: 'ingredients'` y `manual: false`; el criterio de agotamiento usa porciones preparables (`floor(stock / quantity)`), no solo `stock <= 0`. `isMenuItemOutOfStockByIngredients()` usa el mismo helper, así que etiqueta y estado no pueden divergir. Un toggle manual pendiente nunca se sobrescribe. `pullServerMenuStatus()` recalcula después de aplicar el estado remoto (carrera corregida) y `DELETE /api/ingredients/[id]` también llama a `syncMenuStatusesFromStock()`.
- `setMenuItemStatus(id, status, manual, reason)` y `PATCH /api/menu/[id]` aceptan `reason` (`manual` | `ingredients`) y escriben `statusReason`. En web `syncMenuStatusesFromStock()` mantiene `reason` al reponer stock, en vez de forzar `"manual"`.
- IAM/despliegue resueltos: se creó la app de App Engine en `us-central`, se instaló el componente beta de gcloud, se creó la identidad `service-815344581484@gcp-sa-eventarc.iam.gserviceaccount.com` y se le dio `roles/eventarc.serviceAgent`. `firebase deploy --only functions:syncMenuStatusOnIngredientChange --project restaurante-mania-e47a0 --force` terminó con `Deploy complete!`; la Function está `ACTIVE` (Node 22, región us-central1, trigger en nam5).
- Verificación directa con `firebase/scripts/verify-menu-status-trigger.mjs` (escribe en Firestore sin pasar por la API): `stock=0` → `unavailable`, `stock=100` → `available`, ambos con `statusReason=ingredients` y `manualStatus=null`. Durante la prueba la app se desactivó con `pm disable-user --user 0 com.example.app` para evitar que su stock local sobrescribiera las escrituras; al terminar se reactivó con `pm enable`.
- Checks finales: web `typecheck` ✅, **41 tests** ✅, `build` ✅; Flutter `analyze` ✅, **28 tests** ✅, APK release ✅; Functions `build` ✅ + deploy ✅. Sin commit/push y sin despliegue de Netlify (web sigue solo en `localhost:3001`).

### Descuento desde `pending`, cancelación y navegación (2026-11-24, ronda 4)
- `inventoryDeducted` es el flag de idempotencia compartido. La web descuenta
  recetas al crear en `pending` y persiste el flag; `PATCH /api/orders/[id]` lo
  acepta. `placeOrder` (Functions) descuenta en transacción al nacer el pedido;
  `updateOrderStatus.shouldDeduct` incluye `pending`/`confirmed` además de los
  estados posteriores. La app descuenta pedidos propios al crear y, como
  fallback, pedidos web importados sin flag; al cancelar repone solo si el flag
  está en `true` y lo limpia para que Functions no reponga dos veces.
- Web: `ORDER_STATUS_LABELS.delivered = "Enviado"`; `AccountView` usa el mapa.
  La app conserva «Entregado» como etiqueta interna.
- App: «Menú» sale de la navegación principal; los admin lo abren desde «Más»
  con `MenuAdminScreen(showAppBar: true)`. Inventario muestra tres tarjetas
  (Insumos/Stock bajo/Sin stock) y encabezado; Reportes usa 2×2 `StatCard`; el
  detalle de pedido tiene «Cancelar pedido» con confirmación para cualquier rol
  en pedidos activos. «Más» quedó después exclusivo del admin (ver ronda 5).
- Los pedidos creados en la app son locales; su reposición se sincroniza con la
  cola de stocks absolutos (`/api/ingredients/[id]`), no con
  `PATCH /api/orders/[id]` (ese endpoint aplica a pedidos web importados).
- Checks: web `typecheck` ✅, **46 tests** ✅, `build` ✅; Functions `build` ✅ +
  deploy de `placeOrder,updateOrderStatus` ✅; Flutter `analyze` ✅, **30 tests**
  ✅; APK release instalada en `a791bc16`, `adb reverse tcp:3001` y web
  `mode=firestore`.
- Smoke real: pedido web `RM-20261124-VZ4O` creado en `pending` con flag y
  descuento (`cafe` 20→5, `agua` 20000→19800); PATCH a `delivered` mantuvo el
  flag. Pedido APK `RM-20261124-9909` cancelado repuso `masa-maiz` +120,
  `carne-res` +80, `papa-criolla` +50, `hogao` +30 en Firestore. Detalle en
  `docs/QA-SMOKE-2026-11-24.md`.
- Sin commit/push y sin despliegue de Netlify.

### Filtros, accesos rápidos, «Más», ventas y usuarios (2026-11-24, ronda 5)
- `InventoryScreen` usa `_InventoryFilter { all, low, out }`. «Insumos» fuerza
  `all`; «Stock bajo» alterna `low` con `all` y filtra por `Ingredient.isLow`
  (`stock <= minStock`, incluye stock cero); «Sin stock» alterna `out` con `all`
  y filtra por `stock <= 0`. El encabezado refleja el filtro activo.
- `AppShell`: «Más» (`AppTab.more`) solo aparece para `UserRole.admin`. El admin
  gana la pestaña `tables` para que el acceso rápido del Inicio funcione.
  Destinations: admin `[dashboard, orders, tables, crm, more]`, cajero
  `[dashboard, orders, tables, reports]`, mesero `[dashboard, tables, orders]`,
  cocinero `[dashboard, orders]`.
- El Inicio admin incorpora `_AdminQuickLinks`: «Ingredientes Bajo Stock»
  abre `InventoryScreen(showAppBar: true)` y «Mesas disponibles» llama a
  `onNavigate(AppTab.tables)`. Ambos muestran su valor actual.
- `ReportsScreen`: la `StatCard` «Ventas cobradas» tiene `onTap` y abre
  `SalesDetailScreen(orders: paidOrders)` (mismo conjunto que suma el KPI:
  `paymentStatus == paid` y no cancelados). Cada fila abre `OrderDetailScreen`.
- `MoreScreen` agrega el tile «Usuarios» solo para admin. `UsersScreen` hace
  alta/edición/eliminación local con `RestaurantRepository.addUser/updateUser/
  deleteUser`. `AppUser.copyWith` permite cambiar nombre, correo y rol.
- Las cuentas se persisten en `SharedPreferences` (`rm_users_v1`) y participan
  en `login`/`loginAs`; la contraseña sigue siendo la demo compartida
  `SeedData.demoPassword`. No hay contraseñas por usuario ni sync Firestore.
  No se puede eliminar la propia cuenta ni dejar menos de un administrador.
- `resetDemoData()` limpia `rm_users_v1` y restaura `SeedData.users`.
- Checks: Flutter `analyze` ✅, **32 tests** ✅; APK release instalada en
  `a791bc16` con `WEB_API_URL=http://localhost:3001`; verificación en dispositivo de
  filtros, accesos, roles, detalle de ventas y CRUD de usuarios. Sin
  commit/push y sin despliegue de Netlify. Detalle en
  `docs/QA-SMOKE-2026-11-24.md`.

### Pendiente no descuenta; `statusUpdatedAt` idempotente (2026-11-24, ronda 6)
- **Contrato vigente (supersede la ronda 4):** `pending` **no** descuenta
  ingredientes. Cualquier estado superior distinto de `cancelled`
  (`confirmed|preparing|ready|sent|delivered`) descuenta **una sola vez**;
  `cancelled` (y reabrir a `pending`) repone y limpia el flag. Aplica a web
  (`createOrder` nace con `inventoryDeducted: false`, `updateOrder()` hace
  descuento/reposición), Functions (`placeOrder` ya no descuenta;
  `updateOrderStatus.shouldDeduct` excluye `pending`) y app
  (`createOrder` local, `_isDeductibleStatus`, import de pedidos web,
  `markOrderPaid` y `editOrder`). `markOrderPaid` evalúa el estado final que
  persiste (`delivered`/`sent`), así cobrar un pedido en `pending` también
  descuenta una sola vez.
- **Sobre escritura de estados de menú:** `setMenuItemStatus()` compara
  `status`, `manualStatus` y `statusReason` efectivos antes de `setDocument`;
  si no hay cambio, no actualiza `statusUpdatedAt`. `PATCH /api/menu/[id]`
  devuelve el estado efectivo (`{item:{id,status}}`). La app consume esa
  respuesta en `_flushPendingMenuStatuses()`, adopta el estado corregido y
  limpia la cola, en vez de reenviarlo cada 12 s.
- `pullServerMenuStatus()` ya no llama a `_recomputeMenuStatuses()`: el
  inventario remoto se aplica en `pullServerIngredients()`. El sondeo de la
  app se secuencia con `_pullWebCatalogState()`:
  `_flushPendingIngredientStocks → pullServerIngredients →
  _flushPendingMenuStatuses → pullServerMenuStatus`.
- **Dueño único del stock (corrección de "la web nunca descuenta"):** la web
  descuenta los pedidos con `source: 'web'`. `updateOrder()` decide solo con
  el flag **persistido** (`wasDeducted`), sin mirar el `inventoryDeducted`
  entrante; la app envía siempre `false` en el PATCH para que la web aplique
  el descuento con su valor guardado. La app ya no descuenta ni repone
  localmente pedidos web (ni en `updateOrderStatus`, `markOrderPaid`,
  `updateOrder` ni `addItemsToOrder`); tras el PATCH llama a
  `pullServerIngredients()`. `pullServerOrders()` adopta el flag remoto en
  ambos sentidos y, si un pedido web heredado está en estado superior sin
  flag, lo reconcilia con un PATCH. Test de regresión: PATCH con
  `status: confirmed` **y** `inventoryDeducted: true` debe descontar una vez.
- Sin commit/push todavía.

### Inicio admin simplificado (2026-11-24, ronda 7)
- Se eliminó «Ventas últimos 7 días» del Inicio para administrador **y** cajero; el gráfico de 7 días sigue disponible en Reportes (`reports_screen.dart`).
- Desapareció el bloque «Accesos rápidos» y sus botones «Ver inventario» / «Ver mesas». El grid de KPIs del admin incorpora «Mesas ocupadas» con formato `ocupadas/total` (`2/10` con el seed) y tap a `AppTab.tables`; «Ingredientes agotados» abre `InventoryScreen(showAppBar: true)`.
- `AppShell`: el admin ya no ve «Mesas» en la `NavigationBar`, pero conserva el destino en el `IndexedStack` para que la tarjeta del Inicio funcione. Cajero, mesero y cocinero mantienen su navegación. Mientras se ve Mesas, la barra marca «Inicio» (`NavigationBar` no admite `selectedIndex: -1`).
- Tests: `widget_test.dart` ya no espera el texto de ventas y verifica `2/10`, 4 destinos de barra para admin y la apertura de Mesas desde la tarjeta.

### Inventario en tiempo real bidireccional (2026-11-24, ronda 8)
- Síntoma: la app bajaba el `stock` de `/api/ingredients` cada 12 s, pero el KPI «con stock bajo» no coincidía con la web porque `pullServerIngredients()` solo actualizaba `stock`; ignoraba `minStock`, `name`, `unit` y los insumos borrados en Firestore.
- `mergeServerIngredients()` (en `repository.dart`, `@visibleForTesting`) reconcilia el inventario local con el feed de la web: aplica stock/mínimo/nombre/unidad, respeta los ids con patch pendiente (offline-first), conserva el `cost` local y quita los insumos que ya no existen en el servidor. La descarga se aborta si la API responde `configured: false`.
- La cola `rm_pending_ingredient_stocks_v1` pasa de `id -> stock` a `id -> {name, unit, stock, minStock}`; el lector migra el formato antiguo. Así, editar un insumo en la APK sube también nombre, unidad y stock mínimo (`PATCH /api/ingredients/{id}` ya los acepta). El `cost` sigue siendo local porque la web no lo publica.
- `_onConnectivityChanged()` dispara `_pullWebCatalogState()` al volver a estar online; `RefreshIndicator` del Inicio usa `refreshAll()` (pedidos + catálogo + clientes + visitas).
- Tests nuevos para la fusión (`mergeServerIngredients`): aplica valores de la web, conserva `cost`, respeta pendientes y elimina borrados remotos. `flutter analyze` ✅ y `flutter test` ✅ 36 tests.

### Guard del pull de ingredientes (2026-11-24, ronda 8)
- Síntoma corregido: los descuentos de insumos no aparecían en la APK hasta reiniciar, aunque los estados de platos sí se actualizaban. `pullServerIngredients()` activaba `_pullingServerIngredients` y nunca lo liberaba en el `finally` (solo cerraba el cliente). El primer pull del arranque dejaba el guard en `true`; los sondeos de 12 s y `refreshAll()` salían por el early-return. `pullServerMenuStatus()` y `pullServerOrders()` sí resetean sus guards, por eso los platos seguían funcionando.
- Fix: `_pullingServerIngredients = false` en el `finally` de `pullServerIngredients()` (`app/lib/core/data/repository.dart`), con el mismo patrón que los otros pulls. No se cambió `mergeServerIngredients()` ni la cola `rm_pending_ingredient_stocks_v1`.
- Test de regresión aislado en `app/test/repository_ingredient_pull_test.dart`: servidor HTTP local (sin `TestWidgetsFlutterBinding`, porque el binding intercepta `HttpClient` y devuelve 400) comprueba dos pulls consecutivos y la recuperación tras un 500. Verificado que falla sin el fix y pasa con él. `flutter test` ✅ 37 tests; `flutter analyze --no-fatal-infos` ✅.
- Verificación en `a791bc16`: PATCH `carne-res` `2560 → 2000 → 1500 → 2560`, reflejado en ≤15 s sin reinicio; pedido web `98z5XJCWGFJhINas5T4c` avanzado a `preparing` descontó `2560 → 2480` y la APK lo mostró en ≤15 s. APK release recompilada con `WEB_API_URL=http://localhost:3001`; `adb reverse` activo.
- Hallazgo de la ronda 8, corregido en la ronda 9: `loadIngredientStocks()` (`web/src/lib/orders.ts`) usaba `listDocuments("ingredients", mapper)` con `revalidate = 60` por defecto; al cancelar, la reposición leía el stock previo al descuento y dejaba `2640` en vez de `2560`.

### Reposición de inventario al cancelar (2026-11-25, ronda 9)
- Síntoma reportado: cancelar un pedido web no devolvía los ingredientes (`RM-20261125-BRUI`, 1 × patacones; descuento a las `00:22:05Z`, cancelación a las `00:22:37Z` sin cambio de stocks y con `inventoryDeducted=false`).
- Causa 1: `updateOrder()` priorizaba la copia en memoria (`cached ?? (isFirestoreConfigured() ? await getOrderById(id) : null)`). Con Firestore configurado, un `inventoryDeducted` viejo en `demoOrders()` hacía que la rama de reposición nunca corriera. Fix: con Firestore configurado, siempre `await getOrderById(id)` (lectura fresca vía `getDocument`, que ya cae al caché local si falla); sin Firestore se mantiene `demoOrders().get(id)`.
- Causa 2: `loadIngredientStocks()` usaba el `revalidate = 60` por defecto de `listDocuments()`. Fix: pasar explícitamente `0` como tercer argumento, igual que ya hacen `menu.ts` y `getInsufficientItems`.
- Test de regresión en `web/src/lib/__tests__/orders.test.ts`: pedido creado en modo demo con flag `false`, `getDocument` devolviendo `true`, cancelar → verifica `setDocument("ingredients", "maiz-blanco", {stock: before})`, flag limpio y que ninguna lectura de insumos use 2 argumentos. Verificado que falla sin el fix. Web: `typecheck` ✅, **51 tests** ✅, `build` ✅.
- E2E: pedido `WlnJ2Z3d6WxZGLQNx01t` (1 × arepa) `5000/1000/800 → preparing 4900/940/790 → cancelled 5000/1000/800`; la APK mostró la reposición en ≤16 s. El primer intento falló (`5100`) porque el puerto 3001 seguía sirviendo el build anterior con `next start`: **hay que reiniciar el proceso tras `npm run build`**, no basta con recompilar.
- Compensación manual del pedido reportado: `platano-verde 0→1`, `queso-campesino 720→760`, `tomate 1080→1120`, `cebolla 1310→1340`. Datos QA finales: `carne-res=2560`, `maiz-blanco=2300`, `mantequilla=805`, `vainilla=195`.
- Sin commit/push y sin despliegue de Netlify.

### Diálogo de insumos agotados en el Menú admin (2026-11-25, ronda 10)
- El `Switch.adaptive` de `menu_admin_screen.dart` ya no se deshabilita cuando el plato está agotado por insumos. Si se intenta activar (`value == true && outByIngredients`), se llama a `_explainOutOfStock()` en vez de `toggleAvailability()`; el plato no cambia de estado.
- `IngredientShortage` (`core/models/ingredient.dart`) guarda el insumo y la cantidad que exige una porción. `RestaurantRepository.outOfStockIngredientsFor(MenuItem)` (`core/data/repository.dart`) devuelve todas las líneas de receta con `stock + 0.0001 < quantity`, usando el mismo criterio que `_preparableServings()`; por eso explica exactamente por qué aparece «Agotado (sin insumos)».
- El `AlertDialog` indica «No se puede poner disponible», lista nombre, stock real y cantidad necesaria de cada insumo, y ofrece «Cancelar» o «Ir a ingredientes». El botón hace `Navigator.pop(true)` y abre `InventoryScreen(showAppBar: true)`, igual que los accesos desde Inicio/Más.
- Tests: uno de repositorio (dos faltantes a la vez) y uno de widget (switch → diálogo → Inventario, sin cambio de `manualUnavailable`). El test de widget se bombea con `MenuAdminScreen` dentro de `MaterialApp` + `ChangeNotifierProvider`: desde `AppShell`/`IndexedStack` aparecía un conflicto de `Hero` del `FloatingActionButton` al hacer push. `flutter test` ✅ 39 tests; `flutter analyze --no-fatal-infos` ✅.
- APK release recompilada con `WEB_API_URL=http://localhost:3001`, instalada y verificada en `a791bc16` (hubo que reconectar el teléfono y rehacer `adb reverse tcp:3001 tcp:3001`). Al tocar el switch de «Cazuela de mariscos» apareció el diálogo con Camaron (0/100), Calamar (0/80) y Pescado (0/120); «Ir a ingredientes» abrió Inventario con esos 3 insumos sin stock; «Cancelar» dejó el plato como `Agotado (sin insumos)`.
- Sin commit/push y sin despliegue de Netlify.

### Reportes largos, cobrador y cierre de caja (2026-11-24, ronda 11)
- `Order` guarda `paidAt`, `paidBy` y `paidByName` además de `createdAt`/`updatedAt`. `paidAtOrFallback` usa `updatedAt` en pedidos heredados pagados y `paidByNameOrFallback` distingue origen web (`Web pública`), auditoría local y «Sin registro». `markOrderPaid`/`markGroupPaid` sellan el cobro y la cola de sincronización reenvía la metadata, así el nombre no depende de cambios posteriores.
- `CashShift` (`core/models/cash_shift.dart`) es una foto del turno: `openedAt`, `openedBy/Name`, `closedAt`, `closedBy/Name`, `orderCount`, `total`, `totalsByPaymentMethod`, `closingAmount`, `notes` y `status`. `expectedCash` y `difference` salen de los totales; los contadores vivos se recalculan desde pedidos pagados, nunca se suman a la foto.
- `closeShift()` exige `role.canCloseShift` (admin o cajero), guarda la foto, abre otro turno con `openedAt = ahora`, persiste ambos y encola el cierre por `shiftId`. `_flushPendingCashShiftClosures()` reenvía el cierre con idempotencia por id y adopta el `currentShift` remoto si es más reciente. `pullCashShifts()` fusiona historial sin sobrescribir cierres pendientes. `refreshAll()` y el sondeo de conectividad incluyen turnos.
- Reportes: por defecto **Turno actual** (gráfico por horas). **Histórico** ofrece 7/30/90 días y rango personalizado; agrupa por día hasta 14 días, semana hasta 90 y mes en adelante. `Por cobrar` se mantiene global; KPIs, ranking y métodos de pago respetan el ámbito elegido. `SalesDetailScreen` es pública y muestra «Cobrado por: ...» con `paidAtOrFallback`; `CashShiftDetailScreen` reutiliza esa lista para turnos cerrados.
- Web: `types.ts` extiende `Order` y agrega `CashShift`; `orders.ts` mapea la metadata y `updateOrder()` la acepta (generando valores por defecto al pasar a `paid`); `PATCH /api/orders/[id]` la recibe. Nuevos `lib/cash-shifts.ts` y endpoints `/api/cash-shifts` (GET) y `/api/cash-shifts/close` (POST) con `setDocument` por id, un único turno abierto y reintentos idempotentes. Reglas para `cashShifts` (lectura staff, escritura admin/cajero) e índice `status + openedAt DESC`.
- Arreglos de la verificación en dispositivo: `pullServerOrders()` ahora compara y aplica `paidAt`/`paidBy`/`paidByName` aunque `status` y `paymentStatus` no cambien (antes un pago sellado en la web seguía mostrando «Web pública» en la app); agrega una entrada de auditoría «Cobrador actualizado desde la web» solo cuando hay nombre nuevo. `pullCashShifts()` no mete el turno abierto en `_closedShifts` y purga la entrada heredada con el mismo id, porque el historial mostraba el turno «En curso» como cerrado.
- Tests: 48 en Flutter (metadata, rangos de 30 días, cierre/rearme, permisos, UI de reportes, propagación del cobrador, historial de turnos) y 59 en web (metadata de pago, turnos idempotentes, endpoints). `flutter analyze --no-fatal-infos` ✅, `typecheck` ✅, `npm test` ✅. El test de dashboard dejó de depender de `todaySales` (a medianoche los pedidos semilla caen en el día anterior) y valida el total de 7 días. Sin commit/push y sin despliegue de Netlify.
- Cierre de QA en dispositivo `a791bc16` (25/11/2026): APK final instalada con `WEB_API_URL=http://localhost:3001` y `adb reverse` activo. Turno activo `25/11 00:18` queda fuera del historial; el turno `00:02` aparece cerrado con su pedido y coincide con la web; `RM-20261125-1O35` conserva `Cobrado por: QA Cajero`. Sin commit/push ni despliegue.

