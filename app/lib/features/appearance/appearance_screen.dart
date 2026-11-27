import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/restaurant_appearance.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/media_upload_service.dart';
import '../../core/theme/app_theme.dart';

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _PresetStyle {
  const _PresetStyle({
    required this.label,
    required this.description,
    required this.colors,
  });

  final String label;
  final String description;
  final List<Color> colors;
}

const _presetStyles = <AppearancePreset, _PresetStyle>{
  AppearancePreset.mania: _PresetStyle(
    label: 'Manía',
    description: 'Naranja cálido, la identidad actual',
    colors: [Color(0xFFEF6408), Color(0xFFFBBF24), Color(0xFFFAF8F5)],
  ),
  AppearancePreset.fuego: _PresetStyle(
    label: 'Fuego',
    description: 'Rojos intensos para una cocina vibrante',
    colors: [Color(0xFFB91C1C), Color(0xFFF97316), Color(0xFFFFF7ED)],
  ),
  AppearancePreset.verde: _PresetStyle(
    label: 'Verde',
    description: 'Esmeralda fresco y natural',
    colors: [Color(0xFF047857), Color(0xFF84CC16), Color(0xFFF0FDF4)],
  ),
  AppearancePreset.noche: _PresetStyle(
    label: 'Noche',
    description: 'Azul profundo con acentos dorados',
    colors: [Color(0xFF0F172A), Color(0xFF334155), Color(0xFFFBBF24)],
  ),
  AppearancePreset.tierra: _PresetStyle(
    label: 'Tierra',
    description: 'Tonos cálidos y artesanales',
    colors: [Color(0xFF9A5429), Color(0xFF78716C), Color(0xFFFBF7F2)],
  ),
  AppearancePreset.oceano: _PresetStyle(
    label: 'Océano',
    description: 'Azul verdoso fresco y ligero',
    colors: [Color(0xFF009EA1), Color(0xFF0284C7), Color(0xFFF4FBFB)],
  ),
  AppearancePreset.uva: _PresetStyle(
    label: 'Uva',
    description: 'Morado elegante con acento rosa',
    colors: [Color(0xFF9333EA), Color(0xFFDB2777), Color(0xFFFBF7FF)],
  ),
  AppearancePreset.custom: _PresetStyle(
    label: 'Propio',
    description: 'Tus colores, guardados desde la app',
    colors: [Color(0xFFFE7F12), Color(0xFF059669), Color(0xFFFFFAF5)],
  ),
};

const _presetCustomColors = <AppearancePreset, Map<String, String>>{
  AppearancePreset.mania: {
    'brand': '#fe7f12',
    'accent': '#059669',
    'surface': '#fffaf5',
    'ink': '#1c1917',
    'heroFrom': '#fff8ed',
    'heroTo': '#ecfdf5',
    'footer': '#1c1917',
  },
  AppearancePreset.fuego: {
    'brand': '#e11d48',
    'accent': '#ea580c',
    'surface': '#fff8f5',
    'ink': '#291312',
    'heroFrom': '#fff1f2',
    'heroTo': '#fff7ed',
    'footer': '#2a100d',
  },
  AppearancePreset.verde: {
    'brand': '#16a34a',
    'accent': '#65a30d',
    'surface': '#f8fcf7',
    'ink': '#10281c',
    'heroFrom': '#f0fdf4',
    'heroTo': '#f7fee7',
    'footer': '#102319',
  },
  AppearancePreset.noche: {
    'brand': '#6366f1',
    'accent': '#22d3ee',
    'surface': '#0b1120',
    'ink': '#f8fafc',
    'heroFrom': '#111827',
    'heroTo': '#0f172a',
    'footer': '#070b14',
  },
  AppearancePreset.tierra: {
    'brand': '#b86a35',
    'accent': '#78716c',
    'surface': '#fbf7f2',
    'ink': '#2b2118',
    'heroFrom': '#fdf8f3',
    'heroTo': '#f5f5f4',
    'footer': '#2b2118',
  },
  AppearancePreset.oceano: {
    'brand': '#05c7c7',
    'accent': '#0284c7',
    'surface': '#f4fbfb',
    'ink': '#132a2e',
    'heroFrom': '#effefd',
    'heroTo': '#e0f2fe',
    'footer': '#132a2e',
  },
  AppearancePreset.uva: {
    'brand': '#a855f7',
    'accent': '#db2777',
    'surface': '#fbf7ff',
    'ink': '#24162f',
    'heroFrom': '#faf5ff',
    'heroTo': '#fce7f3',
    'footer': '#24162f',
  },
};

