import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/ingredient.dart';
import '../../core/models/role.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

enum _InventoryFilter { all, low, out }

String _formatNumber(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, this.showAppBar = false});

  final bool showAppBar;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _InventoryFilter _filter = _InventoryFilter.all;

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
    final outOfStockCount =
        repository.ingredients.where((i) => i.stock <= 0).length;
    final lowStockCount = repository.lowStockIngredients.length;
    final query = _query.trim().toLowerCase();
    final items = repository.ingredients.where((ingredient) {
      final matchesQuery =
          query.isEmpty || ingredient.name.toLowerCase().contains(query);
      final matchesStock = switch (_filter) {
        _InventoryFilter.all => true,
        _InventoryFilter.low => ingredient.isLow,
        _InventoryFilter.out => ingredient.stock <= 0,
      };
      return matchesQuery && matchesStock;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Inventario'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            )
          : null,
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
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      hintText: 'Buscar insumo',
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: [
                _SummaryCard(
                  label: 'Insumos',
                  value: '${repository.ingredients.length}',
                  color: AppTheme.ink,
                  selected: _filter == _InventoryFilter.all,
                  onTap: () => setState(() => _filter = _InventoryFilter.all),
                ),
                const SizedBox(width: 8),
                _SummaryCard(
                  label: 'Stock bajo',
                  value: '$lowStockCount',
                  color: AppTheme.warning,
                  selected: _filter == _InventoryFilter.low,
                  onTap: () => setState(() => _filter =
                      _filter == _InventoryFilter.low
                          ? _InventoryFilter.all
                          : _InventoryFilter.low),
                ),
                const SizedBox(width: 8),
                _SummaryCard(
                  label: 'Sin stock',
                  value: '$outOfStockCount',
                  color: outOfStockCount > 0 ? AppTheme.danger : AppTheme.success,
                  selected: _filter == _InventoryFilter.out,
                  onTap: () => setState(() => _filter =
                      _filter == _InventoryFilter.out
                          ? _InventoryFilter.all
                          : _InventoryFilter.out),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SectionHeader(
              title: switch (_filter) {
                _InventoryFilter.low => 'Insumos con stock bajo',
                _InventoryFilter.out => 'Insumos sin stock',
                _InventoryFilter.all => 'Todos los insumos',
              },
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              action: Text(
                '${items.length} resultado(s)',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFFA8A29E),
                ),
              ),
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
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 96),
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
                          onRestock: () => _openRestock(
                            context,
                            repository,
                            ingredient,
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

  /// Suma una cantidad al stock existente. No reemplaza el valor actual.
  Future<bool> _openRestock(
    BuildContext context,
    RestaurantRepository repository,
    Ingredient ingredient,
  ) async {
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => _RestockDialog(ingredient: ingredient),
    );
    if (amount == null || amount <= 0) return false;

    await repository.adjustIngredientStock(ingredient.id, amount);
    return true;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
    this.selected = false,
  });

  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? color : const Color(0xFFEDEAE6),
          width: selected ? 1.5 : 1,
        ),
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
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF78716C),
              ),
            ),
          ),
          if (onTap != null)
            Icon(
              selected ? Icons.filter_alt_rounded : Icons.filter_alt_outlined,
              size: 16,
              color: selected ? color : const Color(0xFFA8A29E),
            ),
        ],
      ),
    );
    return Expanded(
      child: onTap == null
          ? card
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(14),
                child: card,
              ),
            ),
    );
  }
}

class _IngredientTile extends StatefulWidget {
  const _IngredientTile({
    required this.ingredient,
    required this.canEdit,
    required this.onEdit,
    required this.onRestock,
    required this.onDelete,
  });

  final Ingredient ingredient;
  final bool canEdit;
  final VoidCallback onEdit;
  final Future<bool> Function() onRestock;
  final VoidCallback onDelete;

  @override
  State<_IngredientTile> createState() => _IngredientTileState();
}

class _IngredientTileState extends State<_IngredientTile> {
  Timer? _flashTimer;
  bool _justRestocked = false;

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  Future<void> _restock() async {
    final success = await widget.onRestock();
    if (!mounted || !success) return;
    setState(() => _justRestocked = true);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _justRestocked = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ingredient = widget.ingredient;
    final canEdit = widget.canEdit;
    final ratio = ingredient.stockRatio;
    final progressColor = ingredient.isLow
        ? AppTheme.danger
        : ratio < 0.5
            ? AppTheme.warning
            : AppTheme.success;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _justRestocked
            ? AppTheme.success.withValues(alpha: 0.12)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _justRestocked ? AppTheme.success : const Color(0xFFEDEAE6),
          width: _justRestocked ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_justRestocked) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.success,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: const [
                  Icon(Icons.check_circle_rounded, size: 16, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    '¡Surtido!',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  Spacer(),
                  Text(
                    'Stock actualizado',
                    style: TextStyle(fontSize: 10.5, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
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
                  onPressed: widget.onEdit,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: widget.onDelete,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 2,
            children: [
              Text(
                'Stock: ${ingredient.stockLabel}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF57534E),
                ),
              ),
              Text(
                'Mínimo: ${ingredient.minStockLabel}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFA8A29E),
                ),
              ),
              if (ingredient.cost > 0)
                Text(
                  '\$${ingredient.cost.toStringAsFixed(0)}/${ingredient.unit.symbol}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFFA8A29E),
                  ),
                ),
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
          if (canEdit) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _restock,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Surtir'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.brand.withValues(alpha: 0.12),
                  foregroundColor: AppTheme.brandDark,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RestockDialog extends StatefulWidget {
  const _RestockDialog({required this.ingredient});

  final Ingredient ingredient;

  @override
  State<_RestockDialog> createState() => _RestockDialogState();
}

class _RestockDialogState extends State<_RestockDialog> {
  final _controller = TextEditingController();
  String? _error;

  double? get _amount =>
      double.tryParse(_controller.text.replaceAll(',', '.').trim());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final amount = _amount;
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Escribe una cantidad mayor a cero.');
      return;
    }
    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) {
    final amount = _amount;
    final preview = amount == null || amount <= 0
        ? widget.ingredient.stock
        : widget.ingredient.stock + amount;

    return AlertDialog(
      title: Text('Surtir ${widget.ingredient.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stock actual: ${widget.ingredient.stockLabel}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF57534E),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _confirm(),
              decoration: InputDecoration(
                labelText:
                    'Cantidad a agregar (${widget.ingredient.unit.symbol})',
                hintText: 'Ej. 500',
                prefixIcon: const Icon(Icons.add_rounded, size: 18),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.danger,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    size: 18,
                    color: AppTheme.success,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Nuevo stock: '
                      '${_formatNumber(preview)} ${widget.ingredient.unit.symbol}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.brandDark,
                      ),
                    ),
                  ),
                ],
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
        FilledButton(
          onPressed: _confirm,
          child: const Text('Confirmar surtido'),
        ),
      ],
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