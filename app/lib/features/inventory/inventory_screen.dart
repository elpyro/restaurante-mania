import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/ingredient.dart';
import '../../core/models/role.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();
    final role = repository.role ?? UserRole.admin;
    final canEdit = role.canManageMenu;
    final lowCount = repository.lowStockIngredients.length;
    final query = _query.trim().toLowerCase();
    final items = repository.ingredients.where((ingredient) {
      return query.isEmpty ||
          ingredient.name.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(context, repository),
              backgroundColor: AppTheme.brand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuevo insumo'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Buscar insumo',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                _SummaryCard(
                  label: 'Insumos',
                  value: '${repository.ingredients.length}',
                  color: AppTheme.ink,
                ),
                const SizedBox(width: 8),
                _SummaryCard(
                  label: 'Stock bajo',
                  value: '$lowCount',
                  color: lowCount > 0 ? AppTheme.danger : AppTheme.success,
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'Sin insumos',
                      message: 'Agrega los ingredientes del restaurante.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final ingredient = items[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _IngredientTile(
                          ingredient: ingredient,
                          canEdit: canEdit,
                          onEdit: () => _openEditor(
                            context,
                            repository,
                            ingredient: ingredient,
                          ),
                          onDelete: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('Eliminar insumo'),
                                content: Text(
                                  '¿Eliminar "${ingredient.name}" del inventario?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(false),
                                    child: const Text('Cancelar'),
                                  ),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.danger,
                                    ),
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(true),
                                    child: const Text('Eliminar'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await repository.deleteIngredient(ingredient.id);
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    RestaurantRepository repository, {
    Ingredient? ingredient,
  }) async {
    final draft = await showDialog<_IngredientDraft>(
      context: context,
      builder: (_) => _IngredientEditorDialog(ingredient: ingredient),
    );
    if (draft == null) return;
    if (ingredient == null) {
      await repository.addIngredient(
        name: draft.name,
        unit: draft.unit,
        stock: draft.stock,
        minStock: draft.minStock,
        cost: draft.cost,
      );
    } else {
      await repository.upsertIngredient(
        ingredient.copyWith(
          name: draft.name,
          unit: draft.unit,
          stock: draft.stock,
          minStock: draft.minStock,
          cost: draft.cost,
        ),
      );
    }
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEDEAE6)),
        ),
        child: Row(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF78716C),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IngredientTile extends StatelessWidget {
  const _IngredientTile({
    required this.ingredient,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });

  final Ingredient ingredient;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ratio = ingredient.stockRatio;
    final progressColor = ingredient.isLow
        ? AppTheme.danger
        : ratio < 0.5
            ? AppTheme.warning
            : AppTheme.success;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ingredient.name,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              if (ingredient.isLow)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Stock bajo',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.danger,
                    ),
                  ),
                ),
              if (canEdit) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: onDelete,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Stock: ${ingredient.stockLabel}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF57534E),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Mínimo: ${ingredient.minStockLabel}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFA8A29E),
                ),
              ),
              if (ingredient.cost > 0) ...[
                const SizedBox(width: 12),
                Text(
                  '\$${ingredient.cost.toStringAsFixed(0)}/${ingredient.unit.symbol}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFFA8A29E),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: const Color(0xFFEDEAE6),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _IngredientDraft {
  const _IngredientDraft({
    required this.name,
    required this.unit,
    required this.stock,
    required this.minStock,
    required this.cost,
  });

  final String name;
  final IngredientUnit unit;
  final double stock;
  final double minStock;
  final double cost;
}

class _IngredientEditorDialog extends StatefulWidget {
  const _IngredientEditorDialog({this.ingredient});

  final Ingredient? ingredient;

  @override
  State<_IngredientEditorDialog> createState() =>
      _IngredientEditorDialogState();
}

class _IngredientEditorDialogState extends State<_IngredientEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _stock;
  late final TextEditingController _minStock;
  late final TextEditingController _cost;
  late IngredientUnit _unit;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.ingredient?.name ?? '');
    _stock = TextEditingController(
      text: widget.ingredient == null
          ? ''
          : _formatNumber(widget.ingredient!.stock),
    );
    _minStock = TextEditingController(
      text: widget.ingredient == null
          ? ''
          : _formatNumber(widget.ingredient!.minStock),
    );
    _cost = TextEditingController(
      text: widget.ingredient == null
          ? ''
          : _formatNumber(widget.ingredient!.cost),
    );
    _unit = widget.ingredient?.unit ?? IngredientUnit.gramo;
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _name.dispose();
    _stock.dispose();
    _minStock.dispose();
    _cost.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final stock = double.tryParse(_stock.text.replaceAll(',', '.').trim());
    final minStock = double.tryParse(_minStock.text.replaceAll(',', '.').trim());
    final cost = double.tryParse(_cost.text.replaceAll(',', '.').trim());
    if (name.length < 2) {
      setState(() => _error = 'Escribe el nombre del insumo.');
      return;
    }
    if (stock == null || stock < 0) {
      setState(() => _error = 'Escribe un stock válido.');
      return;
    }
    if (minStock == null || minStock < 0) {
      setState(() => _error = 'Escribe un stock mínimo válido.');
      return;
    }
    Navigator.of(context).pop(
      _IngredientDraft(
        name: name,
        unit: _unit,
        stock: stock,
        minStock: minStock,
        cost: cost ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.ingredient == null ? 'Nuevo insumo' : 'Editar insumo',
      ),
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
            const Text(
              'Unidad de medida',
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
              children: IngredientUnit.values.map((unit) {
                return ChoiceChip(
                  label: Text(unit.label),
                  selected: _unit == unit,
                  onSelected: (_) => setState(() => _unit = unit),
                  showCheckmark: false,
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _stock,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Stock actual *',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _minStock,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Stock mínimo *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _cost,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Costo unitario (opcional)',
              ),
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