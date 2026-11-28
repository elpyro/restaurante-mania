# MEMORY.md â€” Resumen Vivo de Decisiones TÃ©cnicas

> Última actualización: 2026-11-26

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

### Apariencia publicable desde la APK y rediseño web (2026-11-25, ronda 12)
- **Documento canónico:** `restaurant/config` en Firestore se extendió con `slogan`, `heroTitle`, `heroDescription`, `heroBadge` y `appearance.preset` (`mania|fuego|verde|noche`), además de `updatedAt`. La web y la APK comparten exactamente ese contrato; los defaults coinciden (eslogan: «Cocina colombiana hecha con calma y servida con cariño.», preset `mania`).
- **Web:** `src/lib/restaurant-config.ts` centraliza tipos, defaults, presets, `getRestaurantConfig()` con `cache()` por request, `tokensToCssVars()`, `presetThemeColor()` y `sanitizeConfigPatch()` (whitelist y longitudes). `GET /api/restaurant/config` es público; `PATCH /api/restaurant/config` exige `Authorization: Bearer <idToken>` y solo acepta los campos de apariencia. El layout inyecta variables CSS del preset y deriva metadata/viewport del documento; se rediseñaron home, menú, ficha, carrito, checkout, orden, cuenta y estados (`loading/error/not-found`); se añadieron `/api/og` (`next/og`) e iconos (`lucide-react`). SEO/GEO, carrito, checkout y stock se conservaron.
- **Autorización:** `src/lib/firebase/admin.ts` verifica el ID token con `firebase-admin` y toma el rol del claim `role` **o** de `users/{uid}` / email en Firestore. El service account del proyecto tiene permisos de Firestore (`datastore.user`), no de Auth Admin, por eso no se pueden escribir custom claims. No hay secretos en cliente.
- **APK:** tile «Apariencia» en «Más» (solo admin) abre `AppearanceScreen`: 4 presets con vista previa, campos con `maxLength`, estado Sincronizado/Pendiente/Sin conexión/Sin sesión y botones «Guardar en la web», «Recargar desde la web» y «Restablecer». **No se introdujo tema oscuro en la APK.** `RestaurantAppearance` se persiste en `rm_restaurant_appearance_v1` con cola offline `rm_pending_restaurant_config_v1`; 401/403 conservan la cola y piden re-login.
- **Auth real sin SDK nativo:** `AuthService` usa Firebase Auth REST con tokens en `flutter_secure_storage` y `FIREBASE_WEB_API_KEY` inyectado con `--dart-define` (clave pública). El endpoint correcto es **`accounts:signInWithPassword`**; `accounts:signInWithEmailAndPassword` devuelve 404 y fue corregido. `loginWithFirebase()` conserva el rol del usuario local con el mismo correo, así que el login demo `1234` sigue vigente si no hay API key.
- **Aprovisionamiento QA:** `firebase/scripts/provision-auth-users.mjs` crea usuarios con `accounts:signUp` (REST público) y escribe su rol en `users/{uid}` (ruta real `tenants/{tenantId}/users/{uid}` desde la migración multi-tenant); no usa custom claims ni contraseñas en el repo. Usuarios creados: `admin@restaurante.com` (uid `xSvkhWqmvVRTX8ZI38Ym0BmJf5T2`, rol admin), `qa-waiter@restaurante.com` (waiter) y `qa-admin@restaurante.com` (admin).
- **Smoke real (25/11/2026):** web: PATCH sin token → 401, con token admin → 200, con token waiter → 403, preset `fuego` visible en HTML y `/api/og` → 200. APK en `a791bc16`: login Firebase real, «Más → Apariencia», publicar `fuego` + eslogan `QA_APK_cocina_de_prueba`; la web reflejó ambos en API, HTML y `llms.txt`. «Recargar desde la web» restauró los valores originales. Configuración final: `preset=mania` y eslogan original.
- **Checks:** web `typecheck` ✅, **74 tests** ✅, `build` ✅ (incluye `/api/og`); Flutter `analyze` ✅ y **53 tests** ✅; APK release recompilada con `WEB_API_URL=http://localhost:3001` y `FIREBASE_WEB_API_KEY=...`, instalada en `a791bc16` con `adb reverse tcp:3001` activo. Web sirviendo con `npx next start -p 3001` en `mode=firestore`.
- **Pendiente:** no hay commit/push ni despliegue de Netlify; la configuración de apariencia se publica en localhost.

### Integración de Firebase Crashlytics en la APK (2026-11-25)
- Aclaración: Crashlytics **no es Firestore**; es un producto Firebase separado y solo reporta crashes de apps nativas. La consola del proyecto `restaurante-mania-e47a0` seguía «esperando el primer error» porque la app Flutter no tenía ningún SDK nativo de Firebase (decisión 6 del stack).
- Se añadieron `firebase_core: ^5.2.0` y `firebase_crashlytics: ^6.1.0` a `app/pubspec.yaml` (resueltos con `flutter pub add`; versiones compatibles con Flutter 3.44.6 / Dart 3.12.2).
- Nuevo `app/lib/core/services/crash_reporter.dart`: inicialización best-effort de Firebase, `FlutterError.onError` + `PlatformDispatcher.instance.onError` y `sendTestCrash()`. `main.dart` solo llama a `CrashReporter.initialize()`; sin configuración nativa la app sigue arrancando en modo demo.
- Disparador de QA en `MoreScreen`: tile «Enviar crash de prueba» compilado solo con `--dart-define=ENABLE_CRASH_TEST=true`, con diálogo de confirmación. En builds de producción no aparece, pero la captura automática sigue activa.
- Gradle: los plugins `com.google.gms.google-services` (4.4.4) y `com.google.firebase.crashlytics` (3.0.5) se declaran en `settings.gradle.kts` con `apply false` y se aplican en `app/build.gradle.kts` **solo si** existe `app/android/app/google-services.json`. Así no se rompe el build demo actual.
- `app/.gitignore` ignora `google-services.json` y `GoogleService-Info.plist`. Instrucciones completas en `docs/CRASHLYTICS-SETUP.md`.
- **Pendiente del usuario:** descargar `google-services.json` de Firebase console (app Android con package `com.example.app`; si no existe, registrarla) y colocarlo en `app/android/app/`. Sin ese archivo es imposible enviar el crash: no se puede generar un evento desde fuera de la app ni con el service account actual (solo rol `datastore.user`, sin permisos de Management API).
- Checks: `flutter test` ✅ 53 tests; `flutter analyze --no-fatal-infos` ✅; build release en curso al cerrar esta nota.

### Web llamativa y configurable desde la APK (2026-11-25, ronda 13)
- **Contrato ampliado:** `restaurant/config` incorpora `countryCode`, `phone`,
  `whatsapp` (compacto derivado para `wa.me`), `city`, `currency`,
  `showOrderTypeOptions`, `deliveryOptions` (`pickup|delivery|table`),
  `paymentMethods`, `paymentMethodLabels` y `appearance.{bannerUrl,logoUrl,
  customColors,preset}`. Preset `custom` usa 7 colores base (`brand`, `accent`,
  `surface`, `ink`, `heroFrom`, `heroTo`, `footer`) y `buildCustomTheme()`
  deriva el resto de tokens. `formatMoney()` respeta la moneda publicada.
- **Fusión de mapas:** `PATCH /api/restaurant/config` fusiona `appearance`,
  `deliveryOptions` y `paymentMethodLabels` con la configuración actual; enviar
  solo el preset ya no borra banner/logo. `appearance.bannerUrl/logoUrl`
  aceptan `null` para eliminar la imagen.
- **Streaming y Storage:** `MediaUploadService` sube/borra JPG/PNG/WEBP/GIF a
  Firebase Storage vía REST con `Authorization: Firebase <idToken>`; no usa
  plugins nativos. `firebase/storage.rules` permite lectura pública y escritura
  solo admin (claim `role` o documento `users/{uid}`), con límite de 6 MB y
  validación de MIME. Registro `storage` añadido a `firebase/firebase.json`
  (emulador 9199) y reglas desplegadas con `firebase deploy --only storage`.
- **Puente Storage↔Firestore:** como el service account no puede escribir custom
  claims, Storage necesita leer `users/{uid}`. Se habilitó concediendo
  `roles/firebaserules.firestoreServiceAgent` a
  `service-815344581484@gcp-sa-firebasestorage.iam.gserviceaccount.com`. Sin ese
  rol la subida devuelve 403 aunque el usuario sea admin en Firestore. El CLI de
  Firebase se colgaba en Windows por el chequeo de actualizaciones: se usa
  `$env:NO_UPDATE_NOTIFIER='1'; $env:FIREBASE_CLI_DISABLE_AUTOUPDATE='1'`.
- **Home y navegación:** portada con banner de fondo atenuado + texto encima,
  logo, favoritos en carrusel con enlace al plato y estado vacío; `Header` con
  logo, sticky, CTA móvil fijo, WhatsApp flotante y microinteracciones. Si no hay
  favoritos se muestra una invitación a marcarlos desde la app.
- **Checkout dinámico:** lee `/api/restaurant/config`, filtra tipos de entrega y
  métodos de pago publicados, aplica etiquetas y moneda, y oculta
  «¿Cómo quieres recibirlo?» cuando `showOrderTypeOptions=false`. `orders.ts`
  y `/api/orders/validate` validan la política también en servidor, así un
  cliente no puede enviar una opción desactivada.
- **Favoritos:** se reutiliza `menuItems.featured`. `PATCH /api/menu/[id]`
  acepta `{featured: boolean}` y **ahora exige token de admin**: sin token 401,
  con otro rol 403. La APK envía `Bearer` en los push de `status` y `featured`;
  si falla la lectura del token, la cola conserva el cambio para reintentarlo.
- **Colas offline nuevas:** `rm_pending_restaurant_config_v1`,
  `rm_pending_config_patch_v1` y `rm_pending_featured_items_v1`.
- **Smoke real (25/11/2026):** subida/lectura pública/borrado de un GIF QA en
  `appearance/` con el token de `admin@restaurante.com` → OK. Config: PATCH admin
  200, mesero 403, mapas anidados preservados, badge restaurado. Favoritos: sin
  token 401, mesero 403, admin 200 y `featured` restaurado. `/api/og` → 200
  `image/png` sin errores de fuentes emoji.
- **Regresión nueva:** `web/src/app/api/menu/[id]/__tests__/route.test.ts` cubre 8 casos del endpoint: sin token 401, rol no admin 403, token inválido 401, Admin no disponible 503, admin publica `featured`/`status`, validación de cuerpo y 404 si el plato no existe.
- **Checks de la ronda 13:** web `typecheck` ✅, **85 tests** ✅, `build` ✅
  (24 rutas); Flutter `analyze` ✅, **58 tests** ✅; APK release ✅ instalada en
  `a791bc16` con
  `WEB_API_URL=http://localhost:3001` y `adb reverse tcp:3001`. Sin commit/push
  y sin despliegue a Netlify.

### Ajustes finales de portada y sesión (2026-11-25, ronda 14)
- **Hero:** se quitó la ficha lateral derecha («Arepa con queso / Favorito de la
  casa / $9.500») pero se conserva la columna vacía para lucir el banner. El
  atenuado bajó a `from-ink/60 via-ink/40 to-ink/55` y el GIF se sirve con
  `unoptimized` para que siga animado. QA real en HTML: `heroCardGone=true`,
  `atenuacionLigera=true`, `bannerGifSinOptimizar=true`.
- **Carrusel de favoritos:** `FavoritesCarousel` es Client Component; avanza
  cada 3,2 s, vuelve al inicio, pausa en `mouseenter`/foco y respeta
  `prefers-reduced-motion`. QA: `carruselClient=true`, `favoritos=true`.