Color _hexColor(String value) {
  final hex = value.replaceFirst('#', '');
  return Color(int.parse('FF$hex', radix: 16));
}

/// La web solo acepta http(s); si el usuario pega un dominio, lo completamos.
String? _publishedUrl(TextEditingController controller) {
  final text = controller.text.trim();
  if (text.isEmpty) return null;
  if (text.startsWith('http://') || text.startsWith('https://')) return text;
  return 'https://$text';
}

const _colorLabels = <String, String>{
  'brand': 'Principal',
  'accent': 'Acento',
  'surface': 'Fondo',
  'ink': 'Texto',
  'heroFrom': 'Portada inicio',
  'heroTo': 'Portada fin',
  'footer': 'Pie de página',
};

class _AppearanceScreenState extends State<AppearanceScreen> {
  final _sloganController = TextEditingController();
  final _heroTitleController = TextEditingController();
  final _heroDescriptionController = TextEditingController();
  final _heroBadgeController = TextEditingController();
  final _ctaTitleController = TextEditingController();
  final _ctaDescriptionController = TextEditingController();
  final _instagramController = TextEditingController();
  final _tiktokController = TextEditingController();
  final _facebookController = TextEditingController();
  final _gpsController = TextEditingController();
  final _googlePlaceController = TextEditingController();
  AppearancePreset _preset = AppearancePreset.mania;
  String? _bannerUrl;
  String? _logoUrl;
  Map<String, String> _customColors =
      Map<String, String>.from(defaultCustomColors);
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _loadFrom(context.read<RestaurantRepository>().restaurantAppearance);
  }

  @override
  void dispose() {
    _sloganController.dispose();
    _heroTitleController.dispose();
    _heroDescriptionController.dispose();
    _heroBadgeController.dispose();
    _ctaTitleController.dispose();
    _ctaDescriptionController.dispose();
    _instagramController.dispose();
    _tiktokController.dispose();
    _facebookController.dispose();
    _gpsController.dispose();
    _googlePlaceController.dispose();
    super.dispose();
  }

  void _loadFrom(RestaurantAppearance appearance) {
    _sloganController.text = appearance.slogan;
    _heroTitleController.text = appearance.heroTitle;
    _heroDescriptionController.text = appearance.heroDescription;
    _heroBadgeController.text = appearance.heroBadge;
    _ctaTitleController.text = appearance.ctaTitle;
    _ctaDescriptionController.text = appearance.ctaDescription;
    _instagramController.text = appearance.instagramUrl ?? '';
    _tiktokController.text = appearance.tiktokUrl ?? '';
    _facebookController.text = appearance.facebookUrl ?? '';
    _gpsController.text = appearance.gpsUrl ?? '';
    _googlePlaceController.text = appearance.googlePlaceUrl ?? '';
    _preset = appearance.preset;
    _bannerUrl = appearance.bannerUrl;
    _logoUrl = appearance.logoUrl;
    _customColors = Map<String, String>.from(appearance.customColors);
    setState(() {});
  }

  RestaurantAppearance _draft() => RestaurantAppearance(
        slogan: _sloganController.text.trim(),
        heroTitle: _heroTitleController.text.trim(),
        heroDescription: _heroDescriptionController.text.trim(),
        heroBadge: _heroBadgeController.text.trim(),
        ctaTitle: _ctaTitleController.text.trim(),
        ctaDescription: _ctaDescriptionController.text.trim(),
        preset: _preset,
        bannerUrl: _bannerUrl,
        logoUrl: _logoUrl,
        customColors: Map<String, String>.from(_customColors),
        instagramUrl: _publishedUrl(_instagramController),
        tiktokUrl: _publishedUrl(_tiktokController),
        facebookUrl: _publishedUrl(_facebookController),
        gpsUrl: _publishedUrl(_gpsController),
        googlePlaceUrl: _publishedUrl(_googlePlaceController),
      );

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();
    final status = _status(repository);
    final statusColor = switch (status) {
      'Sincronizado' => AppTheme.success,
      'Pendiente' => AppTheme.warning,
      'Sin conexión' => const Color(0xFF78716C),
      _ => AppTheme.danger,
    };
    final needsLogin = _needsFirebaseLogin(repository);

    return Scaffold(
      appBar: AppBar(title: const Text('Apariencia de la web')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                status,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            needsLogin
                ? 'Los cambios pendientes se conservan en el dispositivo. '
                    'Inicia sesión para publicarlos.'
                : repository.hasPendingRestaurantConfig
                    ? 'Los cambios se enviarán al recuperar la conexión.'
                    : 'Los textos, imágenes y colores se leen desde la web pública.',
            style: const TextStyle(fontSize: 11, color: Color(0xFF78716C)),
          ),
          if (needsLogin && AuthService.firebaseApiKey.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => unawaited(repository.logout()),
                icon: const Icon(Icons.login_rounded, size: 16),
                label: const Text('Ir a iniciar sesión'),
              ),
            ),
          ],
          if (AuthService.firebaseApiKey.isEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Inicia sesión para publicar los cambios en la web.',
                style: TextStyle(
                  color: AppTheme.danger,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          const Text(
            'Imágenes de la portada',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          _AssetCard(
            title: 'Banner animado',
            subtitle: 'JPG, PNG, WEBP o GIF. Se muestra debajo del texto.',
            url: _bannerUrl,
            uploading: _uploading,
            onPick: () => unawaited(_pickAsset(isBanner: true)),
            onDelete: _bannerUrl == null
                ? null
                : () => unawaited(_deleteAsset(isBanner: true)),
          ),
          const SizedBox(height: 10),
          _AssetCard(
            title: 'Logo de la empresa',
            subtitle: 'JPG, PNG o WEBP con fondo transparente.',
            url: _logoUrl,
            uploading: _uploading,
            onPick: () => unawaited(_pickAsset(isBanner: false)),
            onDelete: _logoUrl == null
                ? null
                : () => unawaited(_deleteAsset(isBanner: false)),
          ),
          const SizedBox(height: 18),
          const Text(
            'Estilo visual',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.25,
            children: AppearancePreset.values.map((preset) {
              return _PresetCard(
                preset: preset,
                selected: preset == _preset,
                badge: _heroBadgeController.text,
                heroTitle: _heroTitleController.text,
                colors: preset == AppearancePreset.custom
                    ? _previewColors()
                    : _presetStyles[preset]!.colors,
                onTap: () => setState(() => _preset = preset),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _openColorDialog,
            icon: const Icon(Icons.color_lens_outlined, size: 18),
            label: const Text('Editar colores propios'),
          ),
          const SizedBox(height: 18),
          const Text(
            'Textos de la portada',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _sloganController,
            maxLength: RestaurantAppearance.sloganMaxLength,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Eslogan',
              helperText: 'Descripción corta del restaurante',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _heroTitleController,
            maxLength: RestaurantAppearance.heroTitleMaxLength,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Título hero'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _heroDescriptionController,
            maxLength: RestaurantAppearance.heroDescriptionMaxLength,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Descripción hero',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _heroBadgeController,
            maxLength: RestaurantAppearance.heroBadgeMaxLength,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Etiqueta hero'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctaTitleController,
            maxLength: RestaurantAppearance.ctaTitleMaxLength,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Título del bloque final',
              helperText: 'Texto grande del bloque «Pedir ahora».',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctaDescriptionController,
            maxLength: RestaurantAppearance.ctaDescriptionMaxLength,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Descripción del bloque final',
              helperText: 'Ejemplo: Abrimos todos los días de Lun–Sáb 11:30–20:30…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Redes sociales y ubicación',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _instagramController,
            keyboardType: TextInputType.url,
            maxLength: RestaurantAppearance.socialUrlMaxLength,
            decoration: const InputDecoration(
              labelText: 'Instagram',
              hintText: 'instagram.com/tu-restaurante',
              helperText: 'Solo se muestra en el pie de la web si tiene valor.',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tiktokController,
            keyboardType: TextInputType.url,
            maxLength: RestaurantAppearance.socialUrlMaxLength,
            decoration: const InputDecoration(
              labelText: 'TikTok',
              hintText: 'tiktok.com/@tu-restaurante',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _facebookController,
            keyboardType: TextInputType.url,
            maxLength: RestaurantAppearance.socialUrlMaxLength,
            decoration: const InputDecoration(
              labelText: 'Facebook',
              hintText: 'facebook.com/tu-restaurante',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _gpsController,
            keyboardType: TextInputType.url,
            maxLength: RestaurantAppearance.gpsUrlMaxLength,
            decoration: const InputDecoration(
              labelText: 'Ubicación GPS / mapa',
              hintText: 'maps.google.com/?q=tu-direccion',
              helperText: 'Se publica como enlace «Ver en el mapa».',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _googlePlaceController,
            keyboardType: TextInputType.url,
            maxLength: RestaurantAppearance.googlePlaceUrlMaxLength,
            decoration: const InputDecoration(
              labelText: 'Google Place / reseñas',
              hintText: 'https://g.page/r/...',
              helperText:
                  'Si se define, la web mostrará un enlace para calificar el restaurante.',
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => unawaited(_save(repository)),
              icon: const Icon(Icons.publish_outlined),
              label: const Text('Guardar en la web'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_reload(repository)),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Recargar desde la web'),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => unawaited(_reset(repository)),
              icon: const Icon(Icons.restart_alt_outlined),
              label: const Text('Restablecer'),
            ),
          ),
        ],
      ),
    );
  }

  List<Color> _previewColors() => [
        _hexColor(_customColors['brand'] ?? defaultCustomColors['brand']!),
        _hexColor(_customColors['accent'] ?? defaultCustomColors['accent']!),
        _hexColor(_customColors['surface'] ?? defaultCustomColors['surface']!),
      ];

  bool _needsFirebaseLogin(RestaurantRepository repository) =>
      AuthService.firebaseApiKey.isEmpty ||
      repository.needsFirebaseReLogin ||
      !repository.hasFirebaseSession;

  String _status(RestaurantRepository repository) {
    if (repository.needsFirebaseReLogin) {
      return 'Inicia sesión para publicar';
    }
    if (_needsFirebaseLogin(repository)) {
      return 'Sin sesión · inicia sesión para publicar';
    }
    if (!repository.isOnline) return 'Sin conexión';
    if (repository.hasPendingRestaurantConfig) return 'Pendiente';
    return 'Sincronizado';
  }

  Future<void> _pickAsset({required bool isBanner}) async {
    if (_uploading) return;
    final repository = context.read<RestaurantRepository>();
    setState(() => _uploading = true);
    try {
      final picker = ImagePicker();
      // Sin imageQuality/maxWidth/maxHeight image_picker entrega el archivo
      // original: comprimir un GIF conserva solo el primer frame y lo vuelve
      // un JPEG con extensión .gif.
      final file = await picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final mime = MediaUploadService.mimeTypeFromPath(file.path);
      if (mime.isEmpty) {
        throw const MediaUploadException('Usa una imagen JPG, PNG, WEBP o GIF.');
      }
      final service = MediaUploadService(
        authService: repository.authServiceForMedia,
      );
      final prefix = isBanner ? 'banner' : 'logo';
      final name =
          'tenants/${repository.tenantId}/appearance/$prefix-${DateTime.now().millisecondsSinceEpoch}.${
              mime.split('/').last.replaceAll('jpeg', 'jpg')}';
      final url = await service.uploadFile(
        filePath: file.path,
        objectName: name,
        maxBytes: isBanner ? 6 * 1024 * 1024 : 2 * 1024 * 1024,
      );
      final next = _draft().copyWith(
        bannerUrl: isBanner ? url : null,
        logoUrl: isBanner ? null : url,
      );
      await repository.updateRestaurantAppearance(next);
      if (!mounted) return;
      _loadFrom(next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isBanner ? 'Banner publicado en la web.' : 'Logo publicado en la web.',
          ),
        ),
      );
    } on MediaUploadException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteAsset({required bool isBanner}) async {
    final url = isBanner ? _bannerUrl : _logoUrl;
    if (url == null) return;
    final repository = context.read<RestaurantRepository>();
    try {
      final service = MediaUploadService(authService: repository.authServiceForMedia);
      await service.deleteUrl(url);
    } on MediaUploadException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
      return;
    }
    final next = _draft().copyWith(
      bannerUrl: isBanner ? null : _bannerUrl,
      logoUrl: isBanner ? _logoUrl : null,
      clearBanner: isBanner,
      clearLogo: !isBanner,
    );
    await repository.updateRestaurantAppearance(next);
    if (!mounted) return;
    _loadFrom(next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isBanner ? 'Banner eliminado de la web.' : 'Logo eliminado de la web.',
        ),
      ),
    );
  }

  Future<void> _openColorDialog() async {
    final repository = context.read<RestaurantRepository>();
    final initialColors = _preset == AppearancePreset.custom
        ? _customColors
        : (_presetCustomColors[_preset] ??
            Map<String, String>.from(defaultCustomColors));
    final colors = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _ColorDialog(colors: initialColors),
    );
    if (colors == null) return;
    setState(() {
      _customColors = colors;
      _preset = AppearancePreset.custom;
    });
    final next = _draft();
    await repository.updateRestaurantAppearance(next);
    if (!mounted) return;
    _loadFrom(next);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Estilo propio publicado en la web.')),
    );
  }

  Future<void> _save(RestaurantRepository repository) async {
    final appearance = _draft();
    await repository.updateRestaurantAppearance(appearance);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          repository.hasPendingRestaurantConfig
              ? 'Cambios guardados en el dispositivo, pendientes de sincronizar.'
              : 'Apariencia publicada en la web.',
        ),
      ),
    );
  }

  Future<void> _reload(RestaurantRepository repository) async {
    final changed = await repository.pullServerRestaurantConfig();
    if (!mounted) return;
    _loadFrom(repository.restaurantAppearance);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          changed ? 'Apariencia actualizada desde la web.' : 'La web no tiene cambios nuevos.',
        ),
      ),
    );
  }

  Future<void> _reset(RestaurantRepository repository) async {
    await repository.updateRestaurantAppearance(RestaurantAppearance.defaults);
    if (!mounted) return;
    _loadFrom(repository.restaurantAppearance);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Apariencia restablecida.')),
    );
  }
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({
    required this.title,
    required this.subtitle,
    required this.url,
    required this.uploading,
    required this.onPick,
    required this.onDelete,
  });

  final String title;
  final String subtitle;
  final String? url;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFF6F1EA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: url == null
                ? const Icon(Icons.image_outlined, color: Color(0xFFA8A29E))
                : Image.network(
                    url!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  url == null ? subtitle : 'Imagen publicada en la web',
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF78716C)),
                ),
              ],
            ),
          ),
          uploading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: url == null ? 'Subir imagen' : 'Cambiar imagen',
                  onPressed: onPick,
                  icon: const Icon(Icons.upload_file_outlined),
                ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Eliminar imagen',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
            ),
        ],
      ),
    );
  }
}

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.colors});

  final Map<String, String> colors;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late final Map<String, TextEditingController> _controllers;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final key in customColorKeys)
        key: TextEditingController(
          text: widget.colors[key] ?? defaultCustomColors[key] ?? '#000000',
        ),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickColor(String key, TextEditingController controller) async {
    final valid = RegExp(r'^#[0-9a-f]{6}$')
        .hasMatch(controller.text.trim().toLowerCase());
    final initial = valid
        ? _hexColor(controller.text.trim())
        : _hexColor(defaultCustomColors[key] ?? '#000000');
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => _ColorPickerDialog(
        initial: initial,
        label: _colorLabels[key] ?? key,
      ),
    );
    if (picked == null || !mounted) return;
    controller.text =
        '#${picked.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toLowerCase()}';
    setState(() => _error = null);
  }

  void _save() {
    final colors = <String, String>{};
    for (final entry in _controllers.entries) {
      final value = entry.value.text.trim().toLowerCase();
      if (!RegExp(r'^#[0-9a-f]{6}$').hasMatch(value)) {
        setState(() => _error = '${_colorLabels[entry.key]}: usa #RRGGBB.');
        return;
      }
      colors[entry.key] = value;
    }
    Navigator.of(context).pop(colors);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Colores propios'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Elige los 7 colores base. La web genera los tonos claros y oscuros.',
              style: TextStyle(fontSize: 12, color: Color(0xFF78716C)),
            ),
            const SizedBox(height: 12),
            ...customColorKeys.map((key) {
              final controller = _controllers[key]!;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: _colorLabels[key],
                          hintText: '#RRGGBB',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => unawaited(_pickColor(key, controller)),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: RegExp(r'^#[0-9a-f]{6}$')
                                    .hasMatch(controller.text.trim().toLowerCase())
                                ? _hexColor(controller.text.trim())
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE7E5E4)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(
                  color: AppTheme.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Aplicar')),
      ],
    );
  }
}

