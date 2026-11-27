import 'dart:convert';

/// La web publica estos textos en metadatos y `/llms.txt`.
String cleanAiText(String? value) {
  final text = value?.trim() ?? '';
  return text.replaceAll(RegExp(r'\s+'), ' ');
}

/// Lee `aiSearch` del cuerpo de la web y conserva los valores locales ausentes.
Map<String, String> aiSearchFromJson(
  Map<String, dynamic> json, {
  Map<String, String>? fallback,
}) {
  final raw = json['aiSearch'];
  final nested = raw is Map ? raw : <String, dynamic>{};
  String text(String key) {
    final value = nested[key] ?? json[key];
    if (value is String) return cleanAiText(value);
    return fallback?[key] ?? '';
  }

  return {
    'description': text('description'),
    'keywords': text('keywords'),
    'serviceArea': text('serviceArea'),
    'highlights': text('highlights'),
  };
}

/// Datos de contacto, entrega y pago que se publican en la web.
class RestaurantSettings {
  const RestaurantSettings({
    required this.name,
    required this.isOpen,
    required this.hours,
    required this.whatsapp,
    required this.address,
    required this.currency,
    this.city = 'Medellín',
    this.countryCode = '+57',
    this.phone = '300 123 4567',
    this.showOrderTypeOptions = true,
    this.tableCount = 0,
    this.deliveryOptions = const {
      'pickup': true,
      'delivery': true,
      'table': true,
    },
    this.paymentMethods = const ['cash', 'card', 'nequi', 'daviplata'],
    this.paymentMethodLabels = const {},
    this.timeZone = defaultTimeZone,
    this.openingDays = defaultOpeningDays,
    this.openTime = defaultOpenTime,
    this.closeTime = defaultCloseTime,
    this.aiDescription = '',
    this.aiKeywords = '',
    this.aiServiceArea = '',
    this.aiHighlights = '',
  });

  final String name;
  final bool isOpen;
  final String hours;
  final String whatsapp;
  final String address;
  final String currency;
  final String city;
  final String countryCode;
  final String phone;
  final bool showOrderTypeOptions;
  /// Cantidad de mesas con las que opera el restaurante. `0` = sin mesas.
  final int tableCount;
  final Map<String, bool> deliveryOptions;
  final List<String> paymentMethods;
  final Map<String, String> paymentMethodLabels;
  /// Identificador IANA (por ejemplo `America/Bogota` o `Europe/Madrid`).
  final String timeZone;
  /// Días activos en orden de lunes a domingo.
  final List<String> openingDays;
  final String openTime;
  final String closeTime;
  final String aiDescription;
  final String aiKeywords;
  final String aiServiceArea;
  final String aiHighlights;

  static const defaults = RestaurantSettings(
    name: 'Restaurante Manía',
    isOpen: true,
    hours: '11:00 - 22:00',
    whatsapp: '+573001234567',
    address: 'Calle 10 # 43-12, Medellín',
    city: 'Medellín',
    currency: 'COP',
    countryCode: '+57',
    phone: '300 123 4567',
  );

  /// Plantilla inicial de un restaurante nuevo. Sin ciudad, país ni platos
  /// típicos: el dueño la reemplaza desde el POS o el panel web.
  static const generic = RestaurantSettings(
    name: 'Restaurante de ejemplo',
    isOpen: true,
    hours: 'Lun–Sáb 11:30–20:30',
    whatsapp: '+000000000000',
    address: 'Dirección por definir',
    city: 'Ciudad por definir',
    currency: 'USD',
    countryCode: '+00',
    phone: '000 000 0000',
    paymentMethods: ['cash', 'card'],
    paymentMethodLabels: {
      'cash': 'Efectivo',
      'card': 'Tarjeta',
    },
    aiDescription:
        'Restaurante con pedidos en línea, menú actualizado y atención cercana.',
    aiKeywords: 'restaurante, menú, pedidos en línea, comida',
    aiServiceArea: 'Zona de atención por definir',
    aiHighlights:
        'Platillos preparados al momento, pedidos sencillos, servicio amable',
  );