- **Logo:** `appearance.logoUrl` se usa también en el pie. QA con logo/banner QA
  subidos: `logoVeces=4` (header + pie + attrs). Config QA restaurada
  (`bannerUrl=null`, `logoUrl=null`, preset `noche`, COP, Medellín).
- **Contraseña:** `AuthService.sendPasswordReset()` usa
  `accounts:sendOobCode` con `PASSWORD_RESET`; el login muestra «Recuperar
  contraseña» solo con API key Firebase. Llamada real: `Reset OK
  email=admin@restaurante.com`.
- **Colores propios:** `_ColorPickerDialog` HSV sin dependencias nuevas; al
  tocar la muestra de color se abre cuadro SV, barra de tono y hex.
- **Sesión/sincronización:** con API key compilada y sin idToken, `load()`
  descarta la sesión local (borra `rm_session_v1`) sin tocar las colas;
  `AuthGate` vuelve al login. Apariencia muestra
  «Sin sesión Firebase · inicia sesión para publicar» o
  «Inicia sesión Firebase para publicar» con botón «Ir a iniciar sesión».
  «Sincronizar ahora» llama a `_flushPendingRestaurantConfig()` desde
  `_runSync()` y su contador incluye la configuración pendiente.
  `_syncRestaurantConfig()` quedó solo como `GET` para evitar dos PATCH al
  reconectar; el flush del sondeo se llama por separado.
- **Storage:** 401/403 dan «Sesión de Firebase vencida o sin permisos…»; la
  falta de red y el timeout tienen mensajes propios (`networkMessage`,
  `timeoutMessage`). Cubierto por `app/test/media_upload_service_test.dart`.
- **Checks finales:** web `typecheck` ✅, **85 tests** ✅, `build` ✅ (24 rutas),
  servidor `npx next start -p 3001` (`/api/health` 200) ✅; Flutter `analyze` ✅,
  **63 tests** ✅, build release 56,4 MB ✅. APK reinstalada en `a791bc16` con
  `adb reverse tcp:3001` y arranque sin `FATAL`; `FlutterSecureStorage` registró
  el fallback a cifrado propio tras la reinstalación (esperado: fuerza login y
  descarta el token anterior). Sin commit/push ni despliegue a Netlify.

### Carrito flotante, badges y GIF animado (2026-11-25, ronda 15)
- **Causa del GIF quieto confirmada:** `image_picker` con `imageQuality: 90`
  decodificaba solo el primer frame y guardaba un JPEG con nombre `.gif`.
  `_pickAsset()` ya llama a `pickImage()` sin `imageQuality`/tamaños: el plugin
  devuelve la ruta original cuando no hay reescalado (verificado en
  `ImageResizer.java`: `shouldScale = maxWidth != null || maxHeight != null ||
  imageQuality < 100`).
- **`MediaUploadService`:** `mimeTypeFromBytes()` detecta JPEG/PNG/WEBP/GIF
  (`GIF87a`/`GIF89a`) por magic bytes y `resolveMimeType()` rechaza un `.gif`
  cuyo contenido no es GIF antes de subirlo. 4 tests nuevos (total Flutter 67).
- **QA real del banner:** se recuperó el GIF original de Descargas (3,5 MB,
  `GIF89a`), se subió como `appearance/banner-1795622928864.gif` con token
  admin, se actualizó `restaurant/config.appearance.bannerUrl` y se borró el
  objeto antiguo que era un JPEG disfrazado. La URL pública responde
  `image/gif`, 3.503.986 bytes y firma `GIF89a`; el hero la usa con
  `unoptimized`, así que el GIF se anima.
- **Carrito flotante:** `FloatingCartBar` (Client Component) aparece abajo al
  centro con unidades y total `formatCOP(totals.total)`; se oculta en `/cart`,
  `/checkout` y `/order/*`. `CartQuantityBadge` muestra la cantidad sobre la
  imagen en `MenuItemCard` y en las tarjetas del carrusel de favoritos.
- **Botones inferiores:** se eliminó la barra móvil «Ver menú» de `Header.tsx`
  y el WhatsApp flotante pasó a `bottom-24 right-4 md:bottom-6 md:right-6` para
  no solaparse con la barra del carrito. El `<main>` usa `pb-28 md:pb-24`.
- **Pie:** «© 2026 Restaurante Manía. Otro software de Software Mania.
  Adquierelo: +573125866072» enlaza a `wa.me/573125866072` con mensaje de
  compra del software.
- **QA HTML:** `heroGifUrl=true`, `footerText=true`, `footerPhoneLink=true`,
  `oldVerMenuBar=false`, `waShifted=true`, `footerOldText=false`,
  `/api/health` 200 en modo `firestore`.
- **Checks:** web `typecheck` ✅, **85 tests** ✅, `build` ✅ (24 rutas);
  Flutter `analyze` ✅, **67 tests** ✅, APK release 56,4 MB ✅ reinstalada en
  `a791bc16` con `adb reverse tcp:3001` y arranque sin `FATAL EXCEPTION`
  (`Fully drawn`, `FlutterSecureStorage` sin token → login). Sin commit/push ni
  Netlify.

### Recuperación de contraseña de castellanoseloy@gmail.com (2026-11-25)
- Diagnóstico: `accounts:sendOobCode` devuelve 200 incluso para correos que no
  existen (Firebase oculta la enumeración), así que la APK mostraba éxito sin
  que hubiera cuenta. `addUser()` de la APK solo crea un usuario local; no crea
  la cuenta en Firebase Auth. En Firestore solo había 3 usuarios QA, ninguno con
  ese Gmail.
- Solución aplicada con `firebase/scripts/provision-auth-users.mjs`: usuario
  Firebase Auth `castellanoseloy@gmail.com` (uid
  `Y72Vea5qAFcdW6AgBqBy0dSfyH92`) con contraseña temporal no guardada en el
  repositorio y documento `users/{uid}` con `role: admin`, `status: active`.
  Verificado en Firestore.
- Se llamó a `accounts:sendOobCode` (`PASSWORD_RESET`) para ese correo: 200 OK.
  El enlace llega desde Firebase; si no aparece, revisar SPAM/Promociones.
- Para iniciar sesión en la APK, además debe existir el usuario local con ese
  mismo correo (`loginWithFirebase` lo exige para conservar el rol).

### Pérdidas y caducados de ingredientes (2026-11-25, ronda 16)
- Nueva colección Firestore `inventoryLosses` y endpoints
  `GET/POST /api/inventory-losses` con `Bearer` y rol `admin` o `cook`
  (claim `role` o `users/{uid}`, como el resto de la web). El POST guarda
  `createdBy`, `receivedBy`, `lines`, `reason`, `notes`, `photoUrl` y `auditLog`;
  valida 1..30 ingredientes y cantidades > 0. **No descuenta stock**: la APK ya
  envió el PATCH de inventario, así se evita un doble descuento.
- APK: `core/models/inventory_loss.dart` (`LossReason`, `LossLine`,
  `LossAuditEntry`, `InventoryLoss`), permisos `canRegisterInventoryLoss`
  (admin/cook) y `canViewInventoryLosses` (admin). Persistencia
  `rm_inventory_losses_v1`; `registerInventoryLoss()` descuenta stock local con
  `upsertIngredient()` y encola el registro. `_flushInventoryLosses()` sube la
  foto a `inventory-losses/...`, envía el POST con `Bearer` y añade la auditoría
  «Sincronizado con la web»; `pullInventoryLosses()` reconcilia desde `GET`,
  priorizando pendientes locales. El sondeo de 12 s, la reconexión,
  `refreshAll` y «Sincronizar ahora» también vacían la cola.
- UI: `features/inventory_losses/inventory_losses_screen.dart` contiene
  `RegisterLossScreen` (motivo, varias líneas ingrediente/cantidad, notas, foto
  con `ImageSource.camera` y opción de galería) e `InventoryLossesScreen`
  (foto, estado, registrador, auditoría). Tile «Pérdidas de inventario» en
  **Más** solo admin, con «Registrar pérdida» dentro; en **Inicio** el cocinero
  ve tarjeta y FAB para registrar. Meseros/cajeros no lo ven.
- `firebase/storage.rules`: nuevo `match /inventory-losses/{fileName}` con
  lectura pública, `create/update` para admin o cocinero según
  `users/{uid}.role` y `delete` solo admin. Reglas compiladas y desplegadas con
  `firebase deploy --only storage` (sin tocar Netlify).
- Checks: web `typecheck` ✅, **91 tests** ✅ (6 nuevos del endpoint), `build`
  ✅; Flutter `analyze` ✅, **75 tests** ✅ (3 modelo, 2 repositorio, 3 UI).
  APK release ✅ 56,6 MB en
  `app/build/app/outputs/flutter-apk/app-release.apk`.
- Smoke real (25/11/2026): con el servidor reiniciado en `:3001`,
  `GET/POST /api/inventory-losses` dieron 200 con tokens de admin
  (`admin@restaurante.com`) y cocinero (`cook-qa@restaurante.com`, creado con
  contraseña temporal no guardada), 403 con mesero y 401 sin token. El `GET`
  devolvió ambos documentos con `auditLog` de una entrada. Subida a
  `inventory-losses/...` con token de cocinero → 200 y borrado con admin → 204;
  los dos documentos QA se eliminaron de Firestore. `adb devices` no listó
  dispositivo, así que no se reinstaló en `a791bc16`. Sin commit/push ni
  Netlify.

### Recibo de pedido en la APK (2026-11-25, ronda 17)
- Web: el hero usa `object-right` en móvil (recorte al extremo derecho) y
  `lg:object-center` en escritorio. El primer intento se revirtió porque el
  rebuild se hizo con `next start` activo; desde entonces se detiene el servidor
  antes de cada `next build` y se reinicia al terminar.
- APK: nuevo `core/services/receipt_print_service.dart`. Genera un PDF de recibo
  de 80 mm con `pdf`/`printing`, fuente Geist embebida en
  `app/assets/fonts/Geist-Regular.ttf` (acentos sin Google Fonts), datos de
  `RestaurantSettings`, productos, totales, pago, notas y cliente. Abre el
  diálogo de impresión del sistema con `Printing.layoutPdf`; no es thermal ni
  Bluetooth.
- UI: `features/orders/order_detail_screen.dart` muestra un `IconButton` con
  tooltip «Imprimir recibo» para cualquier rol y estado del pedido. Errores se
  avisan con SnackBar. Tests: `test/receipt_print_test.dart` valida el PDF y el
  botón. Flutter pasó de 75 a 77 tests.
- Checks: Flutter `analyze` ✅, 77 tests ✅. Sin commit/push ni Netlify.

### Redes sociales, GPS, búsqueda IA e icono APK (2026-11-25, ronda 18)
- **Petición del usuario:** en Apariencia, campos para Instagram/TikTok/Facebook
  y GPS; mostrarlos en el pie de la web solo si existen. En Configuración,
  campos de datos para búsqueda de IA. Logo de la APK:
  `C:\Users\eloy_\Pictures\Captura de pantalla 2026-11-20 104117.png`.
- **Contrato:** `appearance.socialLinks.{instagram,tiktok,facebook}` y
  `appearance.gpsUrl` (URLs `http(s)`, máx. 300/500 caracteres; `null` o vacío
  borra). `aiSearch.{description,keywords,serviceArea,highlights}` (500/300/120/
  300 caracteres, espacios colapsados). `sanitizeConfigPatch` y el `PATCH`
  fusionan ambos mapas con el documento actual; las claves desconocidas se
  ignoran. `RestaurantAppearance`/`RestaurantSettings` comparten el contrato con
  la web y conservan los datos en la cola offline.
- **Web:** `Footer.tsx` añade chips de redes y «Ver en el mapa» condicionales
  (Lucide no trae iconos de marca: se usan `Camera`, `Music2` y `Share2` con
  etiqueta textual). `generateMetadata()` usa `aiSearch.description` y sus
  palabras clave/zona; `restaurantJsonLd()` publica `sameAs`, `hasMap`,
  `areaServed` y `keywords`; `/llms.txt` incluye redes, mapa y la sección
  «Datos para búsqueda con IA». El hero sigue `object-right lg:object-center`.
