import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/category.dart';
import '../../core/models/ingredient.dart';
import '../../core/models/menu_item.dart';
import '../../core/models/role.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../inventory/inventory_screen.dart';

class MenuAdminScreen extends StatefulWidget {
  const MenuAdminScreen({super.key, this.showAppBar = false});

  final bool showAppBar;

  @override
  State<MenuAdminScreen> createState() => _MenuAdminScreenState();
}

class _MenuAdminScreenState extends State<MenuAdminScreen> {
  final _searchController = TextEditingController();
  String _categoryId = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openEditor(
    RestaurantRepository repository, {
    MenuItem? item,
  }) async {
    final draft = await showDialog<_MenuDraft>(
      context: context,
      builder: (_) => _MenuEditorDialog(
        item: item,
        categories: repository.categories,
        ingredients: repository.ingredients,
      ),
    );
    if (draft == null) return;

    if (item == null) {
      final created = await repository.addMenuItem(
        name: draft.name,
        description: draft.description,
        price: draft.price,
        categoryId: draft.categoryId,
        emoji: draft.emoji,
      );
      await repository.upsertMenuItem(
        created.copyWith(
          sku: draft.sku,
          imageUrl: draft.imageUrl,
          videoUrl: draft.videoUrl,
          recipeSteps: draft.recipeSteps,
          recipe: draft.recipe,
          ingredients: draft.ingredients,
        ),
      );
    } else {
      final category = repository.categoryById(draft.categoryId);
      await repository.upsertMenuItem(
        item.copyWith(
          name: draft.name,
          description: draft.description,
          price: draft.price,
          categoryId: draft.categoryId,
          categorySlug: category?.slug ?? item.categorySlug,
          emoji: draft.emoji,
          sku: draft.sku,
          imageUrl: draft.imageUrl,
          videoUrl: draft.videoUrl,
          recipeSteps: draft.recipeSteps,
          recipe: draft.recipe,
          ingredients: draft.ingredients,
        ),
      );
    }
  }

  Future<void> _confirmDelete(
    RestaurantRepository repository,
    MenuItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('¿Eliminar "${item.name}" del menú?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await repository.deleteMenuItem(item.id);
  }

  /// Explica por qué el plato no se puede activar y ofrece ir a Inventario.
  Future<void> _explainOutOfStock(
    RestaurantRepository repository,
    MenuItem item,
  ) async {
    final shortages = repository.outOfStockIngredientsFor(item);
    final goToIngredients = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.inventory_2_outlined, color: AppTheme.danger),
        title: const Text('No se puede poner disponible'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"${item.name}" no tiene insumos suficientes para preparar '
                'una porción.',
                style: const TextStyle(fontSize: 13, color: AppTheme.ink),
              ),
              const SizedBox(height: 12),
              const Text(
                'Insumos faltantes',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.danger,
                ),
              ),
              const SizedBox(height: 6),
              ...shortages.map(
                (shortage) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: AppTheme.danger,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${shortage.ingredient.name}: hay '
                          '${shortage.ingredient.stockLabel}, se necesitan '
                          '${_formatAmount(shortage.required)} '
                          '${shortage.ingredient.unit.symbol}.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Ir a ingredientes'),
          ),
        ],
      ),
    );
    if (goToIngredients != true || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const InventoryScreen(showAppBar: true),
      ),
    );
  }

  static String _formatAmount(double value) =>
      value == value.roundToDouble()
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();
    final role = repository.role ?? UserRole.admin;
    final canEdit = role.canManageMenu;
    final query = _searchController.text.trim().toLowerCase();
    final items = repository.menuItems.where((item) {
      final categoryOk = _categoryId == 'all' || item.categoryId == _categoryId;
      final searchOk = query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.description.toLowerCase().contains(query);
      return categoryOk && searchOk;
    }).toList();
    final available =
        repository.menuItems.where((item) => item.isAvailable).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Menú'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            )
          : null,
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(repository),
              backgroundColor: AppTheme.brand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuevo plato'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar en el menú',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _MenuChip(
                  label: 'Todo',
                  selected: _categoryId == 'all',
                  onTap: () => setState(() => _categoryId = 'all'),
                ),
                ...repository.categories.map(
                  (category) => _MenuChip(
                    label: '${category.emoji} ${category.name}',
                    selected: _categoryId == category.id,
                    onTap: () => setState(() => _categoryId = category.id),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                Text(
                  '${items.length} productos',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF78716C),
                  ),
                ),
                const Spacer(),
                Text(
                  '$available disponibles',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.success,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: EmptyState(
                      icon: Icons.restaurant_menu_outlined,
                      title: 'No hay productos con este filtro',
                      message: 'Cambia la categoría o la búsqueda.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final category = repository.categoryById(item.categoryId);
                      final outByIngredients =
                          repository.isMenuItemOutOfStockByIngredients(item);
                      final effectivelyAvailable =
                          repository.isMenuItemEffectivelyAvailable(item);
                      final statusColor =
                          effectivelyAvailable ? AppTheme.success : AppTheme.danger;
                      final statusLabel =
                          outByIngredients && !item.manualUnavailable
                              ? 'Agotado (sin insumos)'
                              : item.status.label;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFEDEAE6),
                            ),
                          ),
                          child: Row(
                            children: [
                              MenuItemImage(
                                imageUrl: item.imageUrl,
                                emoji: item.emoji,
                                size: 46,
                                borderRadius: 12,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.ink,
                                      ),
                                    ),
                                    Text(
                                      '${category?.name ?? 'Sin categoría'} · ${formatCop(item.price)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        color: Color(0xFF78716C),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    StatusPill(
                                      label: statusLabel,
                                      color: statusColor,
                                    ),
                                  ],
                                ),
                              ),
                              if (canEdit) ...[
                                Switch.adaptive(
                                  value: effectivelyAvailable,
                                  onChanged: (value) {
                                    if (value && outByIngredients) {
                                      _explainOutOfStock(repository, item);
                                      return;
                                    }
                                    repository.toggleAvailability(item.id);
                                  },
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _openEditor(repository, item: item);
                                    } else if (value == 'delete') {
                                      _confirmDelete(repository, item);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem<String>(
                                      value: 'edit',
                                      child: Text('Editar'),
                                    ),
                                    PopupMenuItem<String>(
                                      value: 'delete',
                                      child: Text('Eliminar'),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MenuChip extends StatelessWidget {
  const _MenuChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        labelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: selected ? Colors.white : const Color(0xFF57534E),
        ),
        selectedColor: AppTheme.ink,
        backgroundColor: Colors.white,
      ),
    );
  }
}

