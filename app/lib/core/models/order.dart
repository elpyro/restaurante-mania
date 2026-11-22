enum OrderStatus {
  pending('Pendiente'),
  confirmed('Confirmado'),
  preparing('En preparación'),
  ready('Listo'),
  delivered('Entregado'),
  cancelled('Cancelado');

  const OrderStatus(this.label);

  final String label;

  static OrderStatus fromName(String? value) => OrderStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => OrderStatus.pending,
      );

  bool get isActive => this != OrderStatus.delivered && this != OrderStatus.cancelled;

  OrderStatus? get next => switch (this) {
        OrderStatus.pending => OrderStatus.confirmed,
        OrderStatus.confirmed => OrderStatus.preparing,
        OrderStatus.preparing => OrderStatus.ready,
        OrderStatus.ready => OrderStatus.delivered,
        OrderStatus.delivered || OrderStatus.cancelled => null,
      };
}

enum OrderType {
  pickup('Para recoger'),
  delivery('Domicilio'),
  table('En mesa');

  const OrderType(this.label);

  final String label;

  static OrderType fromName(String? value) => OrderType.values.firstWhere(
        (type) => type.name == value,
        orElse: () => OrderType.pickup,
      );
}

enum PaymentMethod {
  cash('Efectivo'),
  card('Tarjeta'),
  nequi('Nequi'),
  daviplata('Daviplata');

  const PaymentMethod(this.label);

  final String label;

  static PaymentMethod fromName(String? value) =>
      PaymentMethod.values.firstWhere(
        (method) => method.name == value,
        orElse: () => PaymentMethod.cash,
      );
}

enum PaymentStatus {
  pending('Pendiente'),
  paid('Pagado'),
  refunded('Reembolsado');

  const PaymentStatus(this.label);

  final String label;

  static PaymentStatus fromName(String? value) =>
      PaymentStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => PaymentStatus.pending,
      );
}

class OrderItem {
  const OrderItem({
    required this.menuItemId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.emoji,
  });

  final String menuItemId;
  final String name;
  final double price;
  final int quantity;
  final String emoji;

  double get subtotal => price * quantity;

  Map<String, dynamic> toJson() => {
        'menuItemId': menuItemId,
        'name': name,
        'price': price,
        'quantity': quantity,
        'emoji': emoji,
      };

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        menuItemId: json['menuItemId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        emoji: json['emoji'] as String? ?? '🍽️',
      );
}

class Order {
  const Order({
    required this.id,
    required this.code,
    required this.customerName,
    required this.customerPhone,
    required this.type,
    required this.tableNumber,
    required this.items,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.status,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.source,
    required this.synced,
    this.inventoryDeducted = false,
    this.createdBy,
    this.createdByName,
    this.updatedBy,
    this.updatedByName,
  });

  final String id;
  final String code;
  final String customerName;
  final String customerPhone;
  final OrderType type;
  final int? tableNumber;
  final List<OrderItem> items;
  final double subtotal;
  final double tax;
  final double total;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final PaymentMethod paymentMethod;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String source;
  final bool synced;

  /// Evita descontar dos veces el inventario del mismo pedido.
  final bool inventoryDeducted;

  /// Huella de auditoría: quién creó y quién actualizó por última vez.
  final String? createdBy;
  final String? createdByName;
  final String? updatedBy;
  final String? updatedByName;

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  Order copyWith({
    String? customerName,
    String? customerPhone,
    OrderType? type,
    int? tableNumber,
    bool clearTableNumber = false,
    List<OrderItem>? items,
    double? subtotal,
    double? tax,
    double? total,
    OrderStatus? status,
    PaymentStatus? paymentStatus,
    PaymentMethod? paymentMethod,
    String? notes,
    DateTime? updatedAt,
    bool? synced,
    bool? inventoryDeducted,
    String? createdBy,
    String? createdByName,
    String? updatedBy,
    String? updatedByName,
  }) {
    return Order(
      id: id,
      code: code,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      type: type ?? this.type,
      tableNumber: clearTableNumber ? null : (tableNumber ?? this.tableNumber),
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      tax: tax ?? this.tax,
      total: total ?? this.total,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source,
      synced: synced ?? this.synced,
      inventoryDeducted: inventoryDeducted ?? this.inventoryDeducted,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedByName: updatedByName ?? this.updatedByName,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'type': type.name,
        'tableNumber': tableNumber,
        'items': items.map((item) => item.toJson()).toList(),
        'subtotal': subtotal,
        'tax': tax,
        'total': total,
        'status': status.name,
        'paymentStatus': paymentStatus.name,
        'paymentMethod': paymentMethod.name,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'source': source,
        'synced': synced,
        'inventoryDeducted': inventoryDeducted,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'updatedBy': updatedBy,
        'updatedByName': updatedByName,
      };

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as String? ?? '',
        code: json['code'] as String? ?? '',
        customerName: json['customerName'] as String? ?? '',
        customerPhone: json['customerPhone'] as String? ?? '',
        type: OrderType.fromName(json['type'] as String?),
        tableNumber: (json['tableNumber'] as num?)?.toInt(),
        items: (json['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(OrderItem.fromJson)
            .toList(),
        subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
        tax: (json['tax'] as num?)?.toDouble() ?? 0,
        total: (json['total'] as num?)?.toDouble() ?? 0,
        status: OrderStatus.fromName(json['status'] as String?),
        paymentStatus: PaymentStatus.fromName(json['paymentStatus'] as String?),
        paymentMethod: PaymentMethod.fromName(json['paymentMethod'] as String?),
        notes: json['notes'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        source: json['source'] as String? ?? 'app',
        synced: json['synced'] as bool? ?? true,
        inventoryDeducted: json['inventoryDeducted'] as bool? ?? false,
        createdBy: json['createdBy'] as String?,
        createdByName: json['createdByName'] as String?,
        updatedBy: json['updatedBy'] as String?,
        updatedByName: json['updatedByName'] as String?,
      );
}

class CartLine {
  const CartLine({
    required this.menuItemId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.emoji,
  });

  final String menuItemId;
  final String name;
  final double price;
  final int quantity;
  final String emoji;

  double get total => price * quantity;

  CartLine copyWith({int? quantity}) => CartLine(
        menuItemId: menuItemId,
        name: name,
        price: price,
        quantity: quantity ?? this.quantity,
        emoji: emoji,
      );
}
