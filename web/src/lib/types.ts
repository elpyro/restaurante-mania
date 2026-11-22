export type MenuItemStatus = "available" | "unavailable" | "limited";

export interface Category {
  id: string;
  name: string;
  slug: string;
  description: string;
  order: number;
  emoji: string;
}

export interface MenuItem {
  id: string;
  name: string;
  slug: string;
  description: string;
  price: number;
  categoryId: string;
  categorySlug: string;
  status: MenuItemStatus;
  ingredients: string[];
  allergens: string[];
  emoji: string;
  featured: boolean;
  prepMinutes: number;
  calories: number;
}

export type OrderType = "pickup" | "delivery" | "table";
export type OrderStatus =
  | "pending"
  | "confirmed"
  | "preparing"
  | "ready"
  | "delivered"
  | "cancelled";
export type PaymentStatus = "pending" | "paid" | "refunded";
export type PaymentMethod = "cash" | "card" | "nequi" | "daviplata";

export interface OrderItem {
  menuItemId: string;
  name: string;
  price: number;
  quantity: number;
  emoji: string;
}

export interface Order {
  id: string;
  code: string;
  customerName: string;
  customerPhone: string;
  type: OrderType;
  tableNumber: number | null;
  items: OrderItem[];
  subtotal: number;
  tax: number;
  total: number;
  status: OrderStatus;
  paymentStatus: PaymentStatus;
  paymentMethod: PaymentMethod;
  notes: string;
  createdAt: string;
  updatedAt: string;
  source: "web";
}

export interface CartLine {
  menuItemId: string;
  name: string;
  price: number;
  quantity: number;
  emoji: string;
}

export interface CartTotals {
  subtotal: number;
  tax: number;
  total: number;
  count: number;
}

export const ORDER_STATUS_LABELS: Record<OrderStatus, string> = {
  pending: "Pendiente",
  confirmed: "Confirmado",
  preparing: "En preparación",
  ready: "Listo",
  delivered: "Entregado",
  cancelled: "Cancelado",
};

export const ORDER_TYPE_LABELS: Record<OrderType, string> = {
  pickup: "Para recoger",
  delivery: "Domicilio",
  table: "En mesa",
};

export const PAYMENT_METHOD_LABELS: Record<PaymentMethod, string> = {
  cash: "Efectivo",
  card: "Tarjeta",
  nequi: "Nequi",
  daviplata: "Daviplata",
};
