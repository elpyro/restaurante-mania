import 'dart:convert';

/// Estilo visual publicado en la web pública.
///
/// El `preset` viaja como texto (`mania`, `fuego`, `verde`, `noche`, `custom`)
/// para que la app y la web compartan exactamente el mismo contrato.
enum AppearancePreset {
  mania,
  fuego,
  verde,
  noche,
  custom;

  static AppearancePreset fromName(Object? value) {
    if (value is String) {
      for (final preset in AppearancePreset.values) {
        if (preset.name == value.toLowerCase().trim()) return preset;
      }
    }
    return AppearancePreset.mania;
  }
}

/// Colores base del estilo propio. La web deriva el resto de la paleta.
const customColorKeys = <String>[
  'brand',
  'accent',
  'surface',
  'ink',
  'heroFrom',
  'heroTo',
  'footer',
];

const defaultCustomColors = <String, String>{
  'brand': '#fe7f12',
  'accent': '#059669',
  'surface': '#fffaf5',
  'ink': '#1c1917',
  'heroFrom': '#fff8ed',
  'heroTo': '#ecfdf5',
  'footer': '#1c1917',
};

/// La web solo publica enlaces http(s); un campo vacío se envía como `null`.
String? cleanPublishedUrl(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? null : text;
}

class RestaurantAppearance {
  const RestaurantAppearance({
    required this.slogan,
    required this.heroTitle,
    required this.heroDescription,
    required this.heroBadge,
    this.preset = AppearancePreset.mania,
    this.bannerUrl,
    this.logoUrl,
    this.customColors = defaultCustomColors,
    this.instagramUrl,
    this.tiktokUrl,
    this.facebookUrl,
    this.gpsUrl,
  });

  /// Textos actualmente visibles en la portada de la web.
  static const defaults = RestaurantAppearance(
    slogan: 'Cocina colombiana hecha con calma y servida con cariño.',
    heroTitle: 'El sabor de casa, a un clic de distancia.',
    heroDescription:
        'Pide tu bandeja paisa, un ajiaco bien caliente o una limonada de coco. '
        'Preparamos todo al momento y lo tienes listo en minutos.',
    heroBadge: '🇨🇴 Cocina colombiana · Medellín',
    preset: AppearancePreset.mania,
  );

  // Iguales a los límites que valida la web antes de publicar en Firestore.
  static const sloganMaxLength = 160;
  static const heroTitleMaxLength = 120;
  static const heroDescriptionMaxLength = 500;
  static const heroBadgeMaxLength = 80;
  static const socialUrlMaxLength = 300;
  static const gpsUrlMaxLength = 500;

  final String slogan;
  final String heroTitle;
  final String heroDescription;
  final String heroBadge;
  final AppearancePreset preset;
  final String? bannerUrl;
  final String? logoUrl;
  final Map<String, String> customColors;
  final String? instagramUrl;
  final String? tiktokUrl;
  final String? facebookUrl;
  final String? gpsUrl;

  RestaurantAppearance copyWith({
    String? slogan,
    String? heroTitle,
    String? heroDescription,
    String? heroBadge,
    AppearancePreset? preset,
    String? bannerUrl,
    bool clearBanner = false,
    String? logoUrl,
    bool clearLogo = false,
    Map<String, String>? customColors,
    String? instagramUrl,
    bool clearInstagramUrl = false,
    String? tiktokUrl,
    bool clearTiktokUrl = false,
    String? facebookUrl,
    bool clearFacebookUrl = false,
    String? gpsUrl,
    bool clearGpsUrl = false,
  }) {
    return RestaurantAppearance(
      slogan: slogan ?? this.slogan,
      heroTitle: heroTitle ?? this.heroTitle,
      heroDescription: heroDescription ?? this.heroDescription,
      heroBadge: heroBadge ?? this.heroBadge,
      preset: preset ?? this.preset,
      bannerUrl: clearBanner ? null : bannerUrl ?? this.bannerUrl,
      logoUrl: clearLogo ? null : logoUrl ?? this.logoUrl,
      customColors: customColors ?? this.customColors,
      instagramUrl:
          clearInstagramUrl ? null : instagramUrl ?? this.instagramUrl,
      tiktokUrl: clearTiktokUrl ? null : tiktokUrl ?? this.tiktokUrl,
      facebookUrl: clearFacebookUrl ? null : facebookUrl ?? this.facebookUrl,
      gpsUrl: clearGpsUrl ? null : gpsUrl ?? this.gpsUrl,
    );
  }