  static const defaultTimeZone = 'America/Bogota';
  static const defaultOpeningDays = [
    'mon',
    'tue',
    'wed',
    'thu',
    'fri',
    'sat',
  ];
  static const openingDayKeys = [
    'mon',
    'tue',
    'wed',
    'thu',
    'fri',
    'sat',
    'sun',
  ];
  static const openingDayLabels = <String, String>{
    'mon': 'Lun',
    'tue': 'Mar',
    'wed': 'Mié',
    'thu': 'Jue',
    'fri': 'Vie',
    'sat': 'Sáb',
    'sun': 'Dom',
  };
  static const defaultOpenTime = '11:30';
  static const defaultCloseTime = '20:30';
  static const suggestionsTimeZone = <String>[
    'America/Bogota',
    'America/Mexico_City',
    'America/Argentina/Buenos_Aires',
    'Europe/Madrid',
    'UTC',
  ];

  static const availablePaymentMethods = ['cash', 'card', 'nequi', 'daviplata'];
  static const aiDescriptionMaxLength = 500;
  static const aiKeywordsMaxLength = 300;
  static const aiServiceAreaMaxLength = 120;
  static const aiHighlightsMaxLength = 300;
  static const defaultPaymentLabels = <String, String>{
    'cash': 'Efectivo',
    'card': 'Tarjeta',
    'nequi': 'Nequi',
    'daviplata': 'Daviplata',
  };

  /// Número compacto listo para `wa.me` y para el campo whatsapp de la web.
  static String compactNumber(String countryCode, String phone) {
    final code = countryCode.replaceAll(RegExp(r'\D'), '');
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return '+$code$digits';
  }

  /// Separa el indicativo de un número guardado por versiones anteriores.
  static Map<String, String> splitPhone(String rawPhone, String rawCode) {
    var code = rawCode.trim().isEmpty ? '+57' : rawCode.trim();
    var phone = rawPhone.trim();
    if (phone.startsWith(code) && phone.length > code.length) {
      phone = phone.substring(code.length).trim();
    } else if (phone.startsWith('+')) {
      final match = RegExp(r'^\+\d{1,4}\s*').firstMatch(phone);
      if (match != null) {
        code = match.group(0)!.trim();
        phone = phone.substring(match.end).trim();
      }
    }
    if (phone.isEmpty) phone = defaults.phone;
    if (!RegExp(r'^\+\d{1,4}$').hasMatch(code)) code = '+57';
    return {'countryCode': code, 'phone': phone};
  }

  /// Cantidad de mesas válida para el POS (0 = sin mesas).
  static const maxTableCount = 200;