/// Selector HSV integrado (sin dependencias extra): toque el cuadro para elegir
/// saturación/brillo y deslice la barra para el tono.
class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial, required this.label});

  final Color initial;
  final String label;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv;
  late final TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hex = TextEditingController(text: _toHex(widget.initial));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  static String _toHex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toLowerCase()}';

  void _setHex(String value) {
    _hex.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _applyHex(String value) {
    final cleaned = value.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(cleaned)) return;
    final color = Color(int.parse('FF$cleaned', radix: 16));
    setState(() {
      _hsv = HSVColor.fromColor(color);
      _setHex(_toHex(color));
    });
  }

  void _updateSV(Offset position, Size size) {
    final saturation = (position.dx / size.width).clamp(0.0, 1.0);
    final value = (1 - position.dy / size.height).clamp(0.0, 1.0);
    setState(() {
      _hsv = _hsv.withSaturation(saturation).withValue(value);
      _setHex(_toHex(_hsv.toColor()));
    });
  }

  @override
  Widget build(BuildContext context) {
    final hueColor = HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor();
    return AlertDialog(
      title: Text('Color · ${widget.label}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapDown: (details) =>
                      _updateSV(details.localPosition, constraints.biggest),
                  onPanUpdate: (details) =>
                      _updateSV(details.localPosition, constraints.biggest),
                  child: Container(
                    height: 160,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(colors: [Colors.white, hueColor]),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black],
                        ),
                      ),
                      alignment: Alignment(
                        _hsv.saturation * 2 - 1,
                        1 - _hsv.value * 2,
                      ),
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black45, blurRadius: 3),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Slider(
              value: _hsv.hue,
              min: 0,
              max: 360,
              activeColor: hueColor,
              onChanged: (hue) => setState(() {
                _hsv = _hsv.withHue(hue);
                _setHex(_toHex(_hsv.toColor()));
              }),
            ),
            TextField(
              controller: _hex,
              onChanged: _applyHex,
              decoration: const InputDecoration(
                labelText: 'Hex (#RRGGBB)',
                prefixIcon: Icon(Icons.colorize_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _hsv.toColor(),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE7E5E4)),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _toHex(_hsv.toColor()).toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_hsv.toColor()),
          child: const Text('Usar color'),
        ),
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.badge,
    required this.heroTitle,
    required this.colors,
    required this.onTap,
  });

  final AppearancePreset preset;
  final bool selected;
  final String badge;
  final String heroTitle;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = _presetStyles[preset]!;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppTheme.brand : const Color(0xFFEDEAE6),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                style.label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              Text(
                style.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9, color: Color(0xFF78716C)),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final color in colors) ...[
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE7E5E4)),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: colors.take(2).toList(),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        badge.isEmpty ? '🍽️ Cocina colombiana' : badge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 7.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        heroTitle.isEmpty
                            ? 'El sabor de casa'
                            : heroTitle.replaceAll('\n', ' '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