- **APK:** `AppearanceScreen` normaliza dominios pegados prefijando `https://`
  y publica los 4 enlaces; `SettingsScreen` añade «Datos para búsqueda de IA»
  con otro botón de guardado. Se actualizaron tests de contrato, PATCH y widget
  (los botones de Apariencia ahora requieren scroll en el test).
- **Icono:** `app/android/app/src/main/res/mipmap-*/ic_launcher.png` regenerado
  en 48/72/96/144/192 px desde la captura de 496×295, centrado sobre su fondo
  verde oscuro y con interpolación bicúbica; sin distorsión ni tema oscuro nuevo.
- **Checks:** web `npm test -- --run` 95 ✅, `typecheck` ✅, `build` ✅; servidor
  `next start -p 3001` detenido antes del build, reiniciado después y home 200.
  Flutter `analyze` ✅ y `flutter test` 79 ✅. Release compilado con los mismos
  dart-defines (61,6 MB) e instalado con `adb install -r` en `a791bc16`; el
  arranque por `monkey` no dejó `FATAL EXCEPTION`. Sin commit, push ni Netlify.

### Surtido de inventario y colores del logo (2026-11-25, ronda 19)
- **Petición del usuario:** botón «Surtir» en los ítems de ingredientes que abra
  un cuadro de texto para preguntar cuánto agregar, sumarlo al inventario y
  confirmar; además, colores de la APK relacionados con los del logo
  `C:\Users\eloy_\Pictures\Captura de pantalla 2026-11-20 104117.png`.
- **Muestreo del logo:** dominan `#0C110F` (fondo), `#FFFFFF` y `#D3FA30`
  (limón). Paleta APK: `ink #0C110F`, `accent #D3FA30`, `brand #4B5A00`,
  `brandDark #303A00`, `canvas #F6F8F3`, `success #3F7D20`, `warning #B45309`,
  `danger #C62828`. Se conserva `Brightness.light`; el indicador de
  `NavigationBar` usa el limón al 40 %.
- **Surtido:** `_IngredientTile` muestra `FilledButton.tonalIcon` «Surtir» solo
  si `role.canManageMenu`. `_openRestock()` pasa por `_RestockDialog`
  (decimales con `.`/`,`, error si ≤ 0, vista previa del nuevo stock) y llama a
  `adjustIngredientStock()`, que **suma** al stock, encola el PATCH de insumo,
  recalcula estados de menú y muestra SnackBar con el nuevo `stockLabel`.
- **Tests:** nuevos `app/test/inventory_screen_test.dart` (suma 250 g a
  `masa-maiz`, validación y rol mesero sin botón) y
  `app/test/app_theme_test.dart` (paleta y tema claro). `flutter analyze` ✅,
  `flutter test` ✅ 84 tests.
- **APK:** release 61,6 MB compilada con `WEB_API_URL=http://localhost:3001` y
  `FIREBASE_WEB_API_KEY=AIzaSyBycOm9eJ1KlhTXwxUcaGx2ZZwvfE5TJns`, instalada con
  `adb install -r` en `a791bc16` tras `adb reverse tcp:3001 tcp:3001`; arranque
  por `monkey` sin `FATAL EXCEPTION`, actividad `com.example.app/.MainActivity`
  en primer plano y `/api/health` 200 en modo `firestore`. Sin commit, push ni
  despliegue a Netlify.

### Ajustes finales de UI y commit (2026-11-25, ronda 20)
- **Petición del usuario:** revertir el tema experimental (no gustó), quitar
  «Pedidos hoy» del inicio del administrador, hacer visible el surtido en la
  ficha del insumo, eliminar mensajes al programador en APK/web, hacer commit y
  push, y distinguir los pedidos de origen web de los hechos por meseros.
- **Tema:** se restauró `AppTheme` a `brand #EF6408`, `brandDark #C64B09`,
  `ink #1C1917`, `canvas #FAF8F5`, `success #059669`, `warning #D97706` y
  `danger #E11D48`. Se eliminó la constante `accent`; `NavigationBar` usa
  `brand.withValues(alpha: 0.14)` y el avatar el mismo tono. Se mantuvieron los
  iconos de launcher generados desde la captura y el tema claro.
- **Surtido visible:** `_IngredientTile` pasó a `StatefulWidget`; `_openRestock()`
  devuelve `bool` y, al confirmar, la tarjeta se resalta en verde con
  «¡Surtido!» / «Stock actualizado» durante 3 s (`Timer` cancelado en `dispose`)
  además de un SnackBar verde de 4 s. Sigue sumando con
  `adjustIngredientStock()` y respetando offline/roles.
- **Pedidos web:** `OrderCard` usa fondo `#F0F9FF` y borde `#BAE6FD` cuando
  `source == 'web'`, conservando la insignia «Web». Se añadió
  `app/test/order_card_test.dart` (2 tests).
- **Limpieza de mensajes técnicos:** se quitó el tile/diálogo «Enviar crash de
  prueba» y la constante `ENABLE_CRASH_TEST` de `MoreScreen`; se simplificaron los
  textos de Acerca de, Configuración, Login, Apariencia y el pie del shell, y se
  eliminó el aviso de Firestore en `/menu`. `CrashReporter.initialize()` sigue
  activo en segundo plano; no se tocó el `debugShowCheckedModeBanner` ni los
  `console.*` de servidor.
- **Pedidos hoy:** se eliminó solo la ficha del rol `admin`; cajero y cocinero
  conservan la suya.
- **Checks:** `flutter analyze` ✅, `flutter test` ✅ 86 tests; web `typecheck` ✅,
  95 tests ✅ y `build` ✅; servidor `next start -p 3001` detenido antes del build,
  reiniciado después y `/api/health` 200. APK release 61,6 MB compilada con los
  dart-defines habituales, reinstalada en `a791bc16` y arrancada sin
  `FATAL EXCEPTION`. Commit y push realizados en la rama
  `feature/app-reportes-cierre-caja`; sin despliegue a Netlify.

### Instancias demo aisladas / multi-tenant (2026-11-25, Opción B)
- **Objetivo:** crear restaurantes nuevos (`fuego`, `verde`) para probar y
  mostrar el sistema **sin tocar los datos reales de Manía**. No se escribió en
  Firestore, no se cambió `.env.local` y no se modificaron reglas, índices ni
  Functions. Todo sigue sin commit/push.
- **Modelo lógico:** `tenants/{tenantId}/...`. En esta fase se materializa como
  stores demo locales por tenant; `mania` mantiene su comportamiento histórico
  (Firestore REST si hay credenciales) y los tenants nuevos **nunca** llaman a
  Firestore. Sin `?tenant=`, header, cookie ni subdominio, el tenant es `mania`.
- **Resolución de tenant:** `?tenant=` > `X-Tenant-Id` > cookie `rm_tenant_id` >
  subdominio > `mania`. En web, `src/proxy.ts` inyecta el header y la cookie,
  `src/lib/tenant-server.ts` lo lee con `headers()` async en RSC y
  `src/lib/client-tenant.ts` lo propaga en `fetch` desde cliente.
- **Web:** `src/lib/tenants.ts` (registry, normalización y `tenantStorageKey`),
  `src/lib/demo-store.ts` (estado aislado por tenant) y `tenantId` opcional en
  `menu.ts`, `orders.ts`, `cash-shifts.ts` y `restaurant-config.ts`. Persistencia
  demo por tenant en `.data/{tenantId}/orders.json` y
  `.data/{tenantId}/cash-shifts.json`; Manía conserva `.data/orders.json` y
  `.data/cash-shifts.json`. `localStorage`: Manía usa claves legacy
  (`rm_cart_v1`); demo usa `rm_{tenantId}_cart_v1`, etc. El layout inyecta
  `window.__RM_TENANT_ID__`; el cliente respeta el prefijo y añade el header.
  RSC, metadata, sitemap y `llms.txt` pasan el tenant. Seeds: `fuego` añade
  `item-fuego-parrilla`, pone `maiz-blanco=0` y `camaron=1200`; `verde` pone
  `carne-res=0`, `lechuga=40` y `item-ajiaco` unavailable.
- **APK:** `core/data/tenant.dart` (registry, `normalizeTenantId`,
  `tenantStorageKey`, `TenantPreferences`, `tenantHeader`). `load({tenantId})`
  elige el tenant (preferencia global `rm_tenant_id_v1`, sin prefijo),
  `SeedData.menuItemsFor/ingredientsFor/ordersFor` aplican los seeds por tenant
  y `TenantPreferences` prefija todas las claves `rm_*_v1` sin tocar cada
  llamada. Los 18 puntos HTTP envían `X-Tenant-Id`. `switchTenant()` cambia de
  instancia **sobre el mismo repositorio/provider**: cancela polling, quita el
  listener de conectividad, carga el otro tenant con `watchConnectivity:false`,
  persiste la preferencia, copia el estado y reactiva listener/polling. El login
  muestra un selector «INSTANCIA DE LA DEMO» con los 3 tenants.
- **Tests:** web 12 nuevos (resolución de tenant y aislamiento de menú/config,
  stock, pedidos, turnos y visitas); Flutter 10 nuevos (registry, prefijos,
  seeds y aislamiento del repositorio al cambiar de tenant). El selector se
  rediseñó con `DropdownButton(isExpanded: true)` tras un `RenderFlex overflow`
  en los widget tests.
- **Checks:** web `typecheck` ✅, **107 tests** ✅, `build` ✅ (Next 16.4.6);
  Flutter `analyze` ✅ y **96 tests** ✅. Sin commit/push ni despliegue.

### Multi-tenant real en Firestore / limpieza total (2026-11-26)
- **Petición del usuario:** borrar todos los datos de prueba (Firestore y
  Storage), dejar una estructura limpia y funcional con `mania`, `fuego` y
  `verde` en el mismo proyecto/base `(default)`, y probarlo en web y APK.
- **Respaldos antes del borrado:** export de Firestore en
  `gs://restaurante-mania-e47a0-backup-20261126/firestore` y 3 objetos de Storage
  copiados en `%TEMP%/opencode/backup-20261126/storage`. Se borraron 211
  documentos y los 3 objetos de Storage; quedó **ninguna colección raíz**.
- **Estructura nueva:** `tenants/{tenantId}/{collection}` con `restaurant/config`,
  `categories`, `menuItems`, `ingredients`, `orders`, `cashShifts`, `customers`,
  `users`, `inventoryLosses`, `webVisits` y `tables`. No hay colecciones raíz
  operativas. helper central `tenantPath()` en `web/src/lib/firebase/rest.ts`.
- **Siembra:** 230 documentos (verificación por tenant: manía 4/7/42/10/10,
  fuego 4/12/43/1/0, verde 4/10/43/1/0 para categorías/platos/insumos/turnos/
  clientes; 10 mesas y 1 usuario admin por tenant). Las URLs de logo/banner
  borradas se dejaron vacías para no dejar enlaces rotos. UID admin
  `Y72Vea5qAFcdW6AgBqBy0dSfyH92` (`castellanoseloy@gmail.com`, rol `admin`).
- **Código:** todas las lecturas/escrituras web (config, menú, pedidos, stock,
  visitas, CRM, turnos, pérdidas, grupos y apariencia) usan `tenantPath()`. El
  estado demo local queda **solo** como fallback cuando Firestore no está
  configurado (tests/desarrollo). El prefijo de pedidos sale de
  `tenantDefinition(tenantId).orderPrefix`. `verifyAdminIdToken(token, tenant)`
  resuelve el rol dentro de `tenants/{tenant}/users/{uid}`.
