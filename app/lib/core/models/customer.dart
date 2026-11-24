import 'order.dart';

class CustomerRecord {
  const CustomerRecord({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.tags,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.lastOrderAt,
    required this.orderCount,
    required this.totalSpent,
    required this.lastType,
    this.addresses = const [],
    this.visitCount = 0,
    this.visitHistory = const {},
  });

  final String id;
  final String name;
  final String phone;
  final String address;
  final List<String> tags;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastOrderAt;
  final int orderCount;
  final double totalSpent;
  final OrderType lastType;
  final List<String> addresses;
  final int visitCount;
  final Map<String, int> visitHistory; // yyyy-MM-dd -> count

  String get normalizedPhone => phone.replaceAll(RegExp(r'\D'), '');

  bool get hasPhone => normalizedPhone.length >= 7;

  CustomerRecord copyWith({
    String? name,
    String? phone,
    String? address,
    List<String>? tags,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastOrderAt,
    int? orderCount,
    double? totalSpent,
    OrderType? lastType,
    List<String>? addresses,
    int? visitCount,
    Map<String, int>? visitHistory,
  }) {
    return CustomerRecord(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastOrderAt: lastOrderAt ?? this.lastOrderAt,
      orderCount: orderCount ?? this.orderCount,
      totalSpent: totalSpent ?? this.totalSpent,
      lastType: lastType ?? this.lastType,
      addresses: addresses ?? this.addresses,
      visitCount: visitCount ?? this.visitCount,
      visitHistory: visitHistory ?? this.visitHistory,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'tags': tags,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'lastOrderAt': lastOrderAt.toIso8601String(),
        'orderCount': orderCount,
        'totalSpent': totalSpent,
        'lastType': lastType.name,
        'addresses': addresses,
        'visitCount': visitCount,
        'visitHistory': visitHistory,
      };

  factory CustomerRecord.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(String key, DateTime fallback) {
      final raw = json[key];
      if (raw is String) return DateTime.tryParse(raw) ?? fallback;
      return fallback;
    }

    final now = DateTime.now();
    final rawHistory = json['visitHistory'];
    final visitHistory = <String, int>{};
    if (rawHistory is Map) {
      for (final entry in rawHistory.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is num) visitHistory[key] = value.toInt();
      }
    }
    final addresses = (json['addresses'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final visitCount = (json['visitCount'] as num?)?.toInt() ??
        visitHistory.values.fold<int>(0, (s, v) => s + v);
    return CustomerRecord(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      address: json['address'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      notes: json['notes'] as String? ?? '',
      createdAt: parseDate('createdAt', now),
      updatedAt: parseDate('updatedAt', now),
      lastOrderAt: parseDate('lastOrderAt', now),
      orderCount: (json['orderCount'] as num?)?.toInt() ?? 0,
      totalSpent: (json['totalSpent'] as num?)?.toDouble() ?? 0,
      lastType: OrderType.values.firstWhere(
        (t) => t.name == json['lastType'],
        orElse: () => OrderType.pickup,
      ),
      addresses: addresses,
      visitCount: visitCount,
      visitHistory: visitHistory,
    );
  }
}
