enum OrderStatus {
  pending('Pendiente'),
  confirmed('Confirmado'),
  preparing('En preparación'),
  ready('Listo'),
  sent('Enviado'),
  delivered('Entregado'),
  cancelled('Cancelado');

  const OrderStatus(this.label);

  final String label;

  static OrderStatus fromName(String? value) => OrderStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => OrderStatus.pending,
      );

  bool get isActive =>
      this != OrderStatus.delivered &&
      this != OrderStatus.sent &&
      this != OrderStatus.cancelled;

  OrderStatus? get next => switch (this) {
        OrderStatus.pending => OrderStatus.confirmed,
        OrderStatus.confirmed => OrderStatus.preparing,
        OrderStatus.preparing => OrderStatus.ready,
        OrderStatus.ready => OrderStatus.delivered,
        OrderStatus.sent ||
        OrderStatus.delivered ||
        OrderStatus.cancelled =>
          null,
      };

  OrderStatus? nextFor(OrderType type) => switch (this) {
        OrderStatus.pending => OrderStatus.confirmed,
        OrderStatus.confirmed => OrderStatus.preparing,
        OrderStatus.preparing => OrderStatus.ready,
        OrderStatus.ready =>
          type == OrderType.delivery ? OrderStatus.sent : OrderStatus.delivered,
        OrderStatus.sent ||
        OrderStatus.delivered ||
        OrderStatus.cancelled =>
          null,
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

class OrderPayment {
  const OrderPayment({
    required this.method,
    required this.amount,
    this.note = '',
  });

  final PaymentMethod method;
  final double amount;
  final String note;

  Map<String, dynamic> toJson() => {
        'method': method.name,
        'amount': amount,
        'note': note,
      };

  factory OrderPayment.fromJson(Map<String, dynamic> json) => OrderPayment(
        method: PaymentMethod.fromName(json['method'] as String?),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        note: json['note'] as String? ?? '',
      );
}

class OrderAuditEntry {
  const OrderAuditEntry({
    required this.action,
    required this.timestamp,
    this.actorId,
    this.actorName,
    this.detail = '',
  });

  final String action;
  final DateTime timestamp;
  final String? actorId;
  final String? actorName;
  final String detail;

  Map<String, dynamic> toJson() => {
        'action': action,
        'timestamp': timestamp.toIso8601String(),
        'actorId': actorId,
        'actorName': actorName,
        'detail': detail,
      };

  factory OrderAuditEntry.fromJson(Map<String, dynamic> json) =>
      OrderAuditEntry(
        action: json['action'] as String? ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        actorId: json['actorId'] as String?,
        actorName: json['actorName'] as String?,
        detail: json['detail'] as String? ?? '',
      );
}

class OrderItem {
  const OrderItem({
    required this.menuItemId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.emoji,
    this.imageUrl = '',
  });

  final String menuItemId;
  final String name;
  final double price;
  final int quantity;
  final String emoji;
  final String imageUrl;

  double get subtotal => price * quantity;

  Map<String, dynamic> toJson() => {
        'menuItemId': menuItemId,
        'name': name,
        'price': price,
        'quantity': quantity,
        'emoji': emoji,
        'imageUrl': imageUrl,
      };

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        menuItemId: json['menuItemId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        emoji: json['emoji'] as String? ?? '🍽️',
        imageUrl: json['imageUrl'] as String? ?? '',
      );
}

class Order {
  const Order({
    required this.id,
    required this.code,
    required this.customerName,
    required this.customerPhone,
    this.deliveryAddress = '',
    required this.type,
    required this.tableNumber,
    required this.items,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.status,
    required this.paymentStatus,
    required this.paymentMethod,
    this.payments = const [],
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
    this.auditLog = const [],
  });

  final String id;
  final String code;
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final OrderType type;
  final int? tableNumber;
  final List<OrderItem> items;
  final double subtotal;
  final double tax;
  final double total;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final PaymentMethod paymentMethod;
  final List<OrderPayment> payments;
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
  final List<OrderAuditEntry> auditLog;

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  Order copyWith({
    String? customerName,
    String? customerPhone,
    String? deliveryAddress,
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
    List<OrderPayment>? payments,
    String? notes,
    DateTime? updatedAt,
    bool? synced,
    bool? inventoryDeducted,
    String? createdBy,
    String? createdByName,
    String? updatedBy,
    String? updatedByName,
    List<OrderAuditEntry>? auditLog,
  }) {
    return Order(
      id: id,
      code: code,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      type: type ?? this.type,
      tableNumber: clearTableNumber ? null : (tableNumber ?? this.tableNumber),
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      tax: tax ?? this.tax,
      total: total ?? this.total,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      payments: payments ?? this.payments,
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
      auditLog: auditLog ?? this.auditLog,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'deliveryAddress': deliveryAddress,
        'type': type.name,
        'tableNumber': tableNumber,
        'items': items.map((item) => item.toJson()).toList(),
        'subtotal': subtotal,
        'tax': tax,
        'total': total,
        'status': status.name,
        'paymentStatus': paymentStatus.name,
        'paymentMethod': paymentMethod.name,
        'payments': payments.map((p) => p.toJson()).toList(),
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
        'auditLog': auditLog.map((e) => e.toJson()).toList(),
      };

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as String? ?? '',
        code: json['code'] as String? ?? '',
        customerName: json['customerName'] as String? ?? '',
        customerPhone: json['customerPhone'] as String? ?? '',
        deliveryAddress: json['deliveryAddress'] as String? ?? '',
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
        payments: (json['payments'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(OrderPayment.fromJson)
            .toList(),
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
        auditLog: (json['auditLog'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(OrderAuditEntry.fromJson)
            .toList(),
      );
}

class CartLine {
  const CartLine({
    required this.menuItemId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.emoji,
    this.imageUrl = '',
  });

  final String menuItemId;
  final String name;
  final double price;
  final int quantity;
  final String emoji;
  final String imageUrl;

  double get total => price * quantity;

  CartLine copyWith({int? quantity}) => CartLine(
        menuItemId: menuItemId,
        name: name,
        price: price,
        quantity: quantity ?? this.quantity,
        emoji: emoji,
        imageUrl: imageUrl,
      );
}
