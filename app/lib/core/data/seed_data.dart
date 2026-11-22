import '../models/app_user.dart';
import '../models/category.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../models/restaurant_settings.dart';
import '../models/restaurant_table.dart';
import '../models/role.dart';

class SeedData {
  static const demoPassword = '1234';

  static const categories = <Category>[
    Category(
      id: 'cat-entrantes',
      name: 'Entrantes',
      slug: 'entrantes',
      description: 'Para abrir el apetito con lo mejor de la cocina colombiana.',
      order: 1,
      emoji: '🥟',
    ),
    Category(
      id: 'cat-fuertes',
      name: 'Platos fuertes',
      slug: 'platos-fuertes',
      description: 'Clásicos preparados al momento con porciones generosas.',
      order: 2,
      emoji: '🍛',
    ),
    Category(
      id: 'cat-postres',
      name: 'Postres',
      slug: 'postres',
      description: 'El final dulce que tu comida merece.',
      order: 3,
      emoji: '🍰',
    ),
    Category(
      id: 'cat-bebidas',
      name: 'Bebidas',
      slug: 'bebidas',
      description: 'Jugos naturales, café de origen y limonadas de la casa.',
      order: 4,
      emoji: '🥤',
    ),
  ];

  static const menuItems = <MenuItem>[
    MenuItem(
      id: 'item-empanadas',
      name: 'Empanadas de carne',
      slug: 'empanadas-de-carne',
      description:
          'Tres empanadas crocantes rellenas de carne de res guisada, acompañadas de ají de la casa.',
      price: 14500,
      categoryId: 'cat-entrantes',
      categorySlug: 'entrantes',
      status: MenuItemStatus.available,
      ingredients: ['Masa de maíz', 'Carne de res', 'Papa criolla', 'Hogao'],
      allergens: ['Gluten', 'Cebolla'],
      emoji: '🥟',
      featured: true,
      prepMinutes: 12,
      calories: 420,
    ),
    MenuItem(
      id: 'item-arepa-queso',
      name: 'Arepa con queso',
      slug: 'arepa-con-queso',
      description:
          'Arepa de maíz blanco asada a la parrilla con queso campesino derretido.',
      price: 9500,
      categoryId: 'cat-entrantes',
      categorySlug: 'entrantes',
      status: MenuItemStatus.available,
      ingredients: ['Maíz blanco', 'Queso campesino', 'Mantequilla'],
      allergens: ['Lácteos'],
      emoji: '🫓',
      featured: false,
      prepMinutes: 8,
      calories: 310,
    ),
    MenuItem(
      id: 'item-patacones',
      name: 'Patacones con hogao',
      slug: 'patacones-con-hogao',
      description:
          'Plátano verde frito dos veces con hogao de tomate, cebolla y queso rallado.',
      price: 12500,
      categoryId: 'cat-entrantes',
      categorySlug: 'entrantes',
      status: MenuItemStatus.available,
      ingredients: ['Plátano verde', 'Tomate', 'Cebolla', 'Queso'],
      allergens: ['Lácteos'],
      emoji: '🍌',
      featured: false,
      prepMinutes: 10,
      calories: 380,
    ),
    MenuItem(
      id: 'item-bandeja-paisa',
      name: 'Bandeja paisa',
      slug: 'bandeja-paisa',
      description:
          'Frijoles antioqueños, arroz, chicharrón, carne molida, morcilla, chorizo, huevo, arepa y plátano.',
      price: 38900,
      categoryId: 'cat-fuertes',
      categorySlug: 'platos-fuertes',
      status: MenuItemStatus.available,
      ingredients: [
        'Frijoles',
        'Arroz',
        'Chicharrón',
        'Carne molida',
        'Morcilla',
        'Chorizo',
        'Huevo',
        'Arepa',
        'Plátano',
      ],
      allergens: ['Cerdo', 'Huevo', 'Gluten'],
      emoji: '🍛',
      featured: true,
      prepMinutes: 25,
      calories: 1250,
    ),
    MenuItem(
      id: 'item-ajiaco',
      name: 'Ajiaco santafereño',
      slug: 'ajiaco-santafereño',
      description:
          'Sopa espesa de pollo con tres tipos de papa, mazorca, guascas, crema y alcaparras.',
      price: 32900,
      categoryId: 'cat-fuertes',
      categorySlug: 'platos-fuertes',
      status: MenuItemStatus.available,
      ingredients: [
        'Pollo',
        'Papa criolla',
        'Papa pastusa',
        'Mazorca',
        'Guascas',
        'Crema',
      ],
      allergens: ['Lácteos'],
      emoji: '🍲',
      featured: true,
      prepMinutes: 22,
      calories: 720,
    ),
    MenuItem(
      id: 'item-cazuela-mariscos',
      name: 'Cazuela de mariscos',
      slug: 'cazuela-de-mariscos',
      description:
          'Camarones, calamares y pescado en salsa de coco y vino blanco, con arroz con coco.',
      price: 45900,
      categoryId: 'cat-fuertes',
      categorySlug: 'platos-fuertes',
      status: MenuItemStatus.limited,
      ingredients: [
        'Camarón',
        'Calamar',
        'Pescado',
        'Leche de coco',
        'Arroz',
      ],
      allergens: ['Mariscos', 'Pescado', 'Lácteos'],
      emoji: '🦐',
      featured: false,
      prepMinutes: 28,
      calories: 680,
    ),
    MenuItem(
      id: 'item-pollo-plancha',
      name: 'Pollo a la plancha',
      slug: 'pollo-a-la-plancha',
      description:
          'Pechuga marinada en finas hierbas con puré de papa y ensalada fresca.',
      price: 29900,
      categoryId: 'cat-fuertes',
      categorySlug: 'platos-fuertes',
      status: MenuItemStatus.available,
      ingredients: ['Pechuga de pollo', 'Papa', 'Mantequilla', 'Lechuga'],
      allergens: ['Lácteos'],
      emoji: '🍗',
      featured: false,
      prepMinutes: 20,
      calories: 540,
    ),
    MenuItem(
      id: 'item-tres-leches',
      name: 'Tres leches',
      slug: 'tres-leches',
      description:
          'Bizcocho esponjoso bañado en tres leches, con merengue y canela.',
      price: 13900,
      categoryId: 'cat-postres',
      categorySlug: 'postres',
      status: MenuItemStatus.available,
      ingredients: [
        'Harina',
        'Leche',
        'Leche condensada',
        'Leche evaporada',
        'Huevo',
      ],
      allergens: ['Gluten', 'Lácteos', 'Huevo'],
      emoji: '🍰',
      featured: true,
      prepMinutes: 5,
      calories: 460,
    ),
    MenuItem(
      id: 'item-flan',
      name: 'Flan de caramelo',
      slug: 'flan-de-caramelo',
      description: 'Flan casero de vainilla con caramelo oscuro y sal marina.',
      price: 11500,
      categoryId: 'cat-postres',
      categorySlug: 'postres',
      status: MenuItemStatus.available,
      ingredients: ['Leche', 'Huevo', 'Azúcar', 'Vainilla'],
      allergens: ['Lácteos', 'Huevo'],
      emoji: '🍮',
      featured: false,
      prepMinutes: 5,
      calories: 320,
    ),
    MenuItem(
      id: 'item-brownie',
      name: 'Brownie con helado',
      slug: 'brownie-con-helado',
      description:
          'Brownie tibio de chocolate 70% con helado de vainilla y salsa de chocolate.',
      price: 15900,
      categoryId: 'cat-postres',
      categorySlug: 'postres',
      status: MenuItemStatus.available,
      ingredients: ['Chocolate', 'Mantequilla', 'Huevo', 'Harina', 'Helado'],
      allergens: ['Gluten', 'Lácteos', 'Huevo'],
      emoji: '🍫',
      featured: true,
      prepMinutes: 8,
      calories: 510,
    ),
    MenuItem(
      id: 'item-limonada-coco',
      name: 'Limonada de coco',
      slug: 'limonada-de-coco',
      description:
          'Limón fresco licuado con leche de coco y hielo. La favorita de la casa.',
      price: 10900,
      categoryId: 'cat-bebidas',
      categorySlug: 'bebidas',
      status: MenuItemStatus.available,
      ingredients: ['Limón', 'Leche de coco', 'Azúcar', 'Hielo'],
      allergens: ['Coco'],
      emoji: '🥥',
      featured: true,
      prepMinutes: 4,
      calories: 210,
    ),
    MenuItem(
      id: 'item-jugo-lulo',
      name: 'Jugo de lulo',
      slug: 'jugo-de-lulo',
      description:
          'Lulo colombiano recién licuado, endulzado al punto y servido bien frío.',
      price: 9900,
      categoryId: 'cat-bebidas',
      categorySlug: 'bebidas',
      status: MenuItemStatus.available,
      ingredients: ['Lulo', 'Agua', 'Azúcar'],
      allergens: [],
      emoji: '🍹',
      featured: false,
      prepMinutes: 4,
      calories: 150,
    ),
    MenuItem(
      id: 'item-cafe',
      name: 'Café de origen',
      slug: 'cafe-de-origen',
      description:
          'Café de Huila tostado medio, preparado en prensa francesa o espresso.',
      price: 6900,
      categoryId: 'cat-bebidas',
      categorySlug: 'bebidas',
      status: MenuItemStatus.available,
      ingredients: ['Café de Huila', 'Agua'],
      allergens: [],
      emoji: '☕',
      featured: false,
      prepMinutes: 3,
      calories: 5,
    ),
  ];