- **Reglas/índices:** `firebase/firestore.rules` reescrito para el prefijo
  `tenants/{tenantId}`; roles resueltos desde claim o documento de usuario del
  tenant, catálogo público, listados privados y denegación de colecciones raíz.
  Desplegado con `firebase deploy --only firestore:rules,firestore:indexes`.
  Verificación en vivo: lectura pública `tenants/mania/restaurant/config` → 200,
  ruta plana `restaurant/config` → 403.
- **Checks finales:** web `typecheck` ✅, **107 tests** ✅ y `build` ✅ (sin
  warnings de Firestore 403); Flutter `analyze` ✅ y **96 tests** ✅. En vivo en
  `:3001`: config/menú/insumos/turnos/clientes/visitas/pedidos de los 3 tenants
  responden 200 con el `tenantId` correcto; config y menú declaran
  `source=firestore` y el resto `configured=true` con los conteos sembrados
  (mania 4/7/42/10/10, fuego 4/12/43/1/0, verde 4/10/43/1/0); resolución por
  query/header/cookie/subdominio ✅; pedido QA `FUE-20261126-5ZPT` creado,
  aislado (200 en fuego, 404 en manía) y borrado. Sin commit/push salvo
  solicitud.
- **Fix SEO/GEO (2026-11-26):** Next 16 entrega `params.slug` codificado en la
  página (`ajiaco-santafere%C3%B1o`) pero decodificado en `generateMetadata`.
  Se añadió `decodedSlug()` en `web/src/app/menu/[slug]/page.tsx` y se usa en
  ambos. Antes la ficha caía en `notFound()`/`robots: noindex`; en producción
  con el build final: manía y fuego con `ajiaco-santafereño` y verde con
  `arepa-con-queso` → 200, `<h1>`, JSON-LD `MenuItem`, `robots: index, follow`.
  Tras el fix: `typecheck` ✅, 107 tests ✅, `build` ✅.
- **APK verificada en vivo:** release 61,6 MB compilada con `WEB_API_URL` y
  `FIREBASE_WEB_API_KEY`, instalada en `a791bc16` con `adb reverse tcp:3001` y
  `pm clear`. Un proxy de log confirmó el cambio `fuego → verde → manía` con
  `X-Tenant-Id` correcto en todas las peticiones; tras `am force-stop` y
  relanzamiento persistió `tenant=mania`. Sin `FATAL EXCEPTION` (solo
  `VM exiting with result code 0`). No se probaron pantallas autenticadas: no
  hay contraseña disponible y el token de `gcloud` no tiene permisos de Auth
  Admin (403); la verificación fue sobre endpoints públicos. El `exit 1` del
  shell al compilar fue por un warning de Gradle en stderr, pero se generó el
  APK y `adb install -r` devolvió `Success`.
- **Usuarios QA tenant-aware (2026-11-26):** `provision-auth-users.mjs` acepta
  `TENANT=all` y escribe en `tenants/{tenantId}/users/{uid}`. Se crearon
  `admin.qa@restaurante.com` (admin), `cajero.qa@restaurante.com` (cashier),
  `mesero.qa@restaurante.com` (waiter) y `cocina.qa@restaurante.com` (cook), con
  el mismo rol en `mania`, `fuego` y `verde`. La contraseña se entregó al usuario
  fuera del repo. Los 4 hacen `signInWithPassword` → 200; en la web,
  `GET /api/inventory-losses` responde 200 para admin/cook y 403 para
  cashier/waiter en los 3 tenants.
- **APK con login real verificado (2026-11-26):** release 61,6 MB recompilada
  con la semilla QA, reinstalada en `a791bc16`, `pm clear` y tenant **Manía**.
  Login con `admin.qa@restaurante.com` → dashboard «Administrador ·
  Administrador QA». Recorrido verificado: Inicio, Pedidos, Mesas, CRM y
  Más → Usuarios (8 cuentas; las 4 QA visibles con su rol). Sin
  `FATAL EXCEPTION`. La APK quedó en Inicio con la sesión iniciada. El rótulo
  «INSTANCIA DE LA DEMO» del login es texto heredado, **no** modo demo: con la
  API key compilada `_usesFirebase` es `true` y los accesos rápidos demo están
  ocultos.

### Diagnóstico de apuntado y sincronización de usuarios (2026-11-26, ronda 19)
- **Apuntado:** el celular usa `WEB_API_URL=http://localhost:3001` con
  `adb reverse tcp:3001` y tenant persistido **`mania`** (`X-Tenant-Id: mania`).
  La web corre en `:3001` con `next start` y resuelve `?tenant=` >
  `X-Tenant-Id` > cookie `rm_tenant_id` > subdominio > `mania`.
- **Pedido no visto en la APK:** quedó en **`verde`**
  (`VRD-20261126-26ZG`, `createdAt=2026-11-26T11:34:11.593Z`) porque la cookie
  `rm_tenant_id` de la web ganó sobre el fallback. `pullServerOrders()` pide
  pedidos con el tenant de la app (`mania`), así que no lo importa. Para probar
  en Manía: abrir `http://localhost:3001/?tenant=mania` o borrar la cookie.
- **Usuario no visto en Firebase:** `addUser()` solo escribía
  `SharedPreferences` (`rm_users_v1`). Se añadió
  `web/src/app/api/users/route.ts` (GET/POST/DELETE, `Bearer <idToken>`, solo
  rol `admin`) sobre `tenants/{tenantId}/users/{id}` y `_pushUserToServer()` en
  `repository.dart`, llamado desde alta/edición/baja con `X-Tenant-Id`. Sin
  sesión Firebase o sin conexión el cambio queda local (best-effort).
- **Verificación:** `typecheck` ✅, 113 tests web ✅ (6 nuevos para `/api/users`),
  `next build` ✅ con la ruta nueva `/api/users`; `flutter analyze` ✅ y 96
  tests ✅. Con token QA:
  GET manía 5 usuarios, POST `probe-sync-qa` → 6 y encontrado, GET verde sin
  ese usuario (aislamiento), DELETE → 5. El probe se borró. Queda recompilar e
  instalar la APK y crear un usuario desde la pantalla para confirmarlo en
  Firestore. Sin commit/push.
- **Limitación:** el alta desde la APK crea el documento de rol en Firestore,
  **no** una cuenta de Firebase Auth (la pantalla no pide contraseña); para
  entrar con esa cuenta hay que aprovisionarla con
  `provision-auth-users.mjs`.
- **Rótulos corregidos:** el login muestra «INSTANCIA CON FIREBASE» cuando hay
  API key compilada (antes decía «INSTANCIA DE LA DEMO») y la pantalla de
  usuarios indica que las cuentas se sincronizan con Firebase.
- **Verificación en vivo (2026-11-26):** APK release 61,6 MB recompilada e
  instalada en `a791bc16`, login real con `admin.qa@restaurante.com` y tenant
  Manía. Pedido web creado con `?tenant=mania` (`RM-20261126-OZH5`,
  `SnpImKWuiCpSpSa4IDRT`, $ 32.900) apareció en Pedidos como «Web». Alta desde
  la APK `sync.verificada@restaurante.com` → documento en
  `tenants/mania/users/u-1795696097599249-599`; edición de nombre a
  `CajeroSync` → reflejada en Firestore; baja → documento eliminado (5
  usuarios finales: 4 QA + `castellanoseloy@gmail.com`, creada desde el
  dispositivo). Sin `FATAL EXCEPTION`. La APK quedó en Inicio con sesión
  iniciada. El servidor `next start -p 3001` se reinició durante la sesión;
  al final quedó en escucha el pid 10624 con `/api/health` 200.

### Functions multi-tenant, insumos ausentes y cierre QA (2026-11-26)
- **Decisión del usuario:** no descontar inventario al confirmar. El descuento
  sigue ocurriendo al pasar de `pending` a un estado superior (`preparing` en la
  prueba). Se revisaron y desplegaron las Functions para que trabajen con
  `tenants/{tenantId}/...`.
- **Contrato de Functions:** `tenantId` = payload `tenantId` > claim
  `tenantId` > `mania`. El rol se resuelve en
  `tenants/{tenantId}/users/{uid}` con el claim global como fallback; las
  callables quedaron alineadas aunque no son el camino principal de web/APK.
  Triggers verificados en Firebase: `syncMenuStatusOnIngredientChange` escucha
  `tenants/{tenantId}/ingredients/{ingredientId}` y `onOrderCreated` escucha
  `tenants/{tenantId}/orders/{orderId}`. Deploy final: **6 Functions Deployed,
  0 Errors**; el primer intento sin `--debug` falló con `Cannot determine backend
  specification. Timeout after 10000` y el retry con `--debug` terminó bien.
- **Regla crítica:** un insumo de receta sin documento equivale a stock `0` y
  plato agotado en web, APK y Functions (`computeMaxServings`); nunca se ignora
  para dejar pedidos ilimitados.
- **Fix de alta de insumo:** `PATCH /api/ingredients/[id]` usaba
  `createDocument` y generaba un ID aleatorio, así que las recetas no
  encontraban el insumo. Ahora usa
  `setDocument(tenantPath(tenantId, "ingredients"), documentId, ...)` y se
  añadió `web/src/app/api/ingredients/[id]/__tests__/route.test.ts`. Se borró
  el documento espurio `adrxhCHsTiAuP6uRg46K` y se recreó `cafe` con ID
  `cafe` y stock `2000`; `mania` quedó con 43 insumos y 5 platos.
- **QA en vivo:** `pollo3` → 409 con `available: 2`; `cafe20` → 200. El pedido
  `RM-20261126-LXON` (`5hbMsg7yDxfo7AiDEGw4`) nació `pending` con
  `inventoryDeducted=false`; al pasar a `preparing` descontó pechuga
  400→200, papa 2300→2150, mantequilla 30→15 y lechuga 5.5→5.25; al
  cancelar restauró los valores exactos. Los pedidos QA de prueba se borraron.
  Inventario final de `mania`: `cafe=2000`, `pechuga-pollo=400`, `papa=2300`,
  `mantequilla=30`, `lechuga=5.5`.
- **Checks:** web `typecheck` ✅, **116 tests** ✅ y `build` ✅; Flutter
  `analyze --no-fatal-infos` ✅ y **97 tests** ✅. APK release recompilada con
  `WEB_API_URL=http://localhost:3001` y
  `FIREBASE_WEB_API_KEY=AIzaSyBycOm9eJ1KlhTXwxUcaGx2ZZwvfE5TJns`, instalada en
  `a791bc16` con `adb reverse tcp:3001`; arranque sin `FATAL EXCEPTION` (solo
  el `decryption failed` esperado de `FlutterSecureStorage` tras reinstalar).
  Servidor QA reiniciado desde `web/` con `next start -p 3001` y
  `/api/health` 200. Sin commit/push ni despliegue a Netlify.

### Estado de apertura, textos editables y dueño del descuento (2026-11-26)
- **Contrato nuevo de `restaurant/config`:** `isOpen`, `timeZone` (IANA),
  `openingDays` (`mon`…`sun`), `openTime`/`closeTime` (`HH:mm`, 24 h),
  `ctaTitle` y `ctaDescription`. Defaults: `America/Bogota`, Lun–Sáb
  11:30–20:30, `isOpen=true` y los dos textos finales actuales. `hours` se
  deriva del horario estructurado (`Lun–Sáb 11:30–20:30`, `Lun, Mié, Dom
  09:00–17:00` o `Todos los días …`). `sanitizeConfigPatch` valida zona con
  `Intl.supportedValuesOf("timeZone")`, días, rango (`closeTime >
  openTime`) y longitudes de los CTA. `seo.ts` y `/llms.txt` usan los días y
  horas estructurados, no el texto libre.
