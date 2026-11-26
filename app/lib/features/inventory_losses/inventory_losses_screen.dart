import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/ingredient.dart';
import '../../core/models/inventory_loss.dart';
import '../../core/services/media_upload_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';

/// Formulario de pérdidas/caducados. La foto se toma con la cámara del celular
/// (o se elige de la galería si el dispositivo no tiene cámara) y se guarda
/// localmente hasta que haya red para subirla a Storage.
class RegisterLossScreen extends StatefulWidget {
  const RegisterLossScreen({super.key});

  @override
  State<RegisterLossScreen> createState() => _RegisterLossScreenState();
}

class _LineDraft {
  _LineDraft(this.ingredientId);

  String ingredientId;
  final TextEditingController quantity = TextEditingController(text: '1');
}

class _RegisterLossScreenState extends State<RegisterLossScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notes = TextEditingController();
  final List<_LineDraft> _lines = [_LineDraft('')];
  LossReason _reason = LossReason.caducado;
  String? _photoPath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final ingredients = context.read<RestaurantRepository>().ingredients;
    if (ingredients.isNotEmpty) _lines.first.ingredientId = ingredients.first.id;
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final line in _lines) {
      line.quantity.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    // Sin imageQuality: conserva el archivo original tomado por la cámara.
    final file = await picker.pickImage(source: source);
    if (file == null || !mounted) return;
    final mime = MediaUploadService.mimeTypeFromPath(file.path);
    if (mime.isEmpty || !MediaUploadService.allowedMimeTypes.contains(mime)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usa una imagen JPG, PNG, WEBP o GIF.')),
      );
      return;
    }
    setState(() => _photoPath = file.path);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final repository = context.read<RestaurantRepository>();
    final lines = <LossLine>[];
    for (final draft in _lines) {
      final ingredient = repository.ingredientById(draft.ingredientId);
      if (ingredient == null) continue;
      final quantity = double.tryParse(draft.quantity.text.trim()) ?? 0;
      if (quantity <= 0) continue;
      if (quantity > ingredient.stock) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No hay ${ingredient.stockLabel} de ${ingredient.name} para registrar.',
            ),
          ),
        );
        return;
      }
      lines.add(
        LossLine(
          ingredientId: ingredient.id,
          name: ingredient.name,
          quantity: quantity,
          unit: ingredient.unit.symbol,
        ),
      );
    }
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrega cantidades mayores a cero.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await repository.registerInventoryLoss(
        reason: _reason,
        lines: lines,
        notes: _notes.text,
        photoPath: _photoPath,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pérdida registrada. Se sincronizará con la web.'),
        ),
      );
      Navigator.of(context).pop(true);
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ingredients = context.watch<RestaurantRepository>().ingredients;

    return Scaffold(
      appBar: AppBar(title: const Text('Registrar pérdida')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const Text(
              'Registra caducados o mermas de ingredientes. La cantidad se '
              'descuenta del inventario y queda auditada.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF78716C)),
            ),
            const SizedBox(height: 18),
            const Text(
              'Motivo',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<LossReason>(
              initialValue: _reason,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
              ),
              items: [
                for (final reason in LossReason.values)
                  DropdownMenuItem(
                    value: reason,
                    child: Text(reason.label),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _reason = value ?? _reason),
            ),
            SectionHeader(
              title: 'Ingredientes y cantidad',
              action: TextButton.icon(
                onPressed: _saving || ingredients.isEmpty
                    ? null
                    : () => setState(
                        () => _lines.add(_LineDraft(ingredients.first.id)),
                      ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Agregar'),
              ),
            ),
            if (ingredients.isEmpty)
              const Text(
                'No hay ingredientes registrados.',
                style: TextStyle(fontSize: 12, color: AppTheme.danger),
              ),
            for (var index = 0; index < _lines.length; index++) ...[
              _IngredientLine(
                draft: _lines[index],
                ingredients: ingredients,
                index: index,
                canRemove: _lines.length > 1 && !_saving,
                onRemove: () => setState(() {
                  _lines[index].quantity.dispose();
                  _lines.removeAt(index);
                }),
                onChanged: (value) =>
                    setState(() => _lines[index].ingredientId = value),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 10),
            const Text(
              'Observaciones',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              enabled: !_saving,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: 'Ej. lote vencido, hallazgo en nevera…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Foto de la pérdida',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _pickPhoto(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Tomar foto'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _pickPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galería'),
                  ),
                ),
              ],
            ),
            if (_photoPath != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  File(_photoPath!),
                  height: 170,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Guardando…' : 'Guardar pérdida'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brand,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IngredientLine extends StatelessWidget {
  const _IngredientLine({
    required this.draft,
    required this.ingredients,
    required this.index,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  final _LineDraft draft;
  final List<Ingredient> ingredients;
  final int index;
  final bool canRemove;
  final VoidCallback onRemove;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = ingredients.indexWhere((i) => i.id == draft.ingredientId);
    final unit = selected >= 0 ? ingredients[selected].unit.symbol : '';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${index + 1}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTheme.brand,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: draft.ingredientId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Ingrediente',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10),
                  ),
                  items: [
                    for (final ingredient in ingredients)
                      DropdownMenuItem(
                        value: ingredient.id,
                        child: Text(
                          '${ingredient.name} (${ingredient.stockLabel})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) onChanged(value);
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: draft.quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Cantidad',
                    suffixText: unit,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  validator: (value) {
                    final quantity = double.tryParse(value?.trim() ?? '');
                    if (quantity == null || quantity <= 0) {
                      return 'Mayor a cero';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Quitar ingrediente',
            onPressed: canRemove ? onRemove : null,
            icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
          ),
        ],
      ),
    );
  }
}

/// Historial de pérdidas para el administrador, con foto, estado y auditoría.
class InventoryLossesScreen extends StatefulWidget {
  const InventoryLossesScreen({super.key});

  @override
  State<InventoryLossesScreen> createState() => _InventoryLossesScreenState();
}

class _InventoryLossesScreenState extends State<InventoryLossesScreen> {
  @override
  void initState() {
    super.initState();
    final repository = context.read<RestaurantRepository>();
    if (repository.isOnline) unawaited(repository.pullInventoryLosses());
  }

  Future<void> _refresh() async {
    final repository = context.read<RestaurantRepository>();
    await repository.flushInventoryLosses();
    await repository.pullInventoryLosses();
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();
    final losses = repository.inventoryLosses;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pérdidas de inventario'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: repository.isOnline ? _refresh : null,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: repository.role?.canRegisterInventoryLoss == true
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RegisterLossScreen(),
                ),
              ),
              backgroundColor: AppTheme.brand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Registrar pérdida'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: losses.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'Sin pérdidas registradas',
                    message:
                        'Los caducados y mermas aparecerán aquí con su foto y auditoría.',
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: losses.length,
                itemBuilder: (context, index) =>
                    _LossCard(loss: losses[index]),
              ),
      ),
    );
  }
}

