class Category {
  const Category({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.order,
    required this.emoji,
  });

  final String id;
  final String name;
  final String slug;
  final String description;
  final int order;
  final String emoji;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'description': description,
        'order': order,
        'emoji': emoji,
      };

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        description: json['description'] as String? ?? '',
        order: (json['order'] as num?)?.toInt() ?? 0,
        emoji: json['emoji'] as String? ?? '🍽️',
      );
}