- **Portada:** `web/src/lib/opening-hours.ts` calcula el estado en SSR con la
  zona del restaurante: `Abierto: recibiendo pedidos` o `Cerrado: abre a las
  HH:mm` (si cambia de día, `abre el <día> a las HH:mm`). `isOpen=false`
  fuerza el cierre con la misma hora, sin día. La ficha sustituye a
  «Calificación 4.8 ★» y **no bloquea pedidos**. El bloque final lee
  `ctaTitle`/`ctaDescription`.
- **APK:** Configuración reemplaza el campo libre «Horario» por el botón
  «Horario · establecer zona horaria y horario de trabajo» y el diálogo
  `schedule_dialog.dart` (zona IANA editable con sugerencias, chips de días y
  un rango `HH:mm`). `RestaurantSettings` persiste/publica los cinco campos y
  reconcilia el horario desde la web. Apariencia añade los dos campos del
  bloque final; `payment_sheet.dart` ofrece solo métodos activos con sus
  etiquetas, y detalle, recibo y ventas usan `paymentLabel`.
- **Regla de inventario (supersede la nota anterior):** los pedidos creados en
  la APK (`source='app'`) descuentan **al quedar en `pending`**, una sola vez,
  y su cancelación repone. Los pedidos `source='web'` descuentan **al pasar a
  `confirmed`** y la web es la dueña: `updateOrder` ignora el
  `inventoryDeducted` del cliente cuando hay cambio de estado, y la APK envía
  el PATCH sin ese flag y lee el valor devuelto. Así no hay doble descuento ni
  se pierde el flag al sincronizar.
- **Checks:** web `typecheck` ✅, **125 tests** ✅ y `build` ✅; Flutter
  `analyze` ✅ y **101 tests** ✅. Sin commit/push ni despliegue.
- **Verificación final (2026-11-26):** APK release 61,6 MB compilada con
  `WEB_API_URL=http://localhost:3001` y la API key pública, instalada en
  `a791bc16` (con `pm clear` y `adb reverse`) y arrancada sin `FATAL EXCEPTION`.
  Servidor QA `:3001` reiniciado con el build final: `/api/health` 200,
  `/api/og` 200 `image/png`, config con timezone/horario/CTA nuevos, portada con
  ficha «Estado» (sin «Calificación») y pie con `Lun–Sáb 11:30–20:30`, y
  `/llms.txt` con el horario estructurado. Sin commit/push ni despliegue.



### Permisos Firebase producción: APK Firestore directo + Storage por tenant (2026-11-26)

- **Objetivo:** APK release y web ambas apuntan a producción `restaurante-mania-e47a0`. Decisiones del usuario: transporte APK **Firestore directo** (no API web), Storage **rutas por tenant**, guards de web API **pospuestos**, dominio web pendiente (placeholder).
- **APK transporte por defecto:** `DIRECT_FIRESTORE=true` y `FIREBASE_WEB_API_KEY` cae en la clave pública de producción `AIzaSyBycOm9eJ1KlhTXwxUcaGx2ZZwvfE5TJns` (web app `1:815344581484:web:d29a716690981d3f375149`) en builds `kReleaseMode` si no se pasa `--dart-define`; en debug/tests vacía → modo demo. Se eliminó la IP LAN `http://192.168.101.7:3000` de `defaultServerUrl`; ahora `WEB_API_URL` vacío por defecto (solo transporte web/QA). `FIREBASE_PROJECT_ID` default `restaurante-mania-e47a0`; bucket default `restaurante-mania-e47a0.firebasestorage.app`. Firebase Crashlytics usa `google-services.json` (Android app `com.example.app`, proyecto correcto) best-effort.
- **P0 updateMask (no pérdida de datos):** `FirestoreTransport` envía `updateMask.fieldPaths` **repetido** por cada campo del body en todo `PATCH` (query string construido por `FirestoreTransport.buildQueryString`); Firestore REST sin máscara **reemplaza** el documento. Antes `_Route.patch(..., masks)` estaba sin usar y un `Map` no puede repetir la key. `_Route.create` con id también es `PATCH` y manda máscara con todos los campos. Se añade `GET /api/users/{id}` (directo `_Route.get('users', uid, 'user')`).
- **401 vs 403:** solo **401** marca sesión vencida (`ApiAuthException` + `_markNeedsFirebaseReLogin`); **403** es falta de permiso y no dispara re-login. Afecta `WebApiTransport`, `FirestoreTransport`, `_pushUserToServer`, `_pushOrderUpdateToServer`, `_flushInventoryLosses` y `_flushPendingRestaurantConfig`. Se corrigen comentarios que decían 401/403.
- **Rol del usuario:** `loginWithFirebase` **no exige** usuario local con el mismo correo; tras `accounts:signInWithPassword` resuelve rol desde `tenants/{tenantId}/users/{uid}` con el idToken (regla `request.auth.uid == userId`) vía `AuthService.currentUid()` (JWT `sub`/`user_id`). Fallback local por email (offline/tests). Rol desconocido/ausente → `null` (NUNCA `UserRole.fromName`, que por defecto es **admin**); `pullServerUsers` salta roles inválidos. Cuenta sin rol en la instancia → `ArgumentError` claro + `logout`. **`pullServerUsers()` solo admin** (`_currentUser.role == admin`); no se llama incondicionalmente en `_onConnectivityChanged`/`refreshAll`; un 403 devuelve 0. Producción `tenants/mania/users` (6; incl. `castellanoseloy@gmail.com` admin, `admin.qa@` admin, `cajero.qa@` cashier, `mesero.qa@` waiter, `cocina.qa@` cook); colección raíz `users` vacía. No se usan custom claims (service account **sin** `firebaseauth.admin`).
- **Pedido offline avanzado:** `_runSync` crea la orden en **`pending`** + `paymentStatus: pending` (regla `isValidOrder` exige nacer pending) y luego `_pushOrderUpdateToServer` con estado real, `paymentStatus`, `paidAt/paidBy/paidByName`, `payments`, `inventoryDeducted`, `updatedAt` (regla `preservesIdentity` no toca code/customerName/createdAt). `acknowledged` solo si create OK. `_pushOrderUpdateToServer` envía `payments`/`updatedAt` en modo directo.
- **Límites `isValidOrder`** replicados en `createOrder`/`editOrder` (ArgumentError antes de tocar local): `customerName` ≤ 80, `customerPhone` ≤ 20, `notes` ≤ 300, `deliveryAddress` ≤ 160, `items` ≤ 50; nombre ≥2/teléfono ≥7 salvo mesa; dirección entrega ≥5. `total == subtotal + tax`; `paymentMethod` en [cash,card,nequi,daviplata]; `tableNumber` 1..200 (actualizado el 2026-11-28).
- **Storage rutas por tenant:** APK sube a `tenants/{tenantId}/appearance/...` (banner/logo) y `tenants/{tenantId}/inventory-losses/...`; antes `appearance/...` / `inventory-losses/...`. `firebase/storage.rules` reescrito: `tenants/{tenantId}/appearance` admin-del-tenant; `tenants/{tenantId}/inventory-losses` admin o cook del tenant; rol = claim `role` o `firestore.get(tenants/{tenantId}/users/{uid}).role` (**ya no usa `users/{uid}` raíz**, vacía); lectura pública; se conservan rutas antiguas + catch-all `isAdminLegacy`; `isAllowedImage` 6 MB `image/(jpeg|png|webp|gif)`. Rutas antiguas `appearance`/`inventory-losses` mantienen escritura admin. **IAM verificado**: service agent `service-815344581484@gcp-sa-firebasestorage.iam.gserviceaccount.com` con `roles/firebaserules.firestoreServiceAgent`; `service-815344581484@firebase-rules...` `roles/firebaserules.system`; service account web `firebase-web-admin@...` `storage.admin`. Sin custom claims.
- **Permisos Firestore sin cambios:** `firebase/firestore.rules` ya cubría lo que necesita la APK directa; compila y **desplegado** a producción. `tenants/{tenantId}/users/{uid}` read self/admin, write admin; `orders` list staff, create `isValidOrder`, update `isStaff && preservesIdentity`; `menuItems`/`ingredients`/`categories` write admin; `restaurant` write admin; `customers` staff con keys hasOnly; `inventoryLosses` staff; `cashShifts` admin/cashier keys hasOnly; catch-all deny. Claim `role` fallback + Firestore. Service account de web sigue **sin** `firebaserules.releases.list` y **sin** Auth Admin; web API privada sin guards (decisión “Después”).
- **Reglas desplegadas:** `firebase deploy --only "firestore:rules,storage" --project restaurante-mania-e47a0` → compila + released. PowerShell: `--only "firestore:rules,storage"` con comillas (la coma crea array sin ellas).
- **Diagnóstico APK:** Configuración → “Conexión · diagnóstico” muestra proyecto, transporte (`firestore`/`web`), instancia, sesión+rol, clave pública. Getters `firebaseProjectId`, `apiTransportName`, `hasFirebaseApiKey`, `currentRole`, `useDirectFirestore`. `FirestoreTransport /api/health` responde `{mode,tenantId,projectId}` sin token; token solo si `authorized`.
- **Verificación:** `flutter analyze` limpio; **108/108** tests Flutter; reglas Firebase compilan; APK release rebuild OK; en `lib/arm64-v8a/libapp.so` `192.168.101.7` **ausente**, `localhost:3001` ausente, `restaurante-mania-e47a0` + clave web + `firebasestorage.app` + `tenants/` presentes; `DIRECT_FIRESTORE` no aparece (resuelto en compilación). Test `FirestoreTransport.buildQueryString repite updateMask.fieldPaths`. `pullServerUsers` test ajustado a admin + serverUrl. Web sin cambios de código; guards pospuestos. `NEXT_PUBLIC_SITE_URL` placeholder `http://localhost:3001` pendiente de dominio. Emisores IAM no se modifican; rules/storage service agent ya tenían roles.
- **Docs:** README “Login real en la APK” + “APK en producción: Firestore directo + Storage por tenant”, autorización/Storage actualizada; `docs/CRASHLYTICS-SETUP` sigue mostrando `WEB_API_URL=localhost:3001` + key opcional (no obligatorio en release).

### Puesta en producción y cierre final (2026-11-26)
- **Firebase real desplegado:** `restaurante-mania-e47a0`, base `(default)`, tenant `mania`. Comando final `firebase deploy --only "functions,storage,firestore:rules,firestore:indexes" --project restaurante-mania-e47a0`: reglas y Storage releaseados, índices publicados y 6 Functions activas (sin cambios de código). En PowerShell `--only` debe ir entre comillas: sin ellas solo se despliega el primer target. El primer intento agotó el timeout de descubrimiento del CLI (10 s) porque en frío `lib/index.js` tardó 46 s en cargar en Windows; con caché caliente tarda 1,5 s y el deploy terminó OK.
- **Catálogo real en la APK:** además del estado, ahora se descargan el menú completo y las categorías (`pullServerMenuCatalog()` y `pullServerCategories()` desde `/api/menu` y `/api/menu/categories`). `FirestoreTransport` mapea ambas rutas a las colecciones `menuItems`/`categories`; los toggles pendientes offline se conservan al reemplazar el catálogo. Antes solo se sincronizaba `available/unavailable` y los platos seguían siendo semilla local; el dispositivo mostraba 13 platos y ahora muestra **7 platos reales**.
- **APK de producción verificada:** release de 61,6 MB compilada con `DIRECT_FIRESTORE=true`, `FIREBASE_WEB_API_KEY=AIzaSyBycOm9eJ1KlhTXwxUcaGx2ZZwvfE5TJns` y `FIREBASE_PROJECT_ID=restaurante-mania-e47a0`, instalada en `a791bc16`. Sesión real `castellanoseloy@gmail.com` (admin) «En línea»: 43 insumos, 7 platos, 7 cuentas, pedidos web (`RM-20261126-OZH5`, `RM-20261126-RKCZ`), clientes, turnos y configuración desde Firestore. El pedido QA local `RM-20261126-8816` no existe en Firestore ni aparece en la APK (búsqueda → 0).
- **Conteos reales en `tenants/mania`:** users 6 (7 tras la fusión local), orders 5, ingredients 43, menuItems 7, categories 4, cashShifts 10, webVisits 1, customers 10, tables 10.
- **Checks finales:** web `typecheck` ✅, **125 tests** ✅ y `build` ✅; Flutter `analyze` ✅ (**No issues found**) y **108 tests** ✅. `firebase functions:list` confirma 6 functions activas.
- **Netlify:** fuera de alcance por decisión del usuario (sin login/dominio real). Se deja todo listo para publicar; `NEXT_PUBLIC_SITE_URL=http://localhost:3001` sigue pendiente del dominio definitivo.
- **Git:** commit convencional y push a `origin/feature/app-reportes-cierre-caja` con todo el cambio acumulado de la rama.

