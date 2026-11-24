/**
 * Migra los datos demo (web + app) a Cloud Firestore.
 *
 * Uso:
 *   node firebase/scripts/migrate-demo-to-firestore.mjs
 *
 * Requiere firebase/service-account.json con rol `datastore.user` (o superior).
 * La migración es idempotente: sobrescribe los documentos por ID.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { webcrypto } from "node:crypto";
import { createRequire } from "node:module";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..", "..");
const require = createRequire(import.meta.url);

const PROJECT_ID = "restaurante-mania-e47a0";
const BASE_URL = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const SERVICE_ACCOUNT_PATH = path.join(root, "firebase", "service-account.json");
const WEB_ORDERS_PATH = path.join(root, "web", ".data", "orders.json");
const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL?.trim() || "http://localhost:3000";

const serviceAccount = JSON.parse(fs.readFileSync(SERVICE_ACCOUNT_PATH, "utf8"));
let authToken = "";

function base64url(value) {
  return Buffer.from(value).toString("base64url");
}

function pemToDer(pem) {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s/g, "");
  return new Uint8Array(Buffer.from(body, "base64"));
}

async function getAccessToken() {
  if (authToken) return authToken;
  const now = Math.floor(Date.now() / 1000);
  const unsigned = [
    base64url(JSON.stringify({ alg: "RS256", typ: "JWT" })),
    base64url(
      JSON.stringify({
        iss: serviceAccount.client_email,
        scope:
          "https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/cloud-platform",
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 3600,
      }),
    ),
  ].join(".");
  const key = await webcrypto.subtle.importKey(
    "pkcs8",
    pemToDer(serviceAccount.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await webcrypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    Buffer.from(unsigned),
  );
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${base64url(new Uint8Array(signature))}`,
    }),
  });
  if (!response.ok) {
    throw new Error(`OAuth respondió ${response.status}: ${await response.text()}`);
  }
  const payload = await response.json();
  authToken = payload.access_token;
  return authToken;
}

function encodeValue(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(encodeValue) } };
  }
  if (typeof value === "object") {
    return { mapValue: { fields: encodeFields(value) } };
  }
  return { nullValue: null };
}

function encodeFields(data) {
  return Object.fromEntries(
    Object.entries(data).map(([key, value]) => [key, encodeValue(value)]),
  );
}

async function writeDoc(collection, id, data) {
  const token = await getAccessToken();
  const fields = encodeFields(data);
  const mask = Object.keys(fields)
    .map((field) => `updateMask.fieldPaths=${encodeURIComponent(field)}`)
    .join("&");
  const url = `${BASE_URL}/${collection}/${encodeURIComponent(id)}?${mask}`;
  const response = await fetch(url, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ fields }),
  });
  if (!response.ok) {
    throw new Error(
      `Firestore PATCH ${collection}/${id} respondió ${response.status}: ${await response.text()}`,
    );
  }
}

function loadSeed() {
  const ts = require(path.join(root, "web", "node_modules", "typescript"));
  const source = fs.readFileSync(path.join(root, "web", "src", "lib", "seed.ts"), "utf8");
  const output = ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
      esModuleInterop: true,
    },
  }).outputText;
  const module = { exports: {} };
  new Function("exports", "module", "require", output)(module.exports, module, require);
  return module.exports;
}

function pad(value) {
  return String(value).padStart(2, "0");
}

function dayKeyFor(value) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Bogota",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date(value));
  const get = (type) => parts.find((part) => part.type === type)?.value ?? "";
  return `${get("year")}-${get("month")}-${get("day")}`;
}

function normalizePhone(value) {
  return String(value ?? "").replace(/\D/g, "");
}

function humanizeId(id) {
  return id
    .split("-")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}

function computeMaxServings(recipe, stocks) {
  if (!recipe?.length) return null;
  let max = Number.POSITIVE_INFINITY;
  for (const line of recipe) {
    const stock = stocks[line.ingredientId];
    if (stock === undefined) continue;
    const canMake = stock <= 0 ? 0 : Math.floor(stock / line.quantity);
    if (canMake < max) max = canMake;
  }
  return Number.isFinite(max) ? Math.max(0, max) : null;
}

function buildAppOrders(menuItems) {
  const byId = new Map(menuItems.map((item) => [item.id, item]));
  const now = new Date();
  const minutesAgo = (minutes) =>
    new Date(now.getTime() - minutes * 60_000).toISOString();
  const code = (daysAgo, suffix) => {
    const date = new Date(now.getTime() - daysAgo * 86_400_000);
    return `RM-${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}-${suffix}`;
  };
  const build = ({
    id,
    code: orderCode,
    customerName,
    customerPhone,
    type,
    tableNumber = null,
    lines,
    status,
    paymentStatus,
    paymentMethod,
    createdAt,
    notes = "",
  }) => {
    const items = lines.map(([menuItemId, quantity]) => {
      const item = byId.get(menuItemId);
      return {
        menuItemId,
        name: item?.name ?? menuItemId,
        price: item?.price ?? 0,
        quantity,
        emoji: item?.emoji ?? "",
        imageUrl: item?.imageUrl ?? "",
      };
    });
    const subtotal = items.reduce((sum, item) => sum + item.price * item.quantity, 0);
    return {
      id,
      code: orderCode,
      customerName,
      customerPhone,
      deliveryAddress: "",
      type,
      tableNumber,
      items,
      subtotal,
      tax: 0,
      total: subtotal,
      status,
      paymentStatus,
      paymentMethod,
      notes,
      source: type === "table" ? "app" : "web",
      createdAt,
      updatedAt: createdAt,
      synced: true,
      inventoryDeducted: status !== "pending" && status !== "cancelled",
      auditLog: [
        { action: "Pedido creado", timestamp: createdAt, actorName: "Sistema (demo)", detail: type },
      ],
    };
  };

  return [
    build({
      id: "order-1",
      code: code(0, "1042"),
      customerName: "Laura Gómez",
      customerPhone: "300 555 1122",
      type: "pickup",
      lines: [["item-bandeja-paisa", 1], ["item-limonada-coco", 1]],
      status: "pending",
      paymentStatus: "pending",
      paymentMethod: "nequi",
      createdAt: minutesAgo(8),
      notes: "Sin morcilla, por favor.",
    }),
    build({
      id: "order-2",
      code: code(0, "1041"),
      customerName: "Mesa 3 · Carlos Ruiz",
      customerPhone: "310 555 3344",
      type: "table",
      tableNumber: 3,
      lines: [["item-ajiaco", 2], ["item-tres-leches", 1], ["item-cafe", 2]],
      status: "preparing",
      paymentStatus: "pending",
      paymentMethod: "cash",
      createdAt: minutesAgo(24),
    }),
    build({
      id: "order-3",
      code: code(0, "1040"),
      customerName: "Mesa 4 · Sofía Torres",
      customerPhone: "320 555 7788",
      type: "table",
      tableNumber: 4,
      lines: [["item-cazuela-mariscos", 1], ["item-brownie", 2]],
      status: "ready",
      paymentStatus: "pending",
      paymentMethod: "card",
      createdAt: minutesAgo(38),
    }),
    build({
      id: "order-4",
      code: code(0, "1039"),
      customerName: "Mesa 5 · Diego Herrera",
      customerPhone: "301 555 9900",
      type: "table",
      tableNumber: 5,
      lines: [["item-pollo-plancha", 1], ["item-jugo-lulo", 1]],
      status: "delivered",
      paymentStatus: "paid",
      paymentMethod: "cash",
      createdAt: minutesAgo(120),
    }),
    build({
      id: "order-5",
      code: code(1, "1035"),
      customerName: "Mariana López",
      customerPhone: "315 555 2211",
      type: "delivery",
      lines: [["item-bandeja-paisa", 2], ["item-empanadas", 1]],
      status: "delivered",
      paymentStatus: "paid",
      paymentMethod: "daviplata",
      createdAt: minutesAgo(27 * 60),
    }),
    build({
      id: "order-6",
      code: code(1, "1034"),
      customerName: "Felipe Ramírez",
      customerPhone: "312 555 6677",
      type: "pickup",
      lines: [["item-ajiaco", 1], ["item-flan", 1]],
      status: "delivered",
      paymentStatus: "paid",
      paymentMethod: "nequi",
      createdAt: minutesAgo(29 * 60),
    }),
    build({
      id: "order-7",
      code: code(2, "1030"),
      customerName: "Pedido cancelado",
      customerPhone: "300 000 0000",
      type: "pickup",
      lines: [["item-pollo-plancha", 1]],
      status: "cancelled",
      paymentStatus: "refunded",
      paymentMethod: "card",
      createdAt: minutesAgo(50 * 60),
    }),
    build({
      id: "order-8",
      code: code(3, "1027"),
      customerName: "Mesa 2 · Paula Cárdenas",
      customerPhone: "318 555 4433",
      type: "table",
      tableNumber: 2,
      lines: [["item-patacones", 2], ["item-limonada-coco", 2], ["item-tres-leches", 1]],
      status: "delivered",
      paymentStatus: "paid",
      paymentMethod: "card",
      createdAt: minutesAgo(76 * 60),
    }),
  ];
}

function buildVisits(orders) {
  return orders
    .filter((order) => String(order.source ?? "") === "web")
    .map((order) => ({
      id: `vis_migrated_${order.id}`,
      occurredAt: order.createdAt,
      dayKey: dayKeyFor(order.createdAt),
      registered: true,
      customerName: order.customerName,
      customerPhone: order.customerPhone,
      normalizedPhone: normalizePhone(order.customerPhone),
      referenceLabel: `/order/${order.id}`,
      referenceUrl: `${SITE_URL}/order/${order.id}`,
      referrer: "",
    }));
}

function buildCustomers(orders, visits) {
  const now = new Date().toISOString();
  const byPhone = new Map();
  const sorted = [...orders].sort((a, b) =>
    String(a.createdAt).localeCompare(String(b.createdAt)),
  );

  for (const order of sorted) {
    const normalized = normalizePhone(order.customerPhone);
    if (normalized.length < 7) continue;
    const createdAt = String(order.createdAt);
    const name = String(order.customerName ?? "").trim();
    const address = String(order.deliveryAddress ?? "").trim();
    const current = byPhone.get(normalized);
    if (!current) {
      byPhone.set(normalized, {
        id: `cus_${normalized}`,
        name,
        phone: String(order.customerPhone ?? "").trim(),
        normalizedPhone: normalized,
        address,
        tags: [],
        notes: "",
        createdAt,
        updatedAt: now,
        lastOrderAt: createdAt,
        orderCount: 1,
        totalSpent: order.status === "cancelled" ? 0 : Number(order.total ?? 0),
        lastType: order.type,
        addresses: address ? [address] : [],
        visitCount: 0,
        visitHistory: {},
      });
      continue;
    }
    const isLast = createdAt >= current.lastOrderAt;
    current.orderCount += 1;
    current.totalSpent += order.status === "cancelled" ? 0 : Number(order.total ?? 0);
    if (createdAt < current.createdAt) current.createdAt = createdAt;
    if (isLast) {
      current.lastOrderAt = createdAt;
      current.lastType = order.type;
    }
    if (name) current.name = name;
    if (address && !current.addresses.some((a) => a.toLowerCase() === address.toLowerCase())) {
      current.addresses.push(address);
      current.address = address;
    }
  }

  for (const visit of visits) {
    const normalized = String(visit.normalizedPhone ?? "");
    const customer = byPhone.get(normalized);
    if (!customer) continue;
    customer.visitCount += 1;
    customer.visitHistory[visit.dayKey] = (customer.visitHistory[visit.dayKey] ?? 0) + 1;
  }

  return [...byPhone.values()].sort((a, b) =>
    b.lastOrderAt.localeCompare(a.lastOrderAt),
  );
}

async function writeCatalog(seed) {
  const now = new Date().toISOString();
  for (const category of seed.seedCategories) {
    await writeDoc("categories", category.id, category);
  }
  for (const [id, stock] of Object.entries(seed.demoIngredientStocks)) {
    await writeDoc("ingredients", id, {
      id,
      name: humanizeId(id),
      stock,
      minStock: 0,
      unit: "g/ml",
      updatedAt: now,
    });
  }
  for (const item of seed.seedMenuItems) {
    const recipe = item.recipe ?? seed.demoRecipes[item.id] ?? [];
    await writeDoc("menuItems", item.id, {
      ...item,
      sku: item.sku ?? "",
      videoUrl: item.videoUrl ?? "",
      recipe,
      maxServings: computeMaxServings(recipe, seed.demoIngredientStocks),
    });
  }
  const tables = Array.from({ length: 10 }, (_, index) => {
    const number = index + 1;
    const special = number === 3 || number === 4;
    return {
      id: `table-${number}`,
      number,
      status: number === 3 ? "esperandoPedido" : number === 4 ? "pidiendoCuenta" : "libre",
      currentOrderId: number === 3 ? "order-2" : number === 4 ? "order-3" : null,
      capacity: special ? number === 3 ? 4 : 2 : number % 2 === 0 ? 4 : 2,
    };
  });
  for (const table of tables) await writeDoc("tables", table.id, table);
  await writeDoc("restaurant", "config", {
    name: "Restaurante Manía",
    phone: "+57 300 123 4567",
    whatsapp: "573001234567",
    address: "Calle 10 # 43-12, Medellín",
    city: "Medellín",
    hours: "11:00 - 22:00",
    siteUrl: SITE_URL,
    updatedAt: now,
  });
}

async function main() {
  await getAccessToken();
  const seed = loadSeed();
  await writeCatalog(seed);

  const webOrders = fs.existsSync(WEB_ORDERS_PATH)
    ? JSON.parse(fs.readFileSync(WEB_ORDERS_PATH, "utf8"))
    : [];
  const appOrders = buildAppOrders(seed.seedMenuItems);
  const orders = [...webOrders, ...appOrders];

  for (const order of orders) {
    const id = String(order.id ?? order.code);
    await writeDoc("orders", id, order);
  }

  const visits = buildVisits(webOrders);
  for (const visit of visits) await writeDoc("webVisits", visit.id, visit);

  const customers = buildCustomers(orders, visits);
  for (const customer of customers) await writeDoc("customers", customer.id, customer);

  console.log(
    `Migración completada: ${seed.seedCategories.length} categorías, ` +
      `${seed.seedMenuItems.length} platos, ` +
      `${Object.keys(seed.demoIngredientStocks).length} ingredientes, ` +
      `${orders.length} pedidos, ${visits.length} visitas, ` +
      `${customers.length} clientes.`,
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
