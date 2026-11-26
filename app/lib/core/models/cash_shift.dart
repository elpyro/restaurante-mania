import 'order.dart';

/// Turno de caja. Los totales son una foto de los pedidos cobrados en el
/// periodo; los contadores vivos se recalculan desde los pedidos, no se guardan
/// como números sueltos.
class CashShift {
  const CashShift({
    required this.id,
    required this.label,
    required this.openedAt,
    required this.openedBy,
    required this.openedByName,
    this.closedAt,
    this.closedBy,
    this.closedByName,
    this.orderCount = 0,
    this.total = 0,
    this.totalsByPaymentMethod = const {},
    this.closingAmount,
    this.notes = '',
    this.status = 'open',
  });

  final String id;
  final String label;
  final DateTime openedAt;
  final String? openedBy;
  final String openedByName;
  final DateTime? closedAt;
  final String? closedBy;
  final String? closedByName;
  final int orderCount;
  final double total;
  final Map<PaymentMethod, double> totalsByPaymentMethod;
  final double? closingAmount;
  final String notes;

  /// `'open'` o `'closed'`. Se guarda como texto para compartir el mismo
  /// documento con la web sin convertir enums en cada extremo.
  final String status;

  bool get isOpen => status != 'closed';
  bool get isClosed => status == 'closed';

  double get expectedCash => totalsByPaymentMethod[PaymentMethod.cash] ?? 0;

  double? get difference =>
      closingAmount == null ? null : closingAmount! - expectedCash;

  CashShift copyWith({
    String? label,
    DateTime? closedAt,
    String? closedBy,
    String? closedByName,
    int? orderCount,
    double? total,
    Map<PaymentMethod, double>? totalsByPaymentMethod,
    double? closingAmount,
    String? notes,
    String? status,
  }) {
    return CashShift(
      id: id,
      label: label ?? this.label,
      openedAt: openedAt,
      openedBy: openedBy,
      openedByName: openedByName,
      closedAt: closedAt ?? this.closedAt,
      closedBy: closedBy ?? this.closedBy,
      closedByName: closedByName ?? this.closedByName,
      orderCount: orderCount ?? this.orderCount,
      total: total ?? this.total,
      totalsByPaymentMethod:
          totalsByPaymentMethod ?? this.totalsByPaymentMethod,
      closingAmount: closingAmount ?? this.closingAmount,
      notes: notes ?? this.notes,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'openedAt': openedAt.toIso8601String(),
        'openedBy': openedBy,
        'openedByName': openedByName,
        'closedAt': closedAt?.toIso8601String(),
        'closedBy': closedBy,
        'closedByName': closedByName,
        'orderCount': orderCount,
        'total': total,
        'totalsByPaymentMethod': {
          for (final entry in totalsByPaymentMethod.entries)
            entry.key.name: entry.value,
        },
        'closingAmount': closingAmount,
        'notes': notes,
        'status': status,
      };

  factory CashShift.fromJson(Map<String, dynamic> json) {
    final rawTotals = json['totalsByPaymentMethod'];
    final totals = <PaymentMethod, double>{};
    if (rawTotals is Map<String, dynamic>) {
      for (final entry in rawTotals.entries) {
        if (entry.value is num) {
          totals[PaymentMethod.fromName(entry.key)] =
              (entry.value as num).toDouble();
        }
      }
    }
    return CashShift(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      openedAt:
          DateTime.tryParse(json['openedAt'] as String? ?? '') ?? DateTime.now(),
      openedBy: json['openedBy'] as String?,
      openedByName: json['openedByName'] as String? ?? 'Sistema',
      closedAt: DateTime.tryParse(json['closedAt'] as String? ?? ''),
      closedBy: json['closedBy'] as String?,
      closedByName: json['closedByName'] as String?,
      orderCount: (json['orderCount'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      totalsByPaymentMethod: totals,
      closingAmount: (json['closingAmount'] as num?)?.toDouble(),
      notes: json['notes'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
    );
  }
}