## 2026-11-27 - all_user global y login sin dropdown de tenant
- **all_user (raíz Firestore):** colección raíz `all_user/{email}` (email normalizado, URL-encoded en path) con `{ email, name, memberships: [{tenantId, role, uid, name, email}], updatedAt }`. Se sincroniza en alta/edición/baja de usuarios desde APK (`_syncAllUserEntry` en `app/lib/core/data/repository.dart`) y desde web API (`web/src/app/api/users/route.ts` POST/DELETE, incluyendo cambio de email).
- **Login APK:** se elimina dropdown de tenant en `app/lib/features/auth/login_screen.dart`. `loginWithFirebase(email,password,{tenantId?})` autentica, consulta `all_user/{email}`; si hay 1 tenant cambia automáticamente, si hay >1 lanza `TenantSelectionRequiredException` y la UI muestra `AlertDialog` con dropdown para elegir instancia; si 0 memberships, fallback al comportamiento anterior por tenant actual.
- **FirestoreTransport:** soporta rutas root `/api/all-users/{id}` (GET/PATCH/DELETE) mapeadas a colección raíz `all_user` con `root=true` (`app/lib/core/data/api_transport.dart`).
- **Pendiente:** poblar/respaldar `all_user` para usuarios existentes; reglas Firestore siguen abiertas temporalmente (revertir antes de prod real).

## 2026-11-27 - all_user: deviceId y fix de cambio de tenant
- **Device id para push:** `all_user/{email}` ahora incluye `deviceId` (último dispositivo) y `deviceIds` (historial, sin duplicados). El id es estable por dispositivo, se genera en `RestaurantRepository.load` y se guarda en SharedPreferences global `rm_device_id_v1` (fuera del prefijo de tenant). Se registra en cada login y al restaurar sesión en `main.dart` (`registerDeviceId()`). El backfill `firebase/scripts/backfill-all-users.mjs` preserva ambos campos; la web API y la APK usan PATCH con updateMask, así que no los borran.
- **Fix cambio de tenant:** `switchTenant` creaba un repositorio con el transporte Firestore del nuevo tenant pero `_copyTenantStateFrom` no lo copiaba (`_api` era `late final`), por lo que las lecturas seguían yendo al tenant anterior. `_api` pasa a ser mutable y se copia; `firebaseProjectId` usa una variable local para el type-promotion.
- **Verificación en dispositivo `a791bc16`:** APK release reinstalada. Login con `qa-alluser@restaurante.com` (memberships `fuego(cashier)` + `mania(admin)`) → AlertDialog, al elegir `fuego` entra como `Cajero` y muestra pedido `FUE-20261126-M90W` (tenant correcto). Login con `qa-single@restaurante.com` (solo `fuego`) entra directo como `Cajero` sin diálogo (antes fallaba con «rol no asignado en fuego»). `all_user` de ambos con `deviceId=deviceIds[0]=dev-hojsdfa90j-au19yv`.
- **Reglas:** `firebase/firestore.rules` tiene regla explícita `match /all_user/{email} { allow read, write: if true; }` desplegada; el wildcard temporal sigue abierto para el resto. El backfill inicial creó 8 documentos `all_user` desde 18 usuarios en 3 tenants (luego 10 con los QA de prueba).
- **Cuentas QA creadas para la prueba:** `qa-alluser@restaurante.com` / `QaAllUser2026!` (2 tenants) y `qa-single@restaurante.com` / `QaSingle2026!` (solo fuego).
- **Estado tests:** Flutter 108 pasan, 3 fallos preexistentes en `appearance_screen_test.dart` (2) e `inventory_screen_test.dart` (1) por cambios previos de UI (no relacionados con este cambio). `flutter analyze` con 5 avisos preexistentes; web `tsc --noEmit` OK.

## 2026-11-27 - Pedidos, Inicio, mesas y barra superior
- **Pedidos:** orden predeterminado más viejo → más nuevo (`createdAt` ascendente) con etiqueta visible «Orden: más viejo → más nuevo». `OrdersScreen` acepta `initialFilter` y reacciona en `didUpdateWidget`.
- **Inicio → Pedidos:** callback opcional `DashboardScreen.onOpenOrders(String filter)` (no cambia la firma de `onNavigate`). Mapeo: Por cobrar→`toCollect`, En preparación→`preparing`, Pedidos listos/Listos→`ready`, Pendientes→`pending`, Pedidos hoy→`all`. `AppShell` guarda `_ordersFilter` y lo resetea al usar la barra inferior.
- **Cantidad de mesas:** `RestaurantSettings.tableCount` (0..200, default 0) persistido en `toJson`/`fromJson` y publicado a la web en `toWebConfigPatch()`/`fromWebConfig()`; el registro inicial también lo envía. Nuevo campo en Más → Configuración. `RestaurantRepository._applyTableCount()` crea mesas 1..N conservando existentes por número y solo elimina sobrantes libres; se llama en `load`, `updateSettings` y `pullServerRestaurantConfig`. `0` = no gestionar (no borra mesas demo).
- **Barra superior:** tercera línea «Operando: {nombre}» junto al menú activo y el rol/usuario (se quitó el tenantId).
- **Login:** recuerda el último correo en `rm_last_email_v1`; usa el logo `app/assets/images/login-logo.png` en vez del emoji; botón «Crear restaurante» debajo de «Recuperar contraseña».
- **Verificado en `a791bc16`:** APK release reinstalada; tarjetas «Pedidos por cobrar»/«En preparación»/«Pedidos listos» abren Pedidos con el chip correcto (confirmado vía `selected="true"` en uiautomator); campo «Cantidad de mesas» guardado en 6 creó Mesas 1..6 (0/6 ocupadas). `flutter analyze` sin issues nuevos; 105 tests pasan, 3 fallos preexistentes.

## 2026-11-27 - Registro de restaurantes y tenants dinámicos
- **Alta desde la APK:** `CreateRestaurantScreen` pide correo, contraseña, nombre del restaurante, zona horaria, apertura/cierre, cantidad de mesas, código de país y teléfono. `createRestaurant(...)` intenta `signIn` con Firebase Auth; si falla con `EMAIL_NOT_FOUND`/`INVALID_LOGIN_CREDENTIALS`/`INVALID_PASSWORD` intenta `signUp` (`AuthService.signUp` usa `/v1/accounts:signUp`); si `signUp` responde `EMAIL_EXISTS`, exige la contraseña actual de esa cuenta. No se crea una instancia vacía si el tenant ya está ocupado.
- **Tenants dinámicos:** `tenant.dart` mantiene `tenants` mutable con `registerTenant`, `isValidTenantId` y `tenantIdFromName` (slug del nombre + sufijo `-2`, `-3`… si está ocupado). `FirestoreTransport` añade rutas root `/api/tenants` y `/api/tenants/{id}`. `RestaurantRepository._loadTenantRegistry(auth)` descubre tenants desde Firestore; `createRestaurant` escribe `tenants/{id}`, `tenants/{id}/restaurant/config`, `tenants/{id}/users/{uid}` y el membership en `all_user/{email}`, cambia el tenant y aplica config/mesas.
- **Web multi-tenant:** `normalizeTenantId` acepta cualquier ID `^[a-z0-9][a-z0-9_-]{0,63}$` (antes solo `mania/fuego/verde`); `tenantFromHost` solo acepta subdominios reales (un dominio raíz no es tenant). `restaurant-config.ts` registra la definición del tenant desde su config de Firestore, así que la web pública sirve cualquier instancia nueva.
- **Orden de pedidos:** `OrdersScreen` tiene combobox con `Más viejo a más nuevo` (default), `Más nuevo a más viejo`, `Mayor total primero` y `Menor total primero`. La lista se ordena antes de agrupar por mesa: el orden de los grupos sigue la primera aparición en la lista ordenada. Nuevo test `app/test/orders_sort_test.dart` verifica que al elegir «Mayor total primero» cambia el orden de las tarjetas.
- **Acceso a «Taquitos mexicanos»:** el documento `tenants/taquitos-mexicanos/restaurant/config` existe con `name=Taquitos mexicanos`, `phone=3212308383`, `timeZone=America/Bogota`. El puerto 3001 servía un build anterior de `next start`: borraba la cookie del tenant. Se detuvo, se ejecutó `npm run build` y se reinició con `npm run start -- -p 3001`. Verificado HTTP 200 con `?tenant=taquitos-mexicanos`, header `X-Tenant-Id`, cookie `rm_tenant_id` y subdominio `taquitos-mexicanos.localhost`; el HTML contiene «Taquitos mexicanos» y no «Latin Sushi». Sin parámetros sigue siendo `mania`. Web `npm test`: 127 tests pasan.
- **Pendiente de producción:** reglas Firestore/Storage temporales abiertas (`allow read, write: if true`, wildcard) deben revertirse antes de producción final; `NEXT_PUBLIC_SITE_URL` sigue pendiente del dominio real. Cambios aún sin commit.