  /// Cuerpo exacto aceptado por `PATCH /api/restaurant/config`.
  /// `null` en imágenes, redes o mapa indica a la web que debe eliminarlos.
  Map<String, dynamic> toJson() => {
        'slogan': slogan,
        'heroTitle': heroTitle,
        'heroDescription': heroDescription,
        'heroBadge': heroBadge,
        'appearance': {
          'preset': preset.name,
          'bannerUrl': bannerUrl,
          'logoUrl': logoUrl,
          if (preset == AppearancePreset.custom)
            'customColors': Map<String, String>.from(customColors),
          'socialLinks': {
            'instagram': cleanPublishedUrl(instagramUrl),
            'tiktok': cleanPublishedUrl(tiktokUrl),
            'facebook': cleanPublishedUrl(facebookUrl),
          },
          'gpsUrl': cleanPublishedUrl(gpsUrl),
        },
      };

  /// Acepta tanto el cuerpo de la configuración como un `config` anidado en
  /// la respuesta pública de la web (`GET /api/restaurant/config`).
  factory RestaurantAppearance.fromJson(Map<String, dynamic> json) {
    final appearance = json['appearance'];
    final nested = appearance is Map
        ? Map<String, dynamic>.from(appearance)
        : <String, dynamic>{};
    String text(String key, String fallback) {
      final value = json[key] ?? nested[key];
      return value is String ? value : fallback;
    }

    String? asset(String key) {
      final value = nested[key] ?? json[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    final rawSocial = nested['socialLinks'] ?? json['socialLinks'];
    final social = rawSocial is Map
        ? Map<String, dynamic>.from(rawSocial)
        : <String, dynamic>{};
    String? socialUrl(String key) => cleanPublishedUrl(social[key] is String
        ? social[key] as String
        : json[key] is String
            ? json[key] as String
            : null);
    final rawColors = nested['customColors'] ?? json['customColors'];
    final colors = <String, String>{};
    if (rawColors is Map) {
      for (final key in customColorKeys) {
        final value = rawColors[key];
        if (value is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
          colors[key] = value.toLowerCase();
        }
      }
    }

    return RestaurantAppearance(
      slogan: text('slogan', defaults.slogan),
      heroTitle: text('heroTitle', defaults.heroTitle),
      heroDescription: text('heroDescription', defaults.heroDescription),
      heroBadge: text('heroBadge', defaults.heroBadge),
      preset: AppearancePreset.fromName(
        json['preset'] ?? nested['preset'] ?? defaults.preset.name,
      ),
      bannerUrl: asset('bannerUrl'),
      logoUrl: asset('logoUrl'),
      customColors: colors.length == customColorKeys.length
          ? colors
          : Map<String, String>.from(defaultCustomColors),
      instagramUrl: socialUrl('instagram'),
      tiktokUrl: socialUrl('tiktok'),
      facebookUrl: socialUrl('facebook'),
      gpsUrl: asset('gpsUrl'),
    );
  }

  static RestaurantAppearance? tryFromStoredJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return RestaurantAppearance.fromJson(decoded);
      }
    } catch (_) {
      // Configuración corrupta: se conservan los valores por defecto.
    }
    return null;
  }

  static RestaurantAppearance fromStoredJson(String raw) =>
      tryFromStoredJson(raw) ?? defaults;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RestaurantAppearance &&
          runtimeType == other.runtimeType &&
          slogan == other.slogan &&
          heroTitle == other.heroTitle &&
          heroDescription == other.heroDescription &&
          heroBadge == other.heroBadge &&
          preset == other.preset &&
          bannerUrl == other.bannerUrl &&
          logoUrl == other.logoUrl &&
          instagramUrl == other.instagramUrl &&
          tiktokUrl == other.tiktokUrl &&
          facebookUrl == other.facebookUrl &&
          gpsUrl == other.gpsUrl &&
          jsonEncode(customColors) == jsonEncode(other.customColors);

  @override
  int get hashCode => Object.hash(
        slogan,
        heroTitle,
        heroDescription,
        heroBadge,
        preset,
        bannerUrl,
        logoUrl,
        instagramUrl,
        tiktokUrl,
        facebookUrl,
        gpsUrl,
        jsonEncode(customColors),
      );
}
