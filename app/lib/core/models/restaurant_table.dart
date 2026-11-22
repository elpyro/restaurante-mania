enum TableStatus {
  libre('Libre'),
  ocupada('Ocupada'),
  esperandoPedido('Esperando pedido'),
  pidiendoCuenta('Pidiendo cuenta');

  const TableStatus(this.label);

  final String label;

  static TableStatus fromName(String? value) => TableStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => TableStatus.libre,
      );
}

class RestaurantTable {
  const RestaurantTable({
    required this.id,
    required this.number,
    required this.status,
    required this.capacity,
    required this.currentOrderId,
  });

  final String id;
  final int number;
  final TableStatus status;
  final int capacity;
  final String? currentOrderId;

  RestaurantTable copyWith({
    TableStatus? status,
    String? currentOrderId,
    bool clearOrder = false,
  }) {
    return RestaurantTable(
      id: id,
      number: number,
      status: status ?? this.status,
      capacity: capacity,
      currentOrderId:
          clearOrder ? null : (currentOrderId ?? this.currentOrderId),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'status': status.name,
        'capacity': capacity,
        'currentOrderId': currentOrderId,
      };

  factory RestaurantTable.fromJson(Map<String, dynamic> json) =>
      RestaurantTable(
        id: json['id'] as String? ?? '',
        number: (json['number'] as num?)?.toInt() ?? 0,
        status: TableStatus.fromName(json['status'] as String?),
        capacity: (json['capacity'] as num?)?.toInt() ?? 4,
        currentOrderId: json['currentOrderId'] as String?,
      );
}