  static const users = <AppUser>[
    AppUser(
      id: 'u-admin',
      name: 'Valentina Ríos',
      email: 'admin@restaurante.com',
      role: UserRole.admin,
    ),
    AppUser(
      id: 'u-cashier',
      name: 'Andrés Mejía',
      email: 'cajero@restaurante.com',
      role: UserRole.cashier,
    ),
    AppUser(
      id: 'u-waiter',
      name: 'Camila Duarte',
      email: 'mesero@restaurante.com',
      role: UserRole.waiter,
    ),
    AppUser(
      id: 'u-cook',
      name: 'Jorge Salazar',
      email: 'cocina@restaurante.com',
      role: UserRole.cook,
    ),
  ];

  static const settings = RestaurantSettings.defaults;

  static List<RestaurantTable> tables() {
    return List.generate(10, (index) {
      final number = index + 1;
      if (number == 3) {
        return RestaurantTable(
          id: 'table-3',
          number: 3,
          status: TableStatus.esperandoPedido,
          capacity: 4,
          currentOrderId: 'order-2',
        );
      }
      if (number == 4) {
        return RestaurantTable(
          id: 'table-4',
          number: 4,
          status: TableStatus.pidiendoCuenta,
          capacity: 2,
          currentOrderId: 'order-3',
        );
      }
      return RestaurantTable(
        id: 'table-$number',
        number: number,
        status: TableStatus.libre,
        capacity: number.isEven ? 4 : 2,
        currentOrderId: null,
      );
    });
  }

