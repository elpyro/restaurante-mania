# AGENTS.md - Reglas Estrictas de Desarrollo

## Contexto
Este proyecto es un monorepo para un sistema integral de restaurantes con dos módulos conectados:
- **Web pública** (Next.js): CRM + Menú y pedidos en línea, optimizada para SEO y agentes de IA.
- **App administrativa** (Flutter): POS con persistencia offline y sincronización en tiempo real.

## Pila Tecnológica
- **Web:** Next.js 14 (App Router), TypeScript, Tailwind CSS
- **App móvil:** Flutter (Dart), con persistencia offline via SQLite/Hive
- **Backend:** Firebase (Cloud Firestore con persistence offline, Authentication, Storage, Functions)
- **Despliegue:** Netlify (Web), Firebase Hosting/Functions (Backend), Android/iOS (App)

## Convenciones de Código

### Next.js (Web Pública)
- Usar App Router (pp/ directory).
- Componentes en TypeScript con tipado estricto.
- Tailwind CSS para estilos; classify utility para clases condicionales.
- SEO/GEO obligatorio: metadata dinámica por página, sitemap.xml, obots.txt, JSON-LD estructurados.
- Endpoints de API via Firebase Functions o direct Firestore client (con caché).

### Flutter (App Administrativa)
- Arquitectura **Feature-First / Clean Architecture ligera**.
- Cada característica (eature/) tiene su propia UI, lógica (bloc/provider/riverpod) y modelos.
- Persistencia offline habilitada por defecto en Firestore (enablePersistence).
- Manejo de conexiones: detectar estado online/offline y transicionar estados sincronizados automáticamente.

### Firebase / TypeScript (Backend/Functions)
- Usar TypeScript para todas las Functions.
- Reglas de seguridad irestore.rules y índices irestore.indexes.json deben comprometerse después de cada cambio de esquema.
- **Principio crítico:** Las Functions deben ser **stateless** y usar la SDK de Firestore async/await.
- No almacenar secrets en cliente; usar Firebase Auth tokens de verificación.

## Principios de Persistencia Offline
- Firestore client-side persistence está habilitada por defecto en ambas apps.
- La app Flutter debe llamar a Firestore.enablePersistence() al iniciar, con manejo de errores quota-exceeded.
- Datos offline deben verse consistentes; usar onSnapshot con includeMetadataChanges: true para detectar cambios de estado (online/offline).
- Colas de sincronización: pedidos generados offline deben guardarse localmente y enviarse al restablecer la conexión.

## Flujo de Trabajo para Agentes de IA / SEO-GEO
1. **Web Pública:** Cada página de plato/menú debe tener:
   - og: y 	witter: tags generados SSR.
   - JSON-LD Restaurant, Menu, MenuItem en el <head>.
   - sitemap.xml generado dinámicamente en /firetsome/sitemap/route.ts (Next.js).
   - obots.txt estático que permita rastreo de todas las rutas de catálogo.
2. **Agentes de IA (ChatGPT, Gemini, Perplexity):**
   - Archivo llms.txt en la raíz del dominio con metadatos esenciales.
   - Datos estructurados deben ser consistentes y actualizados en tiempo real via Firestore.
3. **Git Workflow:**
   - main branch protegido: solo merging via PR con aprobación.
   - Feature branches por módulo: eature/web-xxx, eature/app-xxx, eature/firebase-xxx.
   - Commit messages convencionales (eat:, ix:, docs:, chore:).

## Documentación Obligatoria
Todo cambio significativo en el modelo de datos o arquitectura debe reflejarse en MEMORY.md inmediatamente después del commit.