## 2026-11-27 - Plantilla genérica, fix de documentos parciales y verificación final
- **Plantilla genérica aprobada:** «Español (genérico Latino)», platillos nuevos, slogans/hero/CTA y textos IA generales; sin ciudad/país/platos típicos. Web: `web/src/lib/generic-template.ts` + `restaurant-config.ts`/`menu.ts`/`demo-store.ts`/`tenants.ts`; APK: `SeedData.generic*`, `RestaurantAppearance.generic` y `seed_data.dart`. IDs compartidos: categoría `cat-generales`, platos `item-plato-del-dia` y `item-ensalada-fresca`, 4 insumos, preset `tierra`, contactos placeholder `+00`/`USD`.
- **Regla de tenant dinámico:** un tenant nuevo sin configuración usa la plantilla; si ya tiene `tenants/{id}/restaurant/config` con nombre propio (caso histórico `taquitos-mexicanos`) conserva su catálogo. En la APK el probe se hace en `RestaurantRepository.load` con `GET /api/restaurant/config` sin autorización (`useHistoricalSeed`/`useGenericSeed`); en la web lo decide `snapshot.configured` en `menu.ts`.
- **Bug corregido:** la APK publicaba estados/favoritos de platos sembrados localmente aunque no existieran en Firestore, creando documentos parciales (`solo status/statusUpdatedAt/manualStatus/statusReason`) en `tenants/taquitos-mexicanos/menuItems`. Ahora `_serverMenuCatalogLoaded`/`_serverMenuCatalogIds` (poblados por `pullServerMenuCatalog`) bloquean `_flushPendingMenuStatuses` y `_flushPendingFeaturedItems`; el guard viaja en `_copyTenantStateFrom` para sobrevivir a `switchTenant`. Tests de regresión en `app/test/generic_template_test.dart` y `web/src/lib/__tests__/generic-template.test.ts`.
- **Limpieza en producción:** se detuvo la APK, se borraron `item-plato-del-dia` e `item-ensalada-fresca` de `tenants/taquitos-mexicanos/menuItems` y se verificó `MENU_ITEMS_DOCS=0`; después de reinstalar y usar la app sigue en 0 (no se recraron).
- **Verificación web (`:3001`):** `?tenant=resturantedeejemplo` → 200, cookie `rm_tenant_id`, «Restaurante de ejemplo», «Comida lista para compartir», platos genéricos y sin «Latin Sushi»; `/` → 200 con «Latin Sushi» y sin genéricos; `?tenant=taquitos-mexicanos` → 200 con «Taquitos mexicanos». `/menu` y `/api/menu` del tenant plantilla devuelven los dos IDs genéricos. Web `typecheck`, `npm test` (20 archivos/131 tests) y `npm run build` ✅ (Next 16.4.6, `proxy.ts`; reiniciar `next start` tras cada build).
- **Verificación APK release:** compilada con `DIRECT_FIRESTORE=true`, `FIREBASE_WEB_API_KEY` pública y `FIREBASE_PROJECT_ID=restaurante-mania-e47a0` (62,2 MB, `app/build/app/outputs/flutter-apk/app-release.apk`), instalada en `a791bc16`. Tras `pm clear`, login con la cuenta QA nueva `qa-taquitos@restaurante.com` / `QaTaquitos2026!` (1 membership `taquitos-mexicanos`, admin) entra directo. Menú: 13 platos históricos con nombre/precio/categoría (p. ej. «Empanadas de carne · $ 14.500»), sin «Sin categoría · $ 0». Pedidos: filtros y «Más viejo a más nuevo». Más: Reportes, Configuración, Apariencia, Inventario, Pérdidas, Menú, Usuarios, Acerca de. Sin `FATAL EXCEPTION` en logcat.
- **Checks Flutter finales:** `flutter analyze --no-fatal-infos` → solo los 5 avisos preexistentes (4 info en `media_upload_service.dart`, 1 warning `_copyToAppDir` en `menu_admin_screen.dart`). `flutter test` → 112 pasan, 3 fallos preexistentes (`appearance_screen_test.dart` ×2, `inventory_screen_test.dart` ×1) no relacionados. Tests dirigidos de plantilla/tenant/contrato/api: 32 pasan.
- **Cuenta QA añadida:** `qa-taquitos@restaurante.com` con `all_user` y `tenants/taquitos-mexicanos/users/{uid}` para poder probar el tenant histórico tras limpiar datos. Los QA anteriores siguen vigentes.
- **Sigue pendiente:** decidir commit/push; revertir reglas abiertas y fijar `NEXT_PUBLIC_SITE_URL` real antes de producción.

## 2026-11-27 - Notificaciones push/sonoras y favoritos de la plantilla
- **Contrato push:** mensajes FCM **data-only** con `{type, tenantId, eventId, title, body, orderId?}`. Tipos: `new_order`, `order_ready`, `low_stock`, `shift_closed`. El `eventId` canónico es `<type>:<tenantId>:<id>` y se usa también para deduplicar las notificaciones locales generadas por polling. El canal Android es `rm_pos_alerts` (importancia alta, sonido del sistema; **sin WAV propio**). El sonido respeta Silencio/No molestar.
- **Destinatarios:** tokens por dispositivo en `all_user/{email}.fcmTokens: {deviceId: token}`; la APK los registra vía `/api/all-users/{email}` y los quita al cerrar sesión. Functions resuelve el rol **dentro del tenant** (`tenants/{tenantId}/users` donde `role in [...]`), exige que `all_user` tenga membership en ese mismo tenant y envía con `getMessaging().sendEach()`. Roles: pedido nuevo → admin/cajero/cocina; pedido listo → admin/cajero/mesero; stock bajo → admin/cocina; cierre de turno → admin/cajero. Tokens inválidos se limpian del mapa. Idempotencia por `tenants/{tenant}/_notificationEvents/{eventId}`.
- **Functions:** `notifyTenant()` en `firebase/functions/src/index.ts`; `onOrderCreated` envía el aviso de pedido nuevo y añaden los triggers `notifyOrderReady` (orders, `!ready → ready`), `notifyShiftClosed` (cashShifts, `!closed → closed`) y el cruce a stock bajo dentro de `syncMenuStatusOnIngredientChange` (solo `!wasLow && isLow`). Compila con `npm run build` ✅.
- **APK:** `core/services/notification_service.dart` (permiso Android 13 `POST_NOTIFICATIONS` en el manifiesto, `firebase_messaging: ^17.1.0`, `flutter_local_notifications: 22.3.3` (fijada; 23.x exige SDK 37)), preferencias globales `rm_notification_preferences_v1` con `silentAll` + switch por tipo. La pantalla nueva **Más → Notificaciones** permite silenciar todo o cada evento; las preferencias se recargan también en el isolate de segundo plano. Fallback local sonoro en `pullServerOrders()`, `pullServerIngredients()` y `pullCashShifts()` con primeo para no avisar de datos preexistentes. Al tocar una alerta, `AppShell` abre Pedidos con el filtro (`toCollect`/`ready`), Inventario o Reportes/Dashboard, cambiando de tenant si hace falta.
- **Favoritos iniciales:** `SeedData.genericMenuItems()` y `web/src/lib/generic-template.ts` marcan `featured: true` para `item-cafe-con-leche` y `item-ensalada-fresca`, así que toda restaurante creado nace con esos dos platos en el carrusel. Tests de ambos lados actualizados.
- **Verificación:** web `typecheck` ✅ y **132 tests** ✅; Functions `npm run build` ✅; `flutter analyze --no-fatal-infos` sin issues nuevos (queda el warning preexistente `_copyToAppDir`); `flutter test` **116 pasan / 3 fallos preexistentes** (`appearance_screen_test.dart` ×2, `inventory_screen_test.dart` ×1). Sin commit/push.
- **Pendiente para producción:** sustituir `NEXT_PUBLIC_SITE_URL` por el dominio real. Functions/IAM/reglas ya están desplegados y las reglas ya no son comodines (ver sección siguiente).

### Despliegue real de notificaciones y reglas endurecidas (2026-11-27)
- **Functions desplegadas:** `firebase deploy --only functions --project restaurante-mania-e47a0 --non-interactive` → `notifyOrderReady` y `notifyShiftClosed` creadas, el resto actualizadas; `gcloud functions list` las muestra ACTIVE. El primer intento falló con `Cannot determine backend specification. Timeout after 10000` porque `FIRESTORE_EMULATOR_HOST`/`FIREBASE_STORAGE_EMULATOR_HOST` seguían definidos; hay que limpiar ambas variables antes de desplegar.
- **IAM FCM:** el rol correcto es `roles/firebasecloudmessaging.admin` para `815344581484-compute@developer.gserviceaccount.com` (`roles/firebase.messagingAdmin` no existe para ese recurso y fue rechazado).
- **Reglas Firestore:** se reemplazaron los comodines abiertos (`allow read, write: if true`) por reglas tenant-aware: catálogo público, escrituras por rol del tenant, colecciones operativas solo staff, derivadas solo Admin SDK y `all_user` restringido por email/doc-id; simulación en seco compiló limpia y `firestore:rules` quedó releaseada. Limitación residual: cualquier cuenta autenticada puede modificar el `all_user` de otra si el campo `email` coincide con el ID del documento.
- **Alta de restaurante:** `createRestaurant()` ahora escribe `ownerUid` en `tenants/{tenantId}` para poder bootstrapear el primer admin bajo las reglas endurecidas.
- **Bloqueo de build resuelto:** `flutter_local_notifications 23.0.4` exige `compileSdk 37`; la instalación de Android SDK Platform 37 se quedó colgada más de una hora (directorio con solo `.installer`). Se fijó `flutter_local_notifications: 22.3.3` (compila con SDK 36, API usada compatible) y se reanudó el build release con los dart-defines de producción. El primer rebuild falló en `:app:checkReleaseAarMetadata` porque esa versión exige desugaring; se habilitó `isCoreLibraryDesugaringEnabled = true` y `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")` en `app/android/app/build.gradle.kts`.
- **Resultado final:** build release ✅ (62,8 MB / 65.870.076 bytes) e `adb install -r` ✅ en `a791bc16` con el código de push (FCM nativo, `rm_pos_alerts`, menú Más → Notificaciones). Arranque verificado: `FirebaseApp initialization successful`, Crashlytics activo, `Fully drawn`, sin `FATAL EXCEPTION`. Tras reinstalar, `FlutterSecureStorage` cae al cifrado propio (`decryption failed` esperado) y pide iniciar sesión de nuevo; el token FCM se escribe en `all_user/{email}.fcmTokens` al hacer login o al restaurar sesión.
- **Checks:** `flutter analyze --no-fatal-infos` → 7 infos preexistentes, 0 errores/warnings (ya no aparece `_copyToAppDir`). Sin commit/push.

## 2026-11-27 - Fotos por defecto, categorías visibles y fondos de Inventario/Menú
- **Fotos de plantilla:** `SeedData.genericMenuItems()` (APK) y `web/src/lib/generic-template.ts` (web) cargan como `imageUrl` las URLs HTTPS públicas de Firebase Storage `.../imagenesglobales%2FGemini_Generated_Image_u3798u3798u3798u.png?alt=media` (Ensalada fresca) y `.../imagenesglobales%2FGemini_Generated_Image_kfkrwkfkrwkfkrwk.png?alt=media` (Cafe con leche). Ambas responden HTTP 200 `image/png`. Los tenants ya creados conservan sus documentos anteriores sin foto: el cambio aplica solo a restaurantes nuevos.
- **Storage:** `firebase/storage.rules` ya no está abierto: lectura pública solo para `imagenesglobales/{fileName}` y sesión iniciada para todo lo demás. **Pendiente:** desplegar `firebase storage.rules` si la versión en producción sigue siendo la temporal.
- **Categorías visibles:** `visibleMenuCategories()` en `web/src/lib/menu.ts` (usada en demo y Firestore) y `categoriesForOrderMenu()` en `app/lib/features/orders/new_order_screen.dart` publican solo categorías con `order > 0` y al menos un plato disponible. Las 11 categorías siguen existiendo en Firestore/Administración; en la web y en `Nuevo pedido` solo aparecen Ensaladas y Bebidas. Si la categoría seleccionada deja de ser válida, el filtro vuelve a `Todo`.
- **Fondos:** se quitó `backgroundColor: Colors.transparent` de los `Scaffold` de `inventory_screen.dart` y `menu_admin_screen.dart`; ambos usan `AppTheme.canvas` (`#FAF8F5`) igual que Configuración. Verificado por captura en dispositivo: Inventario, Menú y Configuración muestrean `#FAF8F5` en el fondo.
- **Otros QA de esta ronda:** Configuración ya no muestra URL del servidor, diagnóstico ni importación de pedidos web; la APK reinstallada con dart-defines de producción muestra en `Nuevo pedido` de `quesillo` solo `Todo`, Ensaladas y Bebidas con los dos platos; `/api/menu?tenant=resturantedeejemplo` devuelve `source=demo`, 2 categorías y las 2 imágenes; el editor de platos usa `Precio *` (confirmado en código y compilado en la APK).
- **Checks:** web `npm test` ✅ (20 archivos/132 tests), `npm run typecheck` ✅, `npm run build` ✅; Flutter `dart format` aplicado, `flutter analyze --no-fatal-infos` sin issues nuevos (8 infos preexistentes) y `flutter test test/generic_template_test.dart test/widget_test.dart` → 12/12 ✅. Build release APK ✅ e instalada en `a791bc16`.
- **Incidencia de build web:** un `next build` huérfano dejó `web/.next` sin `BUILD_ID` y bloqueó rebuilds (“Another next build process is already running”). Se mataron los PIDs colgados, se borró `web/.next/lock` y se relanzó `npm run build`. `NEXT_PUBLIC_SITE_URL` sigue en `http://localhost:3001`; falta el dominio real.
- **Despliegue:** `firebase deploy --only storage --project restaurante-mania-e47a0` ✅ (reglas compiladas y releaseadas). `NEXT_PUBLIC_SITE_URL` se mantiene en `http://localhost:3001` hasta que se defina el dominio de producción. Los cambios de esta ronda se incluyen en el commit correspondiente de la rama `feature/app-reportes-cierre-caja`.