  static List<Order> orders() {
    final now = DateTime.now();

    Order build({
      required String id,
      required String code,
      required String customerName,
      required String customerPhone,
      required OrderType type,
      required int? tableNumber,
      required Map<String, int> items,
      required OrderStatus status,
      required PaymentStatus paymentStatus,
      required PaymentMethod paymentMethod,
      required DateTime createdAt,
      String notes = '',
      bool synced = true,
    }) {
      final orderItems = items.entries.map((entry) {
        final menuItem = menuItems.firstWhere((item) => item.id == entry.key);
        return OrderItem(
          menuItemId: menuItem.id,
          name: menuItem.name,
          price: menuItem.price,
          quantity: entry.value,
          emoji: menuItem.emoji,
        );
      }).toList();
      final subtotal = orderItems.fold<double>(
        0,
        (sum, item) => sum + item.subtotal,
      );
      return Order(
        id: id,
        code: code,
        customerName: customerName,
        customerPhone: customerPhone,
        type: type,
        tableNumber: tableNumber,
        items: orderItems,
        subtotal: subtotal,
        tax: 0,
        total: subtotal,
        status: status,
        paymentStatus: paymentStatus,
        paymentMethod: paymentMethod,
        notes: notes,
        createdAt: createdAt,
        updatedAt: createdAt,
        source: type == OrderType.table ? 'app' : 'web',
        synced: synced,
      );
    }

    return [
      build(
        id: 'order-1',
        code: 'RM-${now.year}${_two(now.month)}${_two(now.day)}-1042',
        customerName: 'Laura Gómez',
        customerPhone: '300 555 1122',
        type: OrderType.pickup,
        tableNumber: null,
        items: {'item-bandeja-paisa': 1, 'item-limonada-coco': 1},
        status: OrderStatus.pending,
        paymentStatus: PaymentStatus.pending,
        paymentMethod: PaymentMethod.nequi,
        createdAt: now.subtract(const Duration(minutes: 8)),
        notes: 'Sin morcilla, por favor.',
      ),
      build(
        id: 'order-2',
        code: 'RM-${now.year}${_two(now.month)}${_two(now.day)}-1041',
        customerName: 'Mesa 3 · Carlos Ruiz',
        customerPhone: '310 555 3344',
        type: OrderType.table,
        tableNumber: 3,
        items: {'item-ajiaco': 2, 'item-tres-leches': 1, 'item-cafe': 2},
        status: OrderStatus.preparing,
        paymentStatus: PaymentStatus.pending,
        paymentMethod: PaymentMethod.cash,
        createdAt: now.subtract(const Duration(minutes: 24)),
      ),
      build(
        id: 'order-3',
        code: 'RM-${now.year}${_two(now.month)}${_two(now.day)}-1040',
        customerName: 'Mesa 4 · Sofía Torres',
        customerPhone: '320 555 7788',
        type: OrderType.table,
        tableNumber: 4,
        items: {'item-cazuela-mariscos': 1, 'item-brownie': 2},
        status: OrderStatus.ready,
        paymentStatus: PaymentStatus.pending,
        paymentMethod: PaymentMethod.card,
        createdAt: now.subtract(const Duration(minutes: 38)),
      ),
      build(
        id: 'order-4',
        code: 'RM-${now.year}${_two(now.month)}${_two(now.day)}-1039',
        customerName: 'Mesa 5 · Diego Herrera',
        customerPhone: '301 555 9900',
        type: OrderType.table,
        tableNumber: 5,
        items: {'item-pollo-plancha': 1, 'item-jugo-lulo': 1},
        status: OrderStatus.delivered,
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.cash,
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      build(
        id: 'order-5',
        code: 'RM-${now.year}${_two(now.month)}${_two(now.day - 1)}-1035',
        customerName: 'Mariana López',
        customerPhone: '315 555 2211',
        type: OrderType.delivery,
        tableNumber: null,
        items: {'item-bandeja-paisa': 2, 'item-empanadas': 1},
        status: OrderStatus.delivered,
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.daviplata,
        createdAt: now.subtract(const Duration(days: 1, hours: 3)),
      ),
      build(
        id: 'order-6',
        code: 'RM-${now.year}${_two(now.month)}${_two(now.day - 1)}-1034',
        customerName: 'Felipe Ramírez',
        customerPhone: '312 555 6677',
        type: OrderType.pickup,
        tableNumber: null,
        items: {'item-ajiaco': 1, 'item-flan': 1},
        status: OrderStatus.delivered,
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.nequi,
        createdAt: now.subtract(const Duration(days: 1, hours: 5)),
      ),
      build(
        id: 'order-7',
        code: 'RM-${now.year}${_two(now.month)}${_two(now.day - 2)}-1030',
        customerName: 'Pedido cancelado',
        customerPhone: '300 000 0000',
        type: OrderType.pickup,
        tableNumber: null,
        items: {'item-pollo-plancha': 1},
        status: OrderStatus.cancelled,
        paymentStatus: PaymentStatus.refunded,
        paymentMethod: PaymentMethod.card,
        createdAt: now.subtract(const Duration(days: 2, hours: 2)),
      ),
      build(
        id: 'order-8',
        code: 'RM-${now.year}${_two(now.month)}${_two(now.day - 3)}-1027',
        customerName: 'Mesa 2 · Paula Cárdenas',
        customerPhone: '318 555 4433',
        type: OrderType.table,
        tableNumber: 2,
        items: {'item-patacones': 2, 'item-limonada-coco': 2, 'item-tres-leches': 1},
        status: OrderStatus.delivered,
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.card,
        createdAt: now.subtract(const Duration(days: 3, hours: 4)),
      ),
    ];
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
