import '../models/app_user.dart';
import '../models/category.dart';
import '../models/ingredient.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../models/restaurant_settings.dart';
import '../models/restaurant_table.dart';
import '../models/role.dart';
import '../utils/formatters.dart';
import 'tenant.dart';

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
      imageUrl: 'https://images.unsplash.com/photo-1601050690597-df0568f70950?w=800&q=80&auto=format&fit=crop',
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
      imageUrl: 'https://images.unsplash.com/photo-1599789197514-47270cd526b4?w=800&q=80&auto=format&fit=crop',
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
      imageUrl: 'https://images.unsplash.com/photo-1528751086790-81a64658fc53?w=800&q=80&auto=format&fit=crop',
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
      imageUrl: 'https://images.unsplash.com/photo-1598515214211-89d3c73ae83b?w=800&q=80&auto=format&fit=crop',
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
      imageUrl: 'https://images.unsplash.com/photo-1547592166-23ac45744acd?w=800&q=80&auto=format&fit=crop',
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
      imageUrl: 'https://images.unsplash.com/photo-1559742811-822873691df8?w=800&q=80&auto=format&fit=crop',
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
      imageUrl: 'https://images.unsplash.com/photo-1532550907401-a500c9a57435?w=800&q=80&auto=format&fit=crop',
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
      imageUrl: 'https://images.unsplash.com/photo-1464349095431-e9a21285b5f3?w=800&q=80&auto=format&fit=crop',
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
      imageUrl: 'https://images.unsplash.com/photo-1551024506-0bccd828d307?w=800&q=80&auto=format&fit=crop',
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
      imageUrl: 'https://images.unsplash.com/photo-1564355808539-22fda35bed7e?w=800&q=80&auto=format&fit=crop',
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
      imageUrl: 'https://images.unsplash.com/photo-1534353473418-4cfa6c56fd38?w=800&q=80&auto=format&fit=crop',
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
      imageUrl: 'https://images.unsplash.com/photo-1622597467836-f3285f2131b8?w=800&q=80&auto=format&fit=crop',
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
      imageUrl: 'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=800&q=80&auto=format&fit=crop',
      featured: false,
      prepMinutes: 3,
      calories: 5,
    ),
  ];

  /// Insumos base del inventario. Las cantidades están en la unidad indicada.
  static final ingredients = <Ingredient>[
    _ing('masa-maiz', 'Masa de maíz', IngredientUnit.gramo, 8000, 1000, 3.5),
    _ing('carne-res', 'Carne de res', IngredientUnit.gramo, 6000, 800, 18),
    _ing('papa-criolla', 'Papa criolla', IngredientUnit.gramo, 7000, 1000, 4.5),
    _ing('hogao', 'Hogao', IngredientUnit.gramo, 3000, 500, 6),
    _ing('maiz-blanco', 'Maíz blanco', IngredientUnit.gramo, 4000, 500, 4),
    _ing('queso-campesino', 'Queso campesino', IngredientUnit.gramo, 3500, 500, 12),
    _ing('mantequilla', 'Mantequilla', IngredientUnit.gramo, 2000, 300, 14),
    _ing('platano-verde', 'Plátano verde', IngredientUnit.unidad, 60, 10, 800),
    _ing('tomate', 'Tomate', IngredientUnit.gramo, 3000, 400, 3),
    _ing('cebolla', 'Cebolla', IngredientUnit.gramo, 2500, 400, 2.8),
    _ing('frijoles', 'Frijoles', IngredientUnit.gramo, 5000, 800, 6),
    _ing('arroz', 'Arroz', IngredientUnit.gramo, 10000, 1500, 2.2),
    _ing('chicharron', 'Chicharrón', IngredientUnit.gramo, 2500, 400, 20),
    _ing('carne-molida', 'Carne molida', IngredientUnit.gramo, 3000, 500, 16),
    _ing('morcilla', 'Morcilla', IngredientUnit.gramo, 1500, 300, 12),
    _ing('chorizo', 'Chorizo', IngredientUnit.gramo, 2000, 300, 14),
    _ing('huevo', 'Huevo', IngredientUnit.unidad, 120, 20, 500),
    _ing('arepa', 'Arepa', IngredientUnit.unidad, 80, 15, 1200),
    _ing('pollo', 'Pollo', IngredientUnit.gramo, 6000, 800, 11),
    _ing('papa-pastusa', 'Papa pastusa', IngredientUnit.gramo, 6000, 800, 3.8),
    _ing('mazorca', 'Mazorca', IngredientUnit.unidad, 40, 8, 900),
    _ing('guascas', 'Guascas', IngredientUnit.gramo, 300, 50, 15),
    _ing('crema', 'Crema', IngredientUnit.mililitro, 2500, 400, 8),
    _ing('camaron', 'Camarón', IngredientUnit.gramo, 1500, 300, 38),
    _ing('calamar', 'Calamar', IngredientUnit.gramo, 1500, 300, 30),
    _ing('pescado', 'Pescado', IngredientUnit.gramo, 2500, 400, 22),
    _ing('leche-coco', 'Leche de coco', IngredientUnit.mililitro, 3000, 500, 9),
    _ing('pechuga-pollo', 'Pechuga de pollo', IngredientUnit.gramo, 5000, 700, 13),
    _ing('papa', 'Papa', IngredientUnit.gramo, 6000, 800, 3.2),
    _ing('lechuga', 'Lechuga', IngredientUnit.unidad, 25, 5, 1500),
    _ing('harina', 'Harina', IngredientUnit.gramo, 5000, 800, 3),
    _ing('leche', 'Leche', IngredientUnit.mililitro, 5000, 800, 3.6),
    _ing('leche-condensada', 'Leche condensada', IngredientUnit.mililitro, 1500, 250, 8),
    _ing('leche-evaporada', 'Leche evaporada', IngredientUnit.mililitro, 1500, 250, 7.5),
    _ing('chocolate', 'Chocolate', IngredientUnit.gramo, 1800, 300, 28),
    _ing('helado', 'Helado', IngredientUnit.mililitro, 2000, 300, 12),
    _ing('limon', 'Limón', IngredientUnit.unidad, 60, 10, 400),
    _ing('azucar', 'Azúcar', IngredientUnit.gramo, 4000, 600, 3),
    _ing('hielo', 'Hielo', IngredientUnit.gramo, 5000, 800, 0.5),
    _ing('lulo', 'Lulo', IngredientUnit.unidad, 40, 8, 900),
    _ing('agua', 'Agua', IngredientUnit.mililitro, 20000, 3000, 0.2),
    _ing('cafe', 'Café de Huila', IngredientUnit.gramo, 1500, 250, 32),
    _ing('vainilla', 'Vainilla', IngredientUnit.mililitro, 500, 100, 20),
  ];

  /// Consumo de insumos por porción de cada plato.
  static final recipes = <String, Map<String, double>>{
    'item-empanadas': {
      'masa-maiz': 120.0,
      'carne-res': 80.0,
      'papa-criolla': 50.0,
      'hogao': 30.0,
    },
    'item-arepa-queso': {
      'maiz-blanco': 100.0,
      'queso-campesino': 60.0,
      'mantequilla': 10.0,
    },
    'item-patacones': {
      'platano-verde': 1.0,
      'tomate': 40.0,
      'cebolla': 30.0,
      'queso-campesino': 40.0,
    },
    'item-bandeja-paisa': {
      'frijoles': 150.0,
      'arroz': 180.0,
      'chicharron': 80.0,
      'carne-molida': 90.0,
      'morcilla': 60.0,
      'chorizo': 60.0,
      'huevo': 1.0,
      'arepa': 1.0,
      'platano-verde': 1.0,
    },
    'item-ajiaco': {
      'pollo': 180.0,
      'papa-criolla': 120.0,
      'papa-pastusa': 100.0,
      'mazorca': 0.5,
      'guascas': 10.0,
      'crema': 40.0,
    },
    'item-cazuela-mariscos': {
      'camaron': 100.0,
      'calamar': 80.0,
      'pescado': 120.0,
      'leche-coco': 150.0,
      'arroz': 150.0,
    },
    'item-pollo-plancha': {
      'pechuga-pollo': 200.0,
      'papa': 150.0,
      'mantequilla': 15.0,
      'lechuga': 0.25,
    },
    'item-tres-leches': {
      'harina': 80.0,
      'leche': 120.0,
      'leche-condensada': 60.0,
      'leche-evaporada': 60.0,
      'huevo': 1.0,
    },
    'item-flan': {
      'leche': 150.0,
      'huevo': 1.0,
      'azucar': 50.0,
      'vainilla': 5.0,
    },
    'item-brownie': {
      'chocolate': 70.0,
      'mantequilla': 40.0,
      'huevo': 1.0,
      'harina': 60.0,
      'helado': 80.0,
    },
    'item-limonada-coco': {
      'limon': 2.0,
      'leche-coco': 120.0,
      'azucar': 30.0,
      'hielo': 150.0,
    },
    'item-jugo-lulo': {
      'lulo': 3.0,
      'agua': 200.0,
      'azucar': 25.0,
    },
    'item-cafe': {
      'cafe': 15.0,
      'agua': 200.0,
    },
  };

  /// Receta de preparación visible para el rol cocinero.
  static const recipeSteps = <String, String>{
    'item-empanadas':
        '1. Amasar el maíz y formar discos.\n2. Rellenar con carne y papa criolla guisada.\n3. Freír hasta dorar y servir con hogao.',
    'item-arepa-queso':
        '1. Asar la arepa en la parrilla.\n2. Agregar queso campesino y mantequilla.\n3. Servir cuando el queso esté derretido.',
    'item-patacones':
        '1. Cortar el plátano verde en rodajas.\n2. Freír dos veces hasta que queden crocantes.\n3. Cubrir con hogao y queso rallado.',
    'item-bandeja-paisa':
        '1. Calentar frijoles, arroz y carnes por separado.\n2. Freír el huevo y el plátano.\n3. Montar la bandeja con la arepa y servir.',
    'item-ajiaco':
        '1. Cocinar el pollo con papa pastusa y mazorca.\n2. Agregar papa criolla y guascas al final.\n3. Servir con crema y alcaparras aparte.',
    'item-cazuela-mariscos':
        '1. Saltear camarón, calamar y pescado.\n2. Agregar leche de coco y reducir.\n3. Servir con arroz con coco.',
    'item-pollo-plancha':
        '1. Marinar la pechuga con finas hierbas.\n2. Sellar a la plancha y terminar en horno.\n3. Servir con puré de papa y ensalada.',
    'item-tres-leches':
        '1. Hornear el bizcocho y dejar enfriar.\n2. Bañar con la mezcla de tres leches.\n3. Cubrir con merengue y canela.',
    'item-flan':
        '1. Preparar el caramelo en el molde.\n2. Mezclar leche, huevo, azúcar y vainilla.\n3. Hornar a baño María y refrigerar.',
    'item-brownie':
        '1. Derretir chocolate con mantequilla.\n2. Integrar huevo y harina sin batir de más.\n3. Hornear y servir con helado.',
    'item-limonada-coco':
        '1. Licuar limón con leche de coco y azúcar.\n2. Agregar hielo y licuar de nuevo.\n3. Servir bien frío.',
    'item-jugo-lulo':
        '1. Licuar el lulo con agua y azúcar.\n2. Colar si el cliente lo prefiere.\n3. Servir con hielo.',
    'item-cafe':
        '1. Moler el café de Huila al momento.\n2. Preparar en prensa francesa o espresso.\n3. Servir de inmediato.',
  };

  static Ingredient _ing(
    String id,
    String name,
    IngredientUnit unit,
    double stock,
    double minStock,
    double cost,
  ) {
    return Ingredient(
      id: id,
      name: name,
      unit: unit,
      stock: stock,
      minStock: minStock,
      cost: cost,
    );
  }

  static Ingredient ingredientById(String id) {
    return ingredients.firstWhere(
      (ingredient) => ingredient.id == id,
      orElse: () => Ingredient(
        id: id,
        name: id,
        unit: IngredientUnit.unidad,
        stock: 0,
        minStock: 0,
      ),
    );
  }

  /// Platos con SKU, receta estructurada y pasos de preparación.
  static List<MenuItem> menuItemsWithRecipes() {
    return menuItems.map((item) {
      final recipe = recipes[item.id] ?? const <String, double>{};
      final lines = recipe.entries
          .map(
            (entry) => RecipeIngredient(
              ingredientId: entry.key,
              quantity: entry.value,
            ),
          )
          .toList();
      final names = lines
          .map((line) => ingredientById(line.ingredientId).name)
          .toList();
      return item.copyWith(
        sku: item.sku.isEmpty
            ? 'SKU-${item.id.replaceFirst('item-', '').toUpperCase()}'
            : item.sku,
        recipe: lines,
        recipeSteps: recipeSteps[item.id] ?? item.recipeSteps,
        ingredients: names.isEmpty ? item.ingredients : names,
      );
    }).toList();
  }

  /// Catálogo inicial de una instancia demo. Manía conserva el seed histórico.
  static List<MenuItem> menuItemsFor(String tenantId) {
    final items = menuItemsWithRecipes();
    if (tenantId == 'fuego') {
      items.add(
        MenuItem(
          id: 'item-fuego-parrilla',
          name: 'Parrilla de la casa',
          slug: 'parrilla-de-la-casa',
          description: 'Corte de res a la brasa con hogao y papa criolla.',
          price: 42000,
          categoryId: 'cat-fuertes',
          categorySlug: 'platos-fuertes',
          status: MenuItemStatus.available,
          ingredients: ['Carne de res', 'Hogao', 'Papa criolla'],
          allergens: const [],
          emoji: '🔥',
          featured: true,
          prepMinutes: 22,
          calories: 780,
          sku: 'SKU-FUEGO-PARRILLA',
          recipe: const [
            RecipeIngredient(ingredientId: 'carne-res', quantity: 350),
            RecipeIngredient(ingredientId: 'hogao', quantity: 80),
          ],
        ),
      );
      final index = items.indexWhere((item) => item.id == 'item-empanadas');
      if (index >= 0) {
        items[index] = items[index].copyWith(price: items[index].price + 2000);
      }
    }
    if (tenantId == 'verde') {
      final index = items.indexWhere((item) => item.id == 'item-ajiaco');
      if (index >= 0) {
        items[index] = items[index].copyWith(
          status: MenuItemStatus.unavailable,
          manualUnavailable: true,
        );
      }
    }
    return items;
  }

  static List<Ingredient> ingredientsFor(String tenantId) {
    final list = List<Ingredient>.from(ingredients);

    void setStock(String id, double stock) {
      final index = list.indexWhere((ingredient) => ingredient.id == id);
      if (index >= 0) list[index] = list[index].copyWith(stock: stock);
    }

    if (tenantId == 'fuego') {
      setStock('maiz-blanco', 0);
      setStock('camaron', 1200);
    }
    if (tenantId == 'verde') {
      setStock('carne-res', 0);
      setStock('lechuga', 40);
    }
    return list;
  }

  static List<Order> ordersFor(String tenantId) =>
      tenantId == defaultTenantId ? orders() : <Order>[];

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
    AppUser(
      id: 'u-qa-admin',
      name: 'Administrador QA',
      email: 'admin.qa@restaurante.com',
      role: UserRole.admin,
    ),
    AppUser(
      id: 'u-qa-cashier',
      name: 'Cajero QA',
      email: 'cajero.qa@restaurante.com',
      role: UserRole.cashier,
    ),
    AppUser(
      id: 'u-qa-waiter',
      name: 'Mesero QA',
      email: 'mesero.qa@restaurante.com',
      role: UserRole.waiter,
    ),
    AppUser(
      id: 'u-qa-cook',
      name: 'Cocinero QA',
      email: 'cocina.qa@restaurante.com',
      role: UserRole.cook,
    ),
  ];

  static const settings = RestaurantSettings.defaults;

  /// Configuración y catálogo inicial de cualquier restaurante nuevo.
  /// Los IDs coinciden con `web/src/lib/generic-template.ts`.
  static const genericSettings = RestaurantSettings.generic;

  static const genericCategories = <Category>[
    Category(
      id: 'cat-generales',
      name: 'Platos',
      slug: 'platos',
      description: 'Opciones preparadas al momento para todos los gustos.',
      order: 1,
      emoji: '🍽️',
    ),
  ];

  static const genericIngredients = <Ingredient>[
    Ingredient(
      id: 'ing-base-generico',
      name: 'Ingrediente base',
      unit: IngredientUnit.gramo,
      stock: 5000,
      minStock: 500,
    ),
    Ingredient(
      id: 'ing-vegetales-genericos',
      name: 'Vegetales frescos',
      unit: IngredientUnit.gramo,
      stock: 5000,
      minStock: 500,
    ),
    Ingredient(
      id: 'ing-acompanamiento-generico',
      name: 'Acompañamiento',
      unit: IngredientUnit.gramo,
      stock: 5000,
      minStock: 500,
    ),
    Ingredient(
      id: 'ing-aderezo-suave',
      name: 'Aderezo suave',
      unit: IngredientUnit.mililitro,
      stock: 2000,
      minStock: 200,
    ),
  ];

  static List<MenuItem> genericMenuItems() => <MenuItem>[
        MenuItem(
          id: 'item-plato-del-dia',
          name: 'Plato del día',
          slug: 'plato-del-dia',
          description:
              'Una preparación completa con ingredientes frescos, lista para disfrutar en cualquier momento.',
          price: 15000,
          categoryId: 'cat-generales',
          categorySlug: 'platos',
          status: MenuItemStatus.available,
          ingredients: ['Ingrediente base', 'Vegetales frescos', 'Acompañamiento'],
          allergens: const [],
          emoji: '🍽️',
          featured: true,
          prepMinutes: 20,
          calories: 550,
          sku: 'SKU-PLATO-DIA',
          recipeSteps:
              'Prepara la base, añade los vegetales y sirve con el acompañamiento.',
          recipe: const [
            RecipeIngredient(ingredientId: 'ing-base-generico', quantity: 150),
            RecipeIngredient(
                ingredientId: 'ing-vegetales-genericos', quantity: 100),
            RecipeIngredient(
                ingredientId: 'ing-acompanamiento-generico', quantity: 120),
          ],
        ),
        MenuItem(
          id: 'item-ensalada-fresca',
          name: 'Ensalada fresca',
          slug: 'ensalada-fresca',
          description:
              'Vegetales frescos con un aderezo suave, preparados al momento.',
          price: 12000,
          categoryId: 'cat-generales',
          categorySlug: 'platos',
          status: MenuItemStatus.available,
          ingredients: ['Vegetales frescos', 'Aderezo suave'],
          allergens: const [],
          emoji: '🥗',
          featured: false,
          prepMinutes: 10,
          calories: 320,
          sku: 'SKU-ENSALADA',
          recipeSteps: 'Lava y corta los vegetales, mezcla con el aderezo y sirve.',
          recipe: const [
            RecipeIngredient(
                ingredientId: 'ing-vegetales-genericos', quantity: 120),
            RecipeIngredient(
                ingredientId: 'ing-aderezo-suave', quantity: 30),
          ],
        ),
      ];

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
      bool inventoryDeducted = false,
    }) {
      final orderItems = items.entries.map((entry) {
        final menuItem = menuItems.firstWhere((item) => item.id == entry.key);
        return OrderItem(
          menuItemId: menuItem.id,
          name: menuItem.name,
          price: menuItem.price,
          quantity: entry.value,
          emoji: menuItem.emoji,
          imageUrl: menuItem.imageUrl,
        );
      }).toList();
      final subtotal = orderItems.fold<double>(
        0,
        (sum, item) => sum + item.subtotal,
      );
      final audit = <OrderAuditEntry>[
        OrderAuditEntry(
          action: 'Pedido creado',
          timestamp: createdAt,
          actorName: 'Sistema (demo)',
          detail: '${type.label}${tableNumber != null ? ' · Mesa $tableNumber' : ''}',
        ),
      ];
      if (status != OrderStatus.pending) {
        audit.add(OrderAuditEntry(
          action: 'Estado actualizado',
          timestamp: createdAt.add(const Duration(minutes: 2)),
          actorName: 'Equipo de cocina',
          detail: 'Pendiente → ${status.label}',
        ));
      }
      if (paymentStatus == PaymentStatus.paid) {
        audit.add(OrderAuditEntry(
          action: 'Pago registrado',
          timestamp: createdAt.add(const Duration(minutes: 12)),
          actorName: 'Caja',
          detail: '${paymentMethod.label} · ${formatCop(subtotal)}',
        ));
      }
      if (status == OrderStatus.cancelled) {
        audit.add(OrderAuditEntry(
          action: 'Pedido cancelado',
          timestamp: createdAt.add(const Duration(minutes: 5)),
          actorName: 'Sistema (demo)',
        ));
      }
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
        inventoryDeducted: inventoryDeducted,
        auditLog: audit,
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
        inventoryDeducted: true,
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
        inventoryDeducted: true,
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
        inventoryDeducted: true,
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
        inventoryDeducted: true,
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
        inventoryDeducted: true,
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
        inventoryDeducted: true,
      ),
    ];
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