class _LossCard extends StatelessWidget {
  const _LossCard({required this.loss});

  final InventoryLoss loss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${loss.reason.label} · ${formatDateTime(loss.createdAt)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              StatusPill(
                label: loss.statusLabel,
                color: loss.synced ? AppTheme.success : AppTheme.warning,
                icon: loss.synced
                    ? Icons.cloud_done_outlined
                    : Icons.schedule_rounded,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            loss.linesSummary,
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
          if (loss.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              loss.notes,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF78716C),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (loss.photoUrl != null || loss.photoPath != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: loss.photoUrl != null
                  ? Image.network(
                      loss.photoUrl!,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(
                        height: 140,
                        child: Center(
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    )
                  : Image.file(
                      File(loss.photoPath!),
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Registrado por ${loss.createdByName.isEmpty ? 'usuario' : loss.createdByName}'
            ' · ${loss.createdByRole}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF78716C)),
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Auditoría',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            children: [
              for (final entry in loss.auditLog)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history_rounded, size: 18),
                  title: Text(entry.action, style: const TextStyle(fontSize: 12)),
                  subtitle: Text(
                    '${formatDateTime(entry.timestamp)} · '
                    '${entry.actorName.isEmpty ? entry.actorRole : entry.actorName}',
                    style: const TextStyle(fontSize: 10.5),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