## 2026-11-27 - QA final de push en APK + web (taquitos-mexicanos)
- **Token FCM corregido:** en `firebase_messaging 17` `register()`/`onRegistered` entregan el **FID**, no el token apto para `sendEach()`. `notification_service.dart` usa `getToken()`/`onTokenRefresh` (con `ignore: deprecated_member_use`) y `deleteToken()` al cerrar sesión. Tras reinstalar la APK y entrar con `qa-taquitos@restaurante.com`, `all_user/qa-taquitos%40restaurante.com.fcmTokens` contiene un token real (`dl8PCnX0R0…`). Build release ✅ (62,8 MB) e `adb install -r` ✅ en `a791bc16`.
- **Cuatro eventos verificados en primer plano:** `new_order` desde `POST /api/orders?tenant=taquitos-mexicanos` (pedido `TAQ-20261127-ALM9`, notificación «Pedido nuevo …»), `order_ready` al pasar ese pedido a `ready` desde Firestore, `low_stock` al cruzar `masa-maiz` a `stock=3`/`minStock=5`, y `shift_closed` al crear `cashShifts/qa-shift-1` en `closed`. Los cuatro marcaron su documento en `_notificationEvents` y aparecieron en `dumpsys notification` con canal `rm_pos_alerts`, sonido `content://settings/system/notification_sound` e importancia 4.
- **Preferencias verificadas:** «Silenciar todas» ON → el evento se marcó como enviado pero **no** se publicó notificación (5 → 5); OFF y switch «Nuevo pedido» OFF → tampoco (7 → 7 tras 25 s); al reactivar el switch, la notificación volvió a aparecer. El mute respeta el isolate de segundo plano porque las preferencias se releen al iniciarlo.
- **Estados de la app:** primer plano ✅; segundo plano (HOME con launcher activo) ✅; proceso matado con `am kill` ✅ (notificación visible con la app cerrada). Con `am force-stop` (acción de desarrollador, no de usuario) Android/MIUI retiene el mensaje y lo entrega al relanzar: `FLTFireMsgService` se inició y se publicó la alerta, pero el sistema la descartó por el ruido acumulado de las pruebas; en uso normal no aplica.
- **Navegación al tocar:** al pulsar la alerta se abrió **Pedidos** del tenant `taquitos-mexicanos` con el filtro «Por cobrar» y el pedido correspondiente.
- **Web:** servidor `next dev -p 3001` en `mode=firestore`. `/api/orders?tenant=taquitos-mexicanos` devuelve los 9 pedidos QA creados desde la web y el menú sigue en `source=demo` con 12 platos. `/api/menu?tenant=resturantedeejemplo` devuelve `featured: true` para `item-cafe-con-leche` y `item-ensalada-fresca` ✅ (el build anterior servía `false`).
- **Limpieza QA:** se borraron el plato ficticio `qa-low-stock-item` y el turno `qa-shift-1`; `masa-maiz` volvió a `stock=5000`/`minStock=0`. Se conservan los 43 insumos sembrados en `taquitos-mexicanos` para que la web pueda seguir creando pedidos, y los pedidos QA como evidencia de las pruebas. Sin commit/push.

## 2026-11-28 - Alertas avanzadas, mesas configuradas y zona horaria del dispositivo
- **Push (Functions ✅ 8 functions desplegadas):** el emisor ya no recibe su propia alerta; la exclusión compara `updatedBy`/`lastChangedBy`/`closedBy`/`createdBy` con `doc.id`, `data.uid` y el email del usuario del tenant. `out_of_stock` es un evento independiente de `low_stock` y nunca se envían por el mismo cambio. Roles: `new_order` → admin/cajero/cocina; `order_ready` → admin/cajero/mesero; `low_stock`/`out_of_stock` → admin/cocina; `shift_closed` → admin/cajero.
- **Push (APK):** canales por tipo e importancia (`rm_pos_alerts_<tipo>_<importancia>`, p. ej. `rm_pos_alerts_out_of_stock_high`); el canal heredado `rm_pos_alerts` se borra al iniciar. Tonos `classic`/`chime`/`double`/`soft` e importancia `high`/`default`/`low` configurables en Más → Notificaciones. MIUI/HyperOS restaura el sonido del canal, así que el audio lo reproduce el plugin nativo `notification_sound`; `dumpsys` muestra `mSound=null` pero el tono suena. Cambiar importance elimina y recrea el canal.
- **Alta y plantillas:** el formulario de crear restaurante ofrece más zonas IANA y todos los indicativos (`defaultCountryDial = +57`); la plantilla de café quedó con `stock=40`/`minStock=20` en `seed_data.dart` y `web/src/lib/generic-template.ts`.
- **Tope de mesas:** `RestaurantSettings.tableCount` (0..200) ahora se respeta al crear/editar pedidos en la APK (`createOrder`/`updateOrder` validan 1..`tableCount`; el checkout genera chips solo hasta `tableCount`) y en la web (`restaurant-config.ts` publica/normaliza/valida `tableCount`; `OrderPolicy.tableCount` alimenta `validateOrderInput`; `CheckoutForm` filtra «En mesa» y limita el input). Se unificó el techo 200 en `firestore.rules`, `functions/src/domain.ts` (`MAX_TABLE_NUMBER`) y `orders.ts` (`MAX_TABLE_COUNT`). `0` = sin mesas para pedidos; `_applyTableCount()` conserva su comportamiento histórico de no borrar mesas demo.
- **Modalidades predeterminadas:** APK abre «Nuevo pedido» con **En mesa** cuando hay mesas configuradas (si no, cae a la primera modalidad disponible); web abre el checkout con **Domicilio**, o con la primera opción habilitada si el restaurante desactivó domicilio. Las opciones desactivadas (`deliveryOptions`) se ocultan en ambos frentes.
- **Zona horaria:** nueva dependencia `flutter_timezone` y `core/services/device_time_zone.dart` (cachea el identificador IANA nativo y valida con `RestaurantSettings.isValidTimeZone`, con fallback `America/Bogota`). El alta de restaurante y el diálogo de horario muestran la zona del celular como texto de solo lectura; ya no hay selector manual. La hora de horarios se sigue calculando con ese identificador.
- **Verificación:** `npm run typecheck` ✅, web `npm test` ✅ (133), `functions npm run build` ✅, `dart analyze` sin errores (7 infos preexistentes), `flutter test` 116 pasan y los mismos 3 fallos preexistentes (`appearance_screen_test` ×2, `inventory_screen_test` ×1). `firestore.rules` y las 8 Functions desplegados ✅ (tope 200). En Windows el CLI no pudo hacer http discovery (escucha en IPv6 pero consulta `127.0.0.1`); se generó un `functions.yaml` temporal desde `/__/functions.yaml`, se desplegó y se borró. El código de esta ronda quedó incluido en el commit local `c4c28c0` realizado por el usuario; este apunte de MEMORY quedó sin commitear y no se hizo push.

## 2026-11-28 - URLs amigables `/menu...` y portada neutral
- **Esquema público definitivo:** `/` es una portada neutra con el logo de la APK (`web/public/rm-logo.png`), «Bienvenido a Restaurante Manía», «Elige un restaurante para empezar», selector de restaurantes y publicidad de **Software Manía** con WhatsApp `+57 312 586 6072` (`https://wa.me/5731258666072`). Manía usa `/menu` y `/menu/menu`; cualquier otro tenant usa `/menu/restaurante-<id>` y `/menu/restaurante-<id>/menu`. El slug visible conserva el ID real de Firestore (`taquitos-mexicanos` → `/menu/restaurante-taquitos-mexicanos`). No existe `restaurante-mania`.
- **Implementación:** `web/src/proxy.ts` (Proxy de Next 16, no middleware) resuelve el tenant desde la ruta, reescribe `/menu...` a `/inicio`, `/menu`, `/menu/[slug]`, etc. e inyecta `x-tenant-id`; `/?tenant=<id>` y `/menu?tenant=<id>` redirigen 307 a la ruta amigable y quitan el query. `/inicio` es ruta interna: si se pide directo, redirige a `/menu`. `/api/...`, la APK y el header `X-Tenant-Id` no cambiaron.
- **Resolución y enlaces:** `web/src/lib/tenants.ts` añade `MENU_BASE_PATH`, `TENANT_SLUG_PREFIX`, `tenantFromPath()`, `tenantSlug()` y `withTenant()`. Prioridad: ruta > query `?tenant=` > header > cookie > subdominio > `mania`. `client-tenant.ts` prioriza la ruta en el navegador; `Header` recibe el tenant del servidor para que el enlace «Inicio» SSR ya apunte a la portada del mismo restaurante. `Footer`, `MenuBrowser` y `MenuItemCard` prefijan sus enlaces. El selector vive en `RestaurantPicker.tsx` y `tenant-directory.ts` mezcla tenants fijos con `tenants/{id}` públicos de Firestore.
- **SEO/GEO:** `layout.tsx` distingue portada neutra (`x-rm-landing`) de páginas de tenant y usa canonical/metadata por ruta; `seo.ts` genera JSON-LD y URLs tenant-aware; `sitemap.ts` incluye `/`, la portada y el menú de cada tenant del directorio y las fichas del tenant activo; `robots.ts` permite `/menu` y `llms.txt` incluye las URL amigables y el WhatsApp de Software Manía.
- **Verificación local:** `npm run typecheck` ✅, `npm test` ✅ (20 archivos / 136 tests), `npm run build` ✅ (Next.js 16.4.6, Turbopack). Con `next start -p 3001`: `/` 200 con selector/aviso, `/menu`, `/menu/menu`, `/menu/restaurante-taquitos-mexicanos` y su `/menu` → 200; `/?tenant=taquitos-mexicanos` y `/menu?tenant=taquitos-mexicanos` → 307 a `/menu/restaurante-taquitos-mexicanos`; `/inicio` → 307 a `/menu`; `/api/menu?tenant=taquitos-mexicanos`, `/sitemap.xml`, `/robots.txt` y `/llms.txt` → 200. El HTML de la portada incluye «Taquitos mexicanos» y el WhatsApp; las fichas y el menú del tenant usan enlaces prefijados. Nota: tras cada `next build` hay que reiniciar `next start`; una instancia antigua en `:3001` dio falsos 404.
- **Rama:** `feature/web-rutas-amigables` (creada desde `feature/app-reportes-cierre-caja`). Commit `18deab9` pusheado; este apunte y los cambios previos de MEMORY se incluyen.
- **Corrección posterior:** los enlaces de favoritos y categorías en `web/src/app/inicio/page.tsx` y el detalle de pedido en `AccountView.tsx` ahora usan `withTenant(..., tenantId)`; antes caían en el tenant Manía. El selector de `RestaurantPicker.tsx` y el enlace «Ir directo a Restaurante Manía» usan `<a>` (navegación completa) en vez de `<Link>`: los layouts no se vuelven a renderizar en transiciones cliente y, al venir de la portada neutra, no se montaba `CartProvider`, lo que mostraba «Algo salió mal».
- **Verificación de la corrección:** `npm run typecheck` ✅, `npm test` ✅ (20 archivos / 136 tests) y `npm run build` ✅. Tras reiniciar `next start -p 3001`, `/menu/restaurante-fuego` renderiza fichas de plato `/menu/restaurante-fuego/menu/<slug>` (HTTP 200) y categorías `/menu/restaurante-fuego/menu#<slug>`; `/` renderiza los enlaces del selector como `<a href="/menu/restaurante-<id>">` y «Ir directo…» como `<a href="/menu">`.
