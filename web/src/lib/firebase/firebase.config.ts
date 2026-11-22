/**
 * Configuración del cliente Firebase.
 *
 * Todos los valores se leen de variables de entorno `NEXT_PUBLIC_*` para no
 * versionar credenciales. Cuando faltan, la web opera en modo demo con los
 * datos semilla de `src/lib/seed.ts`.
 */
export interface FirebaseClientConfig {
  apiKey: string;
  authDomain: string;
  projectId: string;
  storageBucket: string;
  messagingSenderId: string;
  appId: string;
  measurementId?: string;
}

const env = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY?.trim() ?? "",
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN?.trim() ?? "",
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID?.trim() ?? "",
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET?.trim() ?? "",
  messagingSenderId:
    process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID?.trim() ?? "",
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID?.trim() ?? "",
  measurementId: process.env.NEXT_PUBLIC_FIREBASE_MEASUREMENT_ID?.trim(),
};

function isPlaceholder(value: string): boolean {
  return (
    value === "" ||
    value.startsWith("tu_") ||
    value.startsWith("YOUR_") ||
    value.includes("tu-proyecto")
  );
}

export const firebaseConfig: FirebaseClientConfig = env;

export function hasFirebaseConfig(): boolean {
  return (
    !isPlaceholder(env.apiKey) &&
    !isPlaceholder(env.projectId) &&
    !isPlaceholder(env.appId)
  );
}

export default firebaseConfig;
