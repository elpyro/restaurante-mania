enum IngredientUnit {
  gramo('g', 'gramos'),
  kilogramo('kg', 'kilogramos'),
  mililitro('ml', 'mililitros'),
  litro('l', 'litros'),
  unidad('unidad', 'unidades');

  const IngredientUnit(this.symbol, this.label);

  final String symbol;
  final String label;

  static IngredientUnit fromSymbol(String? value) =>
      IngredientUnit.values.firstWhere(
        (unit) => unit.symbol == value || unit.name == value,
        orElse: () => IngredientUnit.unidad,
      );
}

/// Insumo del inventario. Se descuenta automáticamente cuando un pedido
/// pasa a preparación, según la receta de cada plato.
class Ingredient {
  const Ingredient({
    required this.id,
    required this.name,
    required this.unit,
    required this.stock,
    required this.minStock,
    this.cost = 0,
  });

  final String id;
  final String name;
  final IngredientUnit unit;
  final double stock;
  final double minStock;

  /// Costo unitario de referencia (COP por unidad de medida).
  final double cost;

  bool get isLow => stock <= minStock;

  double get stockRatio {
    final target = minStock <= 0 ? 1.0 : minStock * 3;
    if (target <= 0) return 0;
    return (stock / target).clamp(0.0, 1.0);
  }

  String get stockLabel => '${_format(stock)} ${unit.symbol}';

  String get minStockLabel => '${_format(minStock)} ${unit.symbol}';

  static String _format(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  Ingredient copyWith({
    String? name,
    IngredientUnit? unit,
    double? stock,
    double? minStock,
    double? cost,
  }) {
    return Ingredient(
      id: id,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      stock: stock ?? this.stock,
      minStock: minStock ?? this.minStock,
      cost: cost ?? this.cost,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'unit': unit.symbol,
        'stock': stock,
        'minStock': minStock,
        'cost': cost,
      };

  factory Ingredient.fromJson(Map<String, dynamic> json) => Ingredient(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        unit: IngredientUnit.fromSymbol(json['unit'] as String?),
        stock: (json['stock'] as num?)?.toDouble() ?? 0,
        minStock: (json['minStock'] as num?)?.toDouble() ?? 0,
        cost: (json['cost'] as num?)?.toDouble() ?? 0,
      );
}

/// Línea de receta: cuánto insumo consume una porción del plato.
class RecipeIngredient {
  const RecipeIngredient({
    required this.ingredientId,
    required this.quantity,
  });

  final String ingredientId;
  final double quantity;

  RecipeIngredient copyWith({String? ingredientId, double? quantity}) =>
      RecipeIngredient(
        ingredientId: ingredientId ?? this.ingredientId,
        quantity: quantity ?? this.quantity,
      );

  Map<String, dynamic> toJson() => {
        'ingredientId': ingredientId,
        'quantity': quantity,
      };

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) =>
      RecipeIngredient(
        ingredientId: json['ingredientId'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      );
}
