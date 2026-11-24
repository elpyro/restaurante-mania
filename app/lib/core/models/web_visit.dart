class WebVisit {
  const WebVisit({
    required this.id,
    this.visitorId = '',
    required this.occurredAt,
    required this.dayKey,
    required this.registered,
    required this.customerName,
    required this.customerPhone,
    required this.normalizedPhone,
    required this.referenceLabel,
    required this.referenceUrl,
    required this.referrer,
  });

  final String id;
  final String visitorId; // identidad local/teléfono del cliente en la web
  final DateTime occurredAt;
  final String dayKey; // yyyy-MM-dd (America/Bogota)
  final bool registered;
  final String customerName;
  final String customerPhone;
  final String normalizedPhone;
  final String referenceLabel;
  final String referenceUrl;
  final String referrer;

  String get displayName {
    final name = customerName.trim();
    if (registered && name.isNotEmpty) return name;
    return 'Cliente anónimo';
  }

  String get safeReferenceUrl {
    final uri = Uri.tryParse(referenceUrl);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return uri.toString();
    }
    return '';
  }

  /// Clave estable para deduplicar visitas del mismo cliente en un día.
  String get dedupeKey {
    final identity = visitorId.trim().isNotEmpty
        ? visitorId.trim()
        : (registered && normalizedPhone.trim().isNotEmpty
            ? 'phone:${normalizedPhone.trim()}'
            : 'id:$id');
    return '$dayKey|$identity';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'visitorId': visitorId,
        'occurredAt': occurredAt.toIso8601String(),
        'dayKey': dayKey,
        'registered': registered,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'normalizedPhone': normalizedPhone,
        'referenceLabel': referenceLabel,
        'referenceUrl': referenceUrl,
        'referrer': referrer,
      };

  factory WebVisit.fromJson(Map<String, dynamic> json) {
    final occurredAt = DateTime.tryParse(
          json['occurredAt'] as String? ?? '',
        ) ??
        DateTime.now();
    final referenceUrl = json['referenceUrl'] as String? ?? '';
    var label = json['referenceLabel'] as String? ?? '';
    if (label.trim().isEmpty) {
      final uri = Uri.tryParse(referenceUrl);
      label = uri == null
          ? '/'
          : '${uri.path.isEmpty ? '/' : uri.path}${uri.query.isEmpty ? '' : '?${uri.query}'}';
    }
    return WebVisit(
      id: json['id'] as String? ?? '',
      visitorId: json['visitorId'] as String? ?? '',
      occurredAt: occurredAt,
      dayKey: json['dayKey'] as String? ?? _dayKeyFrom(occurredAt),
      registered: json['registered'] is bool
          ? json['registered'] as bool
          : json['registered'] == 'true' ||
              (json['customerName'] as String? ?? '').trim().isNotEmpty,
      customerName: json['customerName'] as String? ?? '',
      customerPhone: json['customerPhone'] as String? ?? '',
      normalizedPhone: json['normalizedPhone'] as String? ?? '',
      referenceLabel: label,
      referenceUrl: referenceUrl,
      referrer: json['referrer'] as String? ?? '',
    );
  }

  static String _dayKeyFrom(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