  static int cleanTableCount(Object? value) {
    if (value is int) return value.clamp(0, maxTableCount);
    if (value is num) return value.round().clamp(0, maxTableCount);
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed.clamp(0, maxTableCount);
    }
    return 0;
  }

  static bool isValidTimeOfDay(String value) =>
      RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value.trim());

  static String cleanTimeOfDay(Object? value, String fallback) =>
      value is String && isValidTimeOfDay(value) ? value.trim() : fallback;

  static const _timeZoneRoots = <String>{
    'America',
    'Europe',
    'Asia',
    'Africa',
    'Australia',
    'Pacific',
    'Atlantic',
    'Indian',
    'Antarctica',
    'Arctic',
    'Etc',
  };

  static bool isValidTimeZone(String value) {
    final zone = value.trim();
    if (zone.isEmpty || zone.length > 64) return false;
    if (zone == 'UTC') return true;
    final root = zone.split('/').first;
    return _timeZoneRoots.contains(root) &&
        zone.contains('/') &&
        RegExp(r'^[A-Za-z][A-Za-z0-9_+\-/]*$').hasMatch(zone);
  }

  static String cleanTimeZone(Object? value) =>
      value is String && isValidTimeZone(value) ? value.trim() : defaultTimeZone;

  static List<String> cleanOpeningDays(Object? value) {
    if (value is! List) return List<String>.from(defaultOpeningDays);
    final days = value
        .whereType<String>()
        .where(openingDayKeys.contains)
        .toSet()
        .toList();
    if (days.isEmpty) return List<String>.from(defaultOpeningDays);
    return openingDayKeys.where(days.contains).toList();
  }

  /// Versión legible del horario, igual a la que deriva la web.
  static String scheduleHours({
    required List<String> days,
    required String openTime,
    required String closeTime,
  }) {
    if (days.isEmpty) return 'Cerrado';
    final ordered = cleanOpeningDays(days);
    final label = ordered.length == openingDayKeys.length
        ? 'Todos los días'
        : ordered.length > 1 &&
                openingDayKeys.indexOf(ordered.last) -
                        openingDayKeys.indexOf(ordered.first) ==
                    ordered.length - 1
            ? '${openingDayLabels[ordered.first]}–${openingDayLabels[ordered.last]}'
            : ordered.map((day) => openingDayLabels[day] ?? day).join(', ');
    return '$label $openTime–$closeTime';
  }

  String get scheduleHoursText => scheduleHours(
        days: openingDays,
        openTime: openTime,
        closeTime: closeTime,
      );

  RestaurantSettings copyWith({
    String? name,
    bool? isOpen,
    String? hours,
    String? whatsapp,
    String? address,
    String? currency,
    String? city,
    String? countryCode,
    String? phone,
    bool? showOrderTypeOptions,
    int? tableCount,
    Map<String, bool>? deliveryOptions,
    List<String>? paymentMethods,
    Map<String, String>? paymentMethodLabels,
    String? timeZone,
    List<String>? openingDays,
    String? openTime,
    String? closeTime,
    String? aiDescription,
    String? aiKeywords,
    String? aiServiceArea,
    String? aiHighlights,
  }) {
    return RestaurantSettings(
      name: name ?? this.name,
      isOpen: isOpen ?? this.isOpen,
      hours: hours ?? this.hours,
      whatsapp: whatsapp ?? this.whatsapp,
      address: address ?? this.address,
      currency: currency ?? this.currency,
      city: city ?? this.city,
      countryCode: countryCode ?? this.countryCode,
      phone: phone ?? this.phone,
      showOrderTypeOptions:
          showOrderTypeOptions ?? this.showOrderTypeOptions,
      tableCount: tableCount ?? this.tableCount,
      deliveryOptions: deliveryOptions ?? this.deliveryOptions,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      paymentMethodLabels: paymentMethodLabels ?? this.paymentMethodLabels,
      timeZone: timeZone ?? this.timeZone,
      openingDays: openingDays ?? this.openingDays,
      openTime: openTime ?? this.openTime,
      closeTime: closeTime ?? this.closeTime,
      aiDescription: aiDescription ?? this.aiDescription,
      aiKeywords: aiKeywords ?? this.aiKeywords,
      aiServiceArea: aiServiceArea ?? this.aiServiceArea,
      aiHighlights: aiHighlights ?? this.aiHighlights,
    );
  }

  Map<String, String> get aiSearch => {
        'description': cleanAiText(aiDescription),
        'keywords': cleanAiText(aiKeywords),
        'serviceArea': cleanAiText(aiServiceArea),
        'highlights': cleanAiText(aiHighlights),
      };

  Map<String, dynamic> toJson() => {
        'name': name,
        'isOpen': isOpen,
        'hours': hours,
        'whatsapp': whatsapp,
        'address': address,
        'currency': currency,
        'city': city,
        'countryCode': countryCode,
        'phone': phone,
        'showOrderTypeOptions': showOrderTypeOptions,
        'tableCount': tableCount,
        'deliveryOptions': deliveryOptions,
        'paymentMethods': paymentMethods,
        'paymentMethodLabels': paymentMethodLabels,
        'timeZone': timeZone,
        'openingDays': openingDays,
        'openTime': openTime,
        'closeTime': closeTime,
        'aiSearch': aiSearch,
      };

  /// Cuerpo aceptado por `PATCH /api/restaurant/config`.
  Map<String, dynamic> toWebConfigPatch() => {
        'name': name,
        'hours': scheduleHoursText,
        'isOpen': isOpen,
        'timeZone': timeZone,
        'openingDays': openingDays,
        'openTime': openTime,
        'closeTime': closeTime,
        'whatsapp': compactNumber(countryCode, phone),
        'address': address,
        'city': city,
        'countryCode': countryCode,
        'phone': phone,
        'currency': currency,
        'showOrderTypeOptions': showOrderTypeOptions,
        'tableCount': tableCount,
        'deliveryOptions': deliveryOptions,
        'paymentMethods': paymentMethods,
        'paymentMethodLabels': paymentMethodLabels,
        'aiSearch': aiSearch,
      };

  factory RestaurantSettings.fromJson(Map<String, dynamic> json) {
    final split = splitPhone(
      (json['phone'] as String?) ?? '',
      (json['countryCode'] as String?) ?? '',
    );
    final countryCode = split['countryCode']!;
    final phone = split['phone']!;
    final rawWhatsapp = json['whatsapp'] as String?;
    final whatsapp = rawWhatsapp == null || rawWhatsapp.isEmpty
        ? compactNumber(countryCode, phone)
        : rawWhatsapp;
    final rawDelivery = json['deliveryOptions'];
    final delivery = <String, bool>{};
    if (rawDelivery is Map) {
      for (final entry in defaults.deliveryOptions.entries) {
        delivery[entry.key] = rawDelivery[entry.key] is bool
            ? rawDelivery[entry.key] as bool
            : entry.value;
      }
    }
    final rawMethods = json['paymentMethods'];
    final methods = rawMethods is List
        ? rawMethods
            .whereType<String>()
            .where(availablePaymentMethods.contains)
            .toList()
        : List<String>.from(defaults.paymentMethods);
    final rawLabels = json['paymentMethodLabels'];
    final labels = <String, String>{};
    if (rawLabels is Map) {
      for (final entry in rawLabels.entries) {
        if (entry.value is String && entry.value.trim().isNotEmpty) {
          labels[entry.key.toString()] = entry.value.trim();
        }
      }
    }
    final search = aiSearchFromJson(json);
    final timeZone = cleanTimeZone(json['timeZone']);
    final openingDays = cleanOpeningDays(json['openingDays']);
    final openTime = cleanTimeOfDay(json['openTime'], defaults.openTime);
    final closeTime = cleanTimeOfDay(json['closeTime'], defaults.closeTime);
    final derivedHours = scheduleHours(
      days: openingDays,
      openTime: openTime,
      closeTime: closeTime,
    );
    return RestaurantSettings(
      name: json['name'] as String? ?? defaults.name,
      isOpen: json['isOpen'] as bool? ?? defaults.isOpen,
      hours: json['hours'] as String? ?? derivedHours,
      whatsapp: whatsapp,
      address: json['address'] as String? ?? defaults.address,
      currency: json['currency'] as String? ?? defaults.currency,
      city: json['city'] as String? ?? defaults.city,
      countryCode: countryCode,
      phone: phone,
      showOrderTypeOptions: json['showOrderTypeOptions'] as bool? ?? true,
      tableCount: cleanTableCount(json['tableCount']),
      deliveryOptions: delivery.isEmpty ? defaults.deliveryOptions : delivery,
      paymentMethods: methods.isEmpty
          ? List<String>.from(defaults.paymentMethods)
          : methods,
      paymentMethodLabels: labels,
      timeZone: timeZone,
      openingDays: openingDays,
      openTime: openTime,
      closeTime: closeTime,
      aiDescription: search['description'] ?? '',
      aiKeywords: search['keywords'] ?? '',
      aiServiceArea: search['serviceArea'] ?? '',
      aiHighlights: search['highlights'] ?? '',
    );
  }

  /// Actualiza los datos publicables desde la respuesta pública de la web.
  static RestaurantSettings fromWebConfig(
    Map<String, dynamic> json,
    RestaurantSettings current,
  ) {
    final split = splitPhone(
      (json['phone'] as String?) ?? current.phone,
      (json['countryCode'] as String?) ?? current.countryCode,
    );
    final countryCode = split['countryCode']!;
    final phone = split['phone']!;
    final rawDelivery = json['deliveryOptions'];
    final delivery = <String, bool>{};
    if (rawDelivery is Map) {
      for (final entry in current.deliveryOptions.entries) {
        delivery[entry.key] = rawDelivery[entry.key] is bool
            ? rawDelivery[entry.key] as bool
            : entry.value;
      }
    }
    final rawMethods = json['paymentMethods'];
    final methods = rawMethods is List
        ? rawMethods
            .whereType<String>()
            .where(availablePaymentMethods.contains)
            .toList()
        : current.paymentMethods;
    final rawLabels = json['paymentMethodLabels'];
    final labels = <String, String>{};
    if (rawLabels is Map) {
      for (final entry in rawLabels.entries) {
        if (entry.value is String && entry.value.trim().isNotEmpty) {
          labels[entry.key.toString()] = entry.value.trim();
        }
      }
    }
    final search = aiSearchFromJson(json, fallback: current.aiSearch);
    final hasSchedule = json.containsKey('timeZone') ||
        json.containsKey('openingDays') ||
        json.containsKey('openTime') ||
        json.containsKey('closeTime');
    final timeZone = hasSchedule
        ? cleanTimeZone(json['timeZone'] ?? current.timeZone)
        : current.timeZone;
    final openingDays = hasSchedule
        ? cleanOpeningDays(json['openingDays'] ?? current.openingDays)
        : current.openingDays;
    final openTime = hasSchedule
        ? cleanTimeOfDay(json['openTime'], current.openTime)
        : current.openTime;
    final closeTime = hasSchedule
        ? cleanTimeOfDay(json['closeTime'], current.closeTime)
        : current.closeTime;
    return current.copyWith(
      name: json['name'] is String ? json['name'] as String : null,
      hours: json['hours'] is String
          ? json['hours'] as String
          : hasSchedule
              ? scheduleHours(
                  days: openingDays,
                  openTime: openTime,
                  closeTime: closeTime,
                )
              : null,
      isOpen: json['isOpen'] is bool ? json['isOpen'] as bool : null,
      whatsapp: json['whatsapp'] is String ? json['whatsapp'] as String : null,
      address: json['address'] is String ? json['address'] as String : null,
      currency: json['currency'] is String ? json['currency'] as String : null,
      city: json['city'] is String ? json['city'] as String : null,
      countryCode: countryCode,
      phone: phone,
      showOrderTypeOptions: json['showOrderTypeOptions'] is bool
          ? json['showOrderTypeOptions'] as bool
          : null,
      // La web no gestiona mesas, pero el documento de configuración sí
      // guarda la cantidad para que el POS las cree al sincronizar.
      tableCount: json.containsKey('tableCount')
          ? cleanTableCount(json['tableCount'])
          : null,
      deliveryOptions: delivery.isEmpty ? null : delivery,
      paymentMethods: methods.isEmpty ? null : methods,
      paymentMethodLabels: labels,
      timeZone: timeZone,
      openingDays: openingDays,
      openTime: openTime,
      closeTime: closeTime,
      aiDescription: search['description'] ?? '',
      aiKeywords: search['keywords'] ?? '',
      aiServiceArea: search['serviceArea'] ?? '',
      aiHighlights: search['highlights'] ?? '',
    );
  }

  String paymentLabel(String method) =>
      paymentMethodLabels[method] ?? defaultPaymentLabels[method] ?? method;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RestaurantSettings &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          isOpen == other.isOpen &&
          hours == other.hours &&
          whatsapp == other.whatsapp &&
          address == other.address &&
          currency == other.currency &&
          city == other.city &&
          countryCode == other.countryCode &&
          phone == other.phone &&
          showOrderTypeOptions == other.showOrderTypeOptions &&
          tableCount == other.tableCount &&
          jsonEncode(deliveryOptions) == jsonEncode(other.deliveryOptions) &&
          jsonEncode(paymentMethods) == jsonEncode(other.paymentMethods) &&
          jsonEncode(paymentMethodLabels) ==
              jsonEncode(other.paymentMethodLabels) &&
          timeZone == other.timeZone &&
          jsonEncode(openingDays) == jsonEncode(other.openingDays) &&
          openTime == other.openTime &&
          closeTime == other.closeTime &&
          aiDescription == other.aiDescription &&
          aiKeywords == other.aiKeywords &&
          aiServiceArea == other.aiServiceArea &&
          aiHighlights == other.aiHighlights;

  @override
  int get hashCode => Object.hash(
        name,
        isOpen,
        hours,
        whatsapp,
        address,
        currency,
        city,
        countryCode,
        phone,
        showOrderTypeOptions,
        tableCount,
        jsonEncode(deliveryOptions),
        jsonEncode(paymentMethods),
        jsonEncode(paymentMethodLabels),
        timeZone,
        jsonEncode(openingDays),
        openTime,
        closeTime,
        Object.hash(aiDescription, aiKeywords, aiServiceArea, aiHighlights),
      );
}
