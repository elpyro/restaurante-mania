# ROADMAP.md — Plan y Estado de Entrega

Leyenda: `[x]` implementado y verificado · `[~]` implementado, pendiente de
credenciales o de un entorno externo · `[ ]` pendiente para producción.

## Fase 1: Firebase y Modelo de Datos

Objetivo: esquema base, reglas de seguridad, índices y estructura del monorepo.

- [x] Estructura de carpetas del monorepo: `/docs`, `/web`, `/app`, `/firebase`
- [x] Modelo de datos de `users`, `restaurant`, `categories`, `menuItems`,
      `orders`, `tables`, `stats`, `reports`
- [x] `firebase/firestore.rules` con helpers de rol, contrato de pedido,
      protección de identidad y denegación por defecto
- [x] `firebase/firestore.indexes.json` con índices compuestos para las
      consultas del producto
- [x] `firebase/firebase.json` con emuladores y predeploy de Functions
- [x] `firebase/.firebaserc.example` para no versionar el project id
- [x] Cloud Functions v2 en TypeScript, stateless, con dominio puro separado
- [~] Crear proyecto Firebase real y desplegar (requiere credenciales)
- [x] Persistencia offline en la app (`SharedPreferences` + cola de sync)
- [~] Persistencia offline en la web (Firestore REST sin caché local; el
      catálogo se sirve con ISR y semilla)
- [x] Pruebas de la cola offline: simular pérdida y recuperación de conexión
- [x] Checkpoint: modelo estable, reglas e índices válidos, Functions compilan

## Fase 2: Web Next.js — SEO/GEO y Pedidos

Objetivo: web pública optimizada y flujo de pedido completo.

- [x] Next.js con App Router y TypeScript estricto
- [x] Tailwind CSS y sistema visual (paleta cálida, tipografía, componentes)
- [x] `sitemap.xml` dinámico
- [x] `robots.txt`
- [x] JSON-LD `Restaurant`, `Menu`, `MenuItem`, `BreadcrumbList`, `WebSite`
- [x] `llms.txt` con metadatos para agentes de IA
- [x] Páginas: Home, Menú, Ficha de plato, Carrito, Checkout, Confirmación
- [x] Validación server-side del pedido y recálculo de precios
- [x] Creación del pedido en Firestore (REST) con fallback demo
- [x] Enlace `wa.me` en la confirmación
- [x] `/api/menu`, `/api/orders`, `/api/orders/[id]`, `/api/health`
- [x] `npm test` (21 tests) y `npm run build` (24 rutas)
- [ ] Verificar el pedido llegando a la app admin en tiempo real
      (requiere Firestore + app apuntando al mismo proyecto)
- [ ] Publicar en Netlify con dominio real
- [x] Checkpoint: web compilada, rutas y APIs funcionando en modo demo

## Fase 3: App Flutter con Roles y Offline

Objetivo: POS administrativo por roles con persistencia y sincronización.

- [x] Proyecto Flutter con `provider`, `shared_preferences`, `connectivity_plus`
- [x] Login con acceso rápido demo para los cuatro roles
- [x] Navegación por rol (pestañas visibles según permisos)
- [x] Dashboard Administrador (ventas, ticket promedio, top productos, mesas)
- [x] Dashboard Cajero (cuentas por cobrar, cobros del día)
- [x] Dashboard Mesero (mesas y pedidos activos)
- [x] Dashboard Cocinero (cola de cocina y tiempos)
- [x] Gestión de pedidos: listado, detalle, cambios de estado, nuevo pedido
- [x] Gestión de mesas: mapa, estados, hoja de acciones, liberar mesa
- [x] Administración de menú: disponibilidad y precios (admin)
- [x] Reportes y ajustes (admin/cajero)
- [x] Persistencia offline y cola de sincronización con reintento
- [x] Simulación de online/offline para probar la cola
- [x] `flutter analyze` sin issues y `flutter test` con 22 tests
- [x] APK release generado
- [ ] Integrar Firebase Auth + Firestore reales (adaptador en `_runSync()`)
- [ ] Notificaciones push con FCM
- [ ] Publicar en Play Store / App Store (requiere firma y cuenta)

## Fase 4: Pruebas, Despliegue e Integraciones

- [x] Tests unitarios de modelos, repositorio y widgets en Flutter
- [x] Tests de carrito, catálogo y validación de pedidos en la web
- [x] Build de producción de la web
- [x] Build de APK release
- [ ] Test de integración end-to-end web → Firestore → app
- [ ] Despliegue Netlify con hook desde `main`
- [ ] Firebase Hosting / Functions en producción
- [ ] WhatsApp Cloud API (hoy solo `wa.me`)
- [x] Documentación: `MEMORY.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `README.md`
- [x] Repositorio Git inicializado con commit convencional

## Hitos

| Fase | Entregable | Estado |
|---|---|---|
| 1 | Modelo de datos, reglas, índices y Functions | ✅ Compila y validado |
| 2 | Web SEO/GEO con pedidos | ✅ Build + 21 tests |
| 3 | App por roles con offline | ✅ APK + 22 tests |
| 4 | Pruebas, despliegue e integraciones | 🟡 Local completo; nube pendiente |

## Siguientes Pasos Recomendados

1. Crear el proyecto Firebase, copiar `.firebaserc.example` → `.firebaserc` y
   desplegar reglas, índices y Functions.
2. Rellenar `NEXT_PUBLIC_FIREBASE_*` en Netlify y verificar el flujo real.
3. Sustituir el adaptador demo de `_runSync()` por `cloud_firestore` y añadir
   `google-services.json` para la app.
4. Generar keystore de release y publicar el APK/AAB.
5. Configurar WhatsApp Cloud API y FCM cuando el MVP esté en producción.
