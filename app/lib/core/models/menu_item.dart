enum MenuItemStatus {
  available('Disponible'),
  limited('Últimas unidades'),
  unavailable('Agotado');

  const MenuItemStatus(this.label);

  final String label;

  static MenuItemStatus fromName(String? value) => MenuItemStatus.values
      .firstWhere((status) => status.name == value,
          orElse: () => MenuItemStatus.available);
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.price,
    required this.categoryId,
    required this.categorySlug,
    required this.status,
    required this.ingredients,
    required this.allergens,
    required this.emoji,
    required this.featured,
    required this.prepMinutes,
    required this.calories,
  });

  final String id;
  final String name;
  final String slug;
  final String description;
  final double price;
  final String categoryId;
  final String categorySlug;
  final MenuItemStatus status;
  final List<String> ingredients;
  final List<String> allergens;
  final String emoji;
  final bool featured;
  final int prepMinutes;
  final int calories;

  bool get isAvailable => status != MenuItemStatus.unavailable;

  MenuItem copyWith({
    String? name,
    String? description,
    double? price,
    String? categoryId,
    String? categorySlug,
    MenuItemStatus? status,
    List<String>? ingredients,
    List<String>? allergens,
    String? emoji,
    bool? featured,
    int? prepMinutes,
    int? calories,
  }) {
    return MenuItem(
      id: id,
      name: name ?? this.name,
      slug: slug,
      description: description ?? this.description,
      price: price ?? this.price,
      categoryId: categoryId ?? this.categoryId,
      categorySlug: categorySlug ?? this.categorySlug,
      status: status ?? this.status,
      ingredients: ingredients ?? this.ingredients,
      allergens: allergens ?? this.allergens,
      emoji: emoji ?? this.emoji,
      featured: featured ?? this.featured,
      prepMinutes: prepMinutes ?? this.prepMinutes,
      calories: calories ?? this.calories,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'description': description,
        'price': price,
        'categoryId': categoryId,
        'categorySlug': categorySlug,
        'status': status.name,
        'ingredients': ingredients,
        'allergens': allergens,
        'emoji': emoji,
        'featured': featured,
        'prepMinutes': prepMinutes,
        'calories': calories,
      };

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        description: json['description'] as String? ?? '',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        categoryId: json['categoryId'] as String? ?? '',
        categorySlug: json['categorySlug'] as String? ?? '',
        status: MenuItemStatus.fromName(json['status'] as String?),
        ingredients: (json['ingredients'] as List<dynamic>?)
                ?.whereType<String>()
                .toList() ??
            const [],
        allergens: (json['allergens'] as List<dynamic>?)
                ?.whereType<String>()
                .toList() ??
            const [],
        emoji: json['emoji'] as String? ?? '🍽️',
        featured: json['featured'] as bool? ?? false,
        prepMinutes: (json['prepMinutes'] as num?)?.toInt() ?? 15,
        calories: (json['calories'] as num?)?.toInt() ?? 0,
      );
}
