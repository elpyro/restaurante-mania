import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/category.dart';
import '../../core/models/menu_item.dart';
import '../../core/models/role.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';

class MenuAdminScreen extends StatefulWidget {
  const MenuAdminScreen({super.key});

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
      ),
    );
    if (draft == null) return;

    if (item == null) {
      await repository.addMenuItem(
        name: draft.name,
        description: draft.description,
        price: draft.price,
        categoryId: draft.categoryId,
        emoji: draft.emoji,
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
                      final statusColor =
                          item.isAvailable ? AppTheme.success : AppTheme.danger;
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
                              Container(
                                width: 46,
                                height: 46,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7ED),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  item.emoji,
                                  style: const TextStyle(fontSize: 25),
                                ),
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
                                      label: item.status.label,
                                      color: statusColor,
                                    ),
                                  ],
                                ),
                              ),
                              if (canEdit) ...[
                                Switch.adaptive(
                                  value: item.isAvailable,
                                  onChanged: (_) =>
                                      repository.toggleAvailability(item.id),
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
  });

  final String name;
  final String description;
  final double price;
  final String categoryId;
  final String emoji;
}

class _MenuEditorDialog extends StatefulWidget {
  const _MenuEditorDialog({required this.item, required this.categories});

  final MenuItem? item;
  final List<Category> categories;

  @override
  State<_MenuEditorDialog> createState() => _MenuEditorDialogState();
}

class _MenuEditorDialogState extends State<_MenuEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _emoji;
  late String _categoryId;
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
    _categoryId = widget.item?.categoryId ??
        (widget.categories.isEmpty ? '' : widget.categories.first.id);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _emoji.dispose();
    super.dispose();
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
    Navigator.of(context).pop(
      _MenuDraft(
        name: name,
        description: _description.text.trim(),
        price: price,
        categoryId: _categoryId,
        emoji: _emoji.text.trim().isEmpty ? '🍽️' : _emoji.text.trim(),
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
