import 'dart:convert';

/// Indicativo telefónico de un país, tal como se elige al crear un restaurante.
class CountryDial {
  const CountryDial(this.code, this.name);

  final String code;
  final String name;

  String get label => '$name ($code)';

  @override
  String toString() => label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CountryDial && other.code == code && other.name == name;

  @override
  int get hashCode => Object.hash(code, name);
}

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
  /// Zonas IANA habituales para restaurantes en América, Europa, Asia,
  /// África y Oceanía. Se valida con [isValidTimeZone] antes de guardar.
  static const suggestionsTimeZone = <String>[
    'UTC',
    'Etc/GMT+12',
    'Etc/GMT+5',
    'America/Bogota',
    'America/Mexico_City',
    'America/Tijuana',
    'America/Monterrey',
    'America/Chihuahua',
    'America/Merida',
    'America/Cancun',
    'America/Guatemala',
    'America/El_Salvador',
    'America/Honduras',
    'America/Managua',
    'America/Costa_Rica',
    'America/Panama',
    'America/Havana',
    'America/Santo_Domingo',
    'America/Puerto_Rico',
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'America/Anchorage',
    'Pacific/Honolulu',
    'America/Toronto',
    'America/Vancouver',
    'America/Edmonton',
    'America/Winnipeg',
    'America/Halifax',
    'America/St_Johns',
    'America/Argentina/Buenos_Aires',
    'America/Argentina/Cordoba',
    'America/Santiago',
    'America/Lima',
    'America/Sao_Paulo',
    'America/Recife',
    'America/Montevideo',
    'America/Asuncion',
    'America/La_Paz',
    'America/Caracas',
    'America/Guayaquil',
    'America/Guyana',
    'America/Paramaribo',
    'America/Cayenne',
    'Atlantic/Reykjavik',
    'Atlantic/Azores',
    'Atlantic/Cape_Verde',
    'Atlantic/Madeira',
    'Europe/Madrid',
    'Europe/London',
    'Europe/Dublin',
    'Europe/Lisbon',
    'Europe/Paris',
    'Europe/Berlin',
    'Europe/Rome',
    'Europe/Amsterdam',
    'Europe/Brussels',
    'Europe/Vienna',
    'Europe/Zurich',
    'Europe/Stockholm',
    'Europe/Oslo',
    'Europe/Copenhagen',
    'Europe/Helsinki',
    'Europe/Warsaw',
    'Europe/Prague',
    'Europe/Budapest',
    'Europe/Bucharest',
    'Europe/Sofia',
    'Europe/Athens',
    'Europe/Istanbul',
    'Europe/Kyiv',
    'Europe/Moscow',
    'Europe/Belgrade',
    'Europe/Zagreb',
    'Europe/Ljubljana',
    'Europe/Bratislava',
    'Europe/Vilnius',
    'Europe/Riga',
    'Europe/Tallinn',
    'Asia/Dubai',
    'Asia/Riyadh',
    'Asia/Qatar',
    'Asia/Bahrain',
    'Asia/Kuwait',
    'Asia/Tehran',
    'Asia/Baghdad',
    'Asia/Jerusalem',
    'Asia/Amman',
    'Asia/Beirut',
    'Asia/Damascus',
    'Asia/Kolkata',
    'Asia/Karachi',
    'Asia/Dhaka',
    'Asia/Kathmandu',
    'Asia/Colombo',
    'Asia/Bangkok',
    'Asia/Jakarta',
    'Asia/Manila',
    'Asia/Ho_Chi_Minh',
    'Asia/Shanghai',
    'Asia/Hong_Kong',
    'Asia/Taipei',
    'Asia/Seoul',
    'Asia/Tokyo',
    'Asia/Singapore',
    'Asia/Kuala_Lumpur',
    'Asia/Yangon',
    'Asia/Almaty',
    'Asia/Tashkent',
    'Asia/Baku',
    'Asia/Tbilisi',
    'Asia/Yerevan',
    'Australia/Sydney',
    'Australia/Melbourne',
    'Australia/Brisbane',
    'Australia/Perth',
    'Australia/Adelaide',
    'Australia/Darwin',
    'Australia/Hobart',
    'Australia/Lord_Howe',
    'Pacific/Auckland',
    'Pacific/Fiji',
    'Pacific/Guam',
    'Pacific/Port_Moresby',
    'Pacific/Apia',
    'Pacific/Noumea',
    'Africa/Cairo',
    'Africa/Lagos',
    'Africa/Accra',
    'Africa/Johannesburg',
    'Africa/Casablanca',
    'Africa/Algiers',
    'Africa/Tunis',
    'Africa/Tripoli',
    'Africa/Nairobi',
    'Africa/Addis_Ababa',
    'Africa/Dar_es_Salaam',
    'Africa/Kampala',
    'Africa/Kinshasa',
    'Africa/Luanda',
    'Africa/Abidjan',
    'Africa/Dakar',
    'Africa/Bamako',
    'Africa/Ouagadougou',
    'Africa/Maputo',
    'Africa/Lusaka',
    'Africa/Harare',
    'Africa/Windhoek',
    'Africa/Gaborone',
    'Africa/Maseru',
    'Africa/Mbabane',
    'Africa/Asmara',
    'Africa/Mogadishu',
    'Africa/Djibouti',
  ];

  /// Indicativos de todos los países y territorios con código ITU asignado.
  /// Los que comparten prefijo (+1, +7, +44, …) aparecen como entradas
  /// independientes para que el usuario vea el país, no solo el número.
  static const supportedCountries = <CountryDial>[
    CountryDial('+1', 'Estados Unidos'),
    CountryDial('+1', 'Canadá'),
    CountryDial('+1', 'Anguila'),
    CountryDial('+1', 'Antigua y Barbuda'),
    CountryDial('+1', 'Bahamas'),
    CountryDial('+1', 'Barbados'),
    CountryDial('+1', 'Bermudas'),
    CountryDial('+1', 'Islas Vírgenes Británicas'),
    CountryDial('+1', 'Islas Caimán'),
    CountryDial('+1', 'Dominica'),
    CountryDial('+1', 'República Dominicana'),
    CountryDial('+1', 'Granada'),
    CountryDial('+1', 'Guam'),
    CountryDial('+1', 'Jamaica'),
    CountryDial('+1', 'Montserrat'),
    CountryDial('+1', 'Puerto Rico'),
    CountryDial('+1', 'San Cristóbal y Nieves'),
    CountryDial('+1', 'Santa Lucía'),
    CountryDial('+1', 'Trinidad y Tobago'),
    CountryDial('+1', 'Islas Turcas y Caicos'),
    CountryDial('+1', 'Islas Vírgenes de EE. UU.'),
    CountryDial('+7', 'Rusia'),
    CountryDial('+7', 'Kazajistán'),
    CountryDial('+20', 'Egipto'),
    CountryDial('+27', 'Sudáfrica'),
    CountryDial('+30', 'Grecia'),
    CountryDial('+31', 'Países Bajos'),
    CountryDial('+32', 'Bélgica'),
    CountryDial('+33', 'Francia'),
    CountryDial('+34', 'España'),
    CountryDial('+36', 'Hungría'),
    CountryDial('+39', 'Italia'),
    CountryDial('+40', 'Rumanía'),
    CountryDial('+41', 'Suiza'),
    CountryDial('+43', 'Austria'),
    CountryDial('+44', 'Reino Unido'),
    CountryDial('+44', 'Guernsey'),
    CountryDial('+44', 'Jersey'),
    CountryDial('+44', 'Isla de Man'),
    CountryDial('+45', 'Dinamarca'),
    CountryDial('+46', 'Suecia'),
    CountryDial('+47', 'Noruega'),
    CountryDial('+48', 'Polonia'),
    CountryDial('+49', 'Alemania'),
    CountryDial('+51', 'Perú'),
    CountryDial('+52', 'México'),
    CountryDial('+53', 'Cuba'),
    CountryDial('+54', 'Argentina'),
    CountryDial('+55', 'Brasil'),
    CountryDial('+56', 'Chile'),
    CountryDial('+57', 'Colombia'),
    CountryDial('+58', 'Venezuela'),
    CountryDial('+60', 'Malasia'),
    CountryDial('+61', 'Australia'),
    CountryDial('+61', 'Isla de Navidad'),
    CountryDial('+61', 'Islas Cocos'),
    CountryDial('+62', 'Indonesia'),
    CountryDial('+63', 'Filipinas'),
    CountryDial('+64', 'Nueva Zelanda'),
    CountryDial('+65', 'Singapur'),
    CountryDial('+66', 'Tailandia'),
    CountryDial('+81', 'Japón'),
    CountryDial('+82', 'Corea del Sur'),
    CountryDial('+84', 'Vietnam'),
    CountryDial('+86', 'China'),
    CountryDial('+90', 'Turquía'),
    CountryDial('+91', 'India'),
    CountryDial('+92', 'Pakistán'),
    CountryDial('+93', 'Afganistán'),
    CountryDial('+94', 'Sri Lanka'),
    CountryDial('+95', 'Birmania'),
    CountryDial('+98', 'Irán'),
    CountryDial('+211', 'Sudán del Sur'),
    CountryDial('+212', 'Marruecos'),
    CountryDial('+213', 'Argelia'),
    CountryDial('+216', 'Túnez'),
    CountryDial('+218', 'Libia'),
    CountryDial('+220', 'Gambia'),
    CountryDial('+221', 'Senegal'),
    CountryDial('+222', 'Mauritania'),
    CountryDial('+223', 'Malí'),
    CountryDial('+224', 'Guinea'),
    CountryDial('+225', 'Costa de Marfil'),
    CountryDial('+226', 'Burkina Faso'),
    CountryDial('+227', 'Níger'),
    CountryDial('+228', 'Togo'),
    CountryDial('+229', 'Benín'),
    CountryDial('+230', 'Mauricio'),
    CountryDial('+231', 'Liberia'),
    CountryDial('+232', 'Sierra Leona'),
    CountryDial('+233', 'Ghana'),
    CountryDial('+234', 'Nigeria'),
    CountryDial('+235', 'Chad'),
    CountryDial('+236', 'República Centroafricana'),
    CountryDial('+237', 'Camerún'),
    CountryDial('+238', 'Cabo Verde'),
    CountryDial('+239', 'Santo Tomé y Príncipe'),
    CountryDial('+240', 'Guinea Ecuatorial'),
    CountryDial('+241', 'Gabón'),
    CountryDial('+242', 'República del Congo'),
    CountryDial('+243', 'República Democrática del Congo'),
    CountryDial('+244', 'Angola'),
    CountryDial('+245', 'Guinea-Bisáu'),
    CountryDial('+246', 'Islas Seychelles'),
    CountryDial('+247', 'Isla Ascensión'),
    CountryDial('+248', 'Ruanda'),
    CountryDial('+249', 'Sudán'),
    CountryDial('+250', 'Eritrea'),
    CountryDial('+251', 'Etiopía'),
    CountryDial('+252', 'Somalia'),
    CountryDial('+253', 'Yibuti'),
    CountryDial('+254', 'Kenia'),
    CountryDial('+255', 'Tanzania'),
    CountryDial('+256', 'Uganda'),
    CountryDial('+257', 'Burundi'),
    CountryDial('+258', 'Mozambique'),
    CountryDial('+260', 'Zambia'),
    CountryDial('+261', 'Madagascar'),
    CountryDial('+262', 'Reunión y Mayotte'),
    CountryDial('+263', 'Zimbabue'),
    CountryDial('+264', 'Namibia'),
    CountryDial('+265', 'Malaui'),
    CountryDial('+266', 'Lesoto'),
    CountryDial('+267', 'Botsuana'),
    CountryDial('+268', 'Esuatini'),
    CountryDial('+269', 'Comoras'),
    CountryDial('+290', 'Santa Elena y Tristán de Acuña'),
    CountryDial('+291', 'Eritrea'),
    CountryDial('+297', 'Aruba'),
    CountryDial('+298', 'Islas Feroe'),
    CountryDial('+299', 'Groenlandia'),
    CountryDial('+350', 'Gibraltar'),
    CountryDial('+351', 'Portugal'),
    CountryDial('+352', 'Luxemburgo'),
    CountryDial('+353', 'Irlanda'),
    CountryDial('+354', 'Islandia'),
    CountryDial('+355', 'Albania'),
    CountryDial('+356', 'Malta'),
    CountryDial('+357', 'Chipre'),
    CountryDial('+358', 'Finlandia'),
    CountryDial('+359', 'Bulgaria'),
    CountryDial('+370', 'Lituania'),
    CountryDial('+371', 'Letonia'),
    CountryDial('+372', 'Estonia'),
    CountryDial('+373', 'Moldavia'),
    CountryDial('+374', 'Armenia'),
    CountryDial('+375', 'Bielorrusia'),
    CountryDial('+376', 'Andorra'),
    CountryDial('+377', 'Mónaco'),
    CountryDial('+378', 'San Marino'),
    CountryDial('+379', 'Ciudad del Vaticano'),
    CountryDial('+380', 'Ucrania'),
    CountryDial('+381', 'Serbia'),
    CountryDial('+382', 'Montenegro'),
    CountryDial('+383', 'Kosovo'),
    CountryDial('+385', 'Croacia'),
    CountryDial('+386', 'Eslovenia'),
    CountryDial('+387', 'Bosnia y Herzegovina'),
    CountryDial('+389', 'Macedonia del Norte'),
    CountryDial('+420', 'Chequia'),
    CountryDial('+421', 'Eslovaquia'),
    CountryDial('+423', 'Liechtenstein'),
    CountryDial('+500', 'Islas Malvinas'),
    CountryDial('+501', 'Belice'),
    CountryDial('+502', 'Guatemala'),
    CountryDial('+503', 'El Salvador'),
    CountryDial('+504', 'Honduras'),
    CountryDial('+505', 'Nicaragua'),
    CountryDial('+506', 'Costa Rica'),
    CountryDial('+507', 'Panamá'),
    CountryDial('+508', 'San Pedro y Miquelón'),
    CountryDial('+509', 'Haití'),
    CountryDial('+590', 'Guadalupe'),
    CountryDial('+590', 'San Bartolomé'),
    CountryDial('+590', 'San Martín'),
    CountryDial('+591', 'Bolivia'),
    CountryDial('+592', 'Guyana'),
    CountryDial('+593', 'Ecuador'),
    CountryDial('+594', 'Guayana Francesa'),
    CountryDial('+595', 'Paraguay'),
    CountryDial('+596', 'Martinica'),
    CountryDial('+597', 'Surinam'),
    CountryDial('+598', 'Uruguay'),
    CountryDial('+599', 'Curazao y Caribe Neerlandés'),
    CountryDial('+670', 'Timor-Leste'),
    CountryDial('+672', 'Territorios Australianos Externos'),
    CountryDial('+673', 'Brunéi'),
    CountryDial('+674', 'Nauru'),
    CountryDial('+675', 'Papúa Nueva Guinea'),
    CountryDial('+676', 'Tonga'),
    CountryDial('+677', 'Islas Salomón'),
    CountryDial('+678', 'Vanuatu'),
    CountryDial('+679', 'Fiyi'),
    CountryDial('+680', 'Palau'),
    CountryDial('+681', 'Wallis y Futuna'),
    CountryDial('+682', 'Islas Cook'),
    CountryDial('+683', 'Niue'),
    CountryDial('+685', 'Samoa'),
    CountryDial('+686', 'Kiribati'),
    CountryDial('+687', 'Nueva Caledonia'),
    CountryDial('+688', 'Tuvalu'),
    CountryDial('+689', 'Polinesia Francesa'),
    CountryDial('+690', 'Tokelau'),
    CountryDial('+691', 'Micronesia'),
    CountryDial('+692', 'Islas Marshall'),
    CountryDial('+850', 'Corea del Norte'),
    CountryDial('+852', 'Hong Kong'),
    CountryDial('+853', 'Macao'),
    CountryDial('+855', 'Camboya'),
    CountryDial('+856', 'Laos'),
    CountryDial('+880', 'Bangladés'),
    CountryDial('+886', 'Taiwán'),
    CountryDial('+960', 'Maldivas'),
    CountryDial('+961', 'Líbano'),
    CountryDial('+962', 'Jordania'),
    CountryDial('+963', 'Siria'),
    CountryDial('+964', 'Irak'),
    CountryDial('+965', 'Kuwait'),
    CountryDial('+966', 'Arabia Saudí'),
    CountryDial('+967', 'Yemen'),
    CountryDial('+968', 'Omán'),
    CountryDial('+970', 'Palestina'),
    CountryDial('+971', 'Emiratos Árabes Unidos'),
    CountryDial('+972', 'Israel'),
    CountryDial('+973', 'Baréin'),
    CountryDial('+974', 'Catar'),
    CountryDial('+975', 'Bután'),
    CountryDial('+976', 'Mongolia'),
    CountryDial('+977', 'Nepal'),
    CountryDial('+992', 'Tayikistán'),
    CountryDial('+993', 'Turkmenistán'),
    CountryDial('+994', 'Azerbaiyán'),
    CountryDial('+995', 'Georgia'),
    CountryDial('+996', 'Kirguistán'),
    CountryDial('+998', 'Uzbekistán'),
  ];

  static const defaultCountryDial = CountryDial('+57', 'Colombia');

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