class _MenuDraft {
  const _MenuDraft({
    required this.name,
    required this.description,
    required this.price,
    required this.categoryId,
    required this.emoji,
    required this.sku,
    required this.imageUrl,
    required this.videoUrl,
    required this.recipeSteps,
    required this.recipe,
    required this.ingredients,
  });

  final String name;
  final String description;
  final double price;
  final String categoryId;
  final String emoji;
  final String sku;
  final String imageUrl;
  final String videoUrl;
  final String recipeSteps;
  final List<RecipeIngredient> recipe;
  final List<String> ingredients;
}

class _MenuEditorDialog extends StatefulWidget {
  const _MenuEditorDialog({
    required this.item,
    required this.categories,
    required this.ingredients,
  });

  final MenuItem? item;
  final List<Category> categories;
  final List<Ingredient> ingredients;

  @override
  State<_MenuEditorDialog> createState() => _MenuEditorDialogState();
}

class _MenuEditorDialogState extends State<_MenuEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _emoji;
  late final TextEditingController _sku;
  late final TextEditingController _imageUrl;
  late final TextEditingController _videoUrl;
  late final TextEditingController _recipeSteps;
  late String _categoryId;
  late List<RecipeIngredient> _recipe;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item?.name ?? '');
    _description = TextEditingController(text: widget.item?.description ?? '');
    _price = TextEditingController(
      text: widget.item == null ? '' : widget.item!.price.toStringAsFixed(0),
    );
    _emoji = TextEditingController(text: widget.item?.emoji ?? '🍽️');
    _sku = TextEditingController(text: widget.item?.sku ?? '');
    _imageUrl = TextEditingController(text: widget.item?.imageUrl ?? '');
    _videoUrl = TextEditingController(text: widget.item?.videoUrl ?? '');
    _recipeSteps = TextEditingController(text: widget.item?.recipeSteps ?? '');
    _categoryId = widget.item?.categoryId ??
        (widget.categories.isEmpty ? '' : widget.categories.first.id);
    _recipe = List<RecipeIngredient>.from(widget.item?.recipe ?? const []);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _emoji.dispose();
    _sku.dispose();
    _imageUrl.dispose();
    _videoUrl.dispose();
    _recipeSteps.dispose();
    super.dispose();
  }

  String _ingredientName(String id) {
    final matches = widget.ingredients.where((item) => item.id == id);
    return matches.isEmpty ? id : matches.first.name;
  }

  Future<void> _addRecipeLine() async {
    if (widget.ingredients.isEmpty) return;
    final result = await showDialog<_RecipeLineDraft>(
      context: context,
      builder: (_) => _RecipeLineDialog(ingredients: widget.ingredients),
    );
    if (result == null) return;
    setState(() {
      _recipe = [..._recipe, result.toRecipe()];
    });
  }

  void _removeRecipeLine(int index) {
    setState(() {
      _recipe = [..._recipe]..removeAt(index);
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final saved = await _copyToAppDir(file, 'images');
    setState(() => _imageUrl.text = saved);
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final file = await picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    final saved = await _copyToAppDir(file, 'videos');
    setState(() => _videoUrl.text = saved);
  }

  Future<String> _copyToAppDir(XFile file, String subdir) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'media', subdir));
    if (!await dir.exists()) await dir.create(recursive: true);
    final ext = p.extension(file.path).isEmpty ? '' : p.extension(file.path);
    final name = '${DateTime.now().millisecondsSinceEpoch}$ext';
    final dest = p.join(dir.path, name);
    await File(file.path).copy(dest);
    return dest;
  }

  void _save() {
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.replaceAll('.', '').trim());
    if (name.length < 2) {
      setState(() => _error = 'Escribe el nombre del producto.');
      return;
    }
    if (price == null || price <= 0) {
      setState(() => _error = 'Escribe un precio válido.');
      return;
    }
    if (_categoryId.isEmpty) {
      setState(() => _error = 'Selecciona una categoría.');
      return;
    }
    final ingredientNames = _recipe
        .map((line) => _ingredientName(line.ingredientId))
        .toList();
    Navigator.of(context).pop(
      _MenuDraft(
        name: name,
        description: _description.text.trim(),
        price: price,
        categoryId: _categoryId,
        emoji: _emoji.text.trim().isEmpty ? '🍽️' : _emoji.text.trim(),
        sku: _sku.text.trim(),
        imageUrl: _imageUrl.text.trim(),
        videoUrl: _videoUrl.text.trim(),
        recipeSteps: _recipeSteps.text.trim(),
        recipe: _recipe,
        ingredients: ingredientNames.isEmpty
            ? (widget.item?.ingredients ?? const [])
            : ingredientNames,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'Nuevo producto' : 'Editar producto'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Descripción'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Precio (COP) *',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emoji,
              decoration: const InputDecoration(
                labelText: 'Emoji',
                helperText: 'Ej.: 🍛, 🥤, 🍰',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _sku,
              decoration: const InputDecoration(labelText: 'SKU'),
            ),
            const SizedBox(height: 10),
            _MediaPicker(
              label: 'Foto del plato',
              path: _imageUrl.text,
              icon: Icons.photo_camera_outlined,
              onPick: _pickImage,
              onClear: () => setState(() => _imageUrl.text = ''),
            ),
            const SizedBox(height: 10),
            _MediaPicker(
              label: 'Video del plato',
              path: _videoUrl.text,
              icon: Icons.videocam_outlined,
              onPick: _pickVideo,
              onClear: () => setState(() => _videoUrl.text = ''),
            ),
            const SizedBox(height: 14),
            const Text(
              'Categoría',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.categories.map((category) {
                return ChoiceChip(
                  label: Text('${category.emoji} ${category.name}'),
                  selected: _categoryId == category.id,
                  onSelected: (_) =>
                      setState(() => _categoryId = category.id),
                  showCheckmark: false,
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            const Text(
              'Receta (pasos para cocina)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _recipeSteps,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '1. ...\n2. ...',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text(
                  'Insumos por porción',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addRecipeLine,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Agregar'),
                ),
              ],
            ),
            if (_recipe.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Sin receta estructurada.',
                  style: TextStyle(fontSize: 11, color: Color(0xFFA8A29E)),
                ),
              )
            else
              Column(
                children: List.generate(_recipe.length, (index) {
                  final line = _recipe[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_ingredientName(line.ingredientId)} · '
                            '${line.quantity}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded, size: 16),
                          onPressed: () => _removeRecipeLine(index),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.danger,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}

class _RecipeLineDraft {
  const _RecipeLineDraft({
    required this.ingredientId,
    required this.quantity,
  });

  final String ingredientId;
  final double quantity;

  RecipeIngredient toRecipe() =>
      RecipeIngredient(ingredientId: ingredientId, quantity: quantity);
}

class _RecipeLineDialog extends StatefulWidget {
  const _RecipeLineDialog({required this.ingredients});

  final List<Ingredient> ingredients;

  @override
  State<_RecipeLineDialog> createState() => _RecipeLineDialogState();
}

class _RecipeLineDialogState extends State<_RecipeLineDialog> {
  late String _ingredientId;
  final _quantityController = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    _ingredientId = widget.ingredients.first.id;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar insumo a la receta'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _ingredientId,
            decoration: const InputDecoration(labelText: 'Insumo'),
            items: widget.ingredients
                .map(
                  (ingredient) => DropdownMenuItem<String>(
                    value: ingredient.id,
                    child: Text(ingredient.name),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _ingredientId = value);
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _quantityController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Cantidad por porción',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final qty = double.tryParse(
              _quantityController.text.replaceAll(',', '.').trim(),
            );
            if (qty == null || qty <= 0) return;
            Navigator.of(context).pop(
              _RecipeLineDraft(ingredientId: _ingredientId, quantity: qty),
            );
          },
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}

class _MediaPicker extends StatelessWidget {
  const _MediaPicker({
    required this.label,
    required this.path,
    required this.icon,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final String path;
  final IconData icon;
  final VoidCallback onPick;
  final VoidCallback onClear;

  bool get _isImage {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.brandDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              if (path.isNotEmpty)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: onClear,
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (path.isEmpty)
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.upload_rounded, size: 16),
              label: const Text('Subir desde el dispositivo'),
            )
          else ...[
            if (_isImage && File(path).existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(path),
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                height: 48,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  path.split(RegExp(r'[\\/]')).last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Cambiar archivo'),
            ),
          ],
        ],
      ),
    );
  }
}
