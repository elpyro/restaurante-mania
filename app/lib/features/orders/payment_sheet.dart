import 'package:flutter/material.dart';

import '../../core/models/order.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';

Future<List<OrderPayment>?> showPaymentSheet(
  BuildContext context, {
  required double total,
  required String title,
  String subtitle = '',
}) {
  return showModalBottomSheet<List<OrderPayment>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _PaymentSheet(total: total, title: title, subtitle: subtitle),
  );
}

class _PaymentEntry {
  _PaymentEntry({required this.method, required this.amount});
  PaymentMethod method;
  double amount;
  String note = '';
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.total, required this.title, required this.subtitle});

  final double total;
  final String title;
  final String subtitle;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final List<_PaymentEntry> _entries = [
    _PaymentEntry(method: PaymentMethod.cash, amount: 0),
  ];
  String? _error;

  @override
  void initState() {
    super.initState();
    _entries.first.amount = widget.total;
  }

  double get _sum => _entries.fold(0, (s, e) => s + e.amount);

  void _addEntry() {
    setState(() {
      final remaining = widget.total - _sum;
      _entries.add(_PaymentEntry(
        method: PaymentMethod.nequi,
        amount: remaining > 0 ? remaining : 0,
      ));
      _error = null;
    });
  }

  void _removeEntry(int index) {
    if (_entries.length <= 1) return;
    setState(() {
      _entries.removeAt(index);
      if (_entries.length == 1) _entries.first.amount = widget.total;
      _error = null;
    });
  }

  void _confirm() {
    final sum = _sum;
    if ((sum - widget.total).abs() > 1) {
      setState(() => _error = 'La suma de pagos (${formatCop(sum)}) debe ser igual al total (${formatCop(widget.total)}).');
      return;
    }
    for (final e in _entries) {
      if (e.amount <= 0) {
        setState(() => _error = 'Cada método debe tener un monto mayor a 0.');
        return;
      }
    }
    // normalize last amount to fix rounding
    if (_entries.length > 1) {
      final others = _entries.sublist(0, _entries.length - 1).fold<double>(0, (s, e) => s + e.amount);
      _entries.last.amount = widget.total - others;
    }
    Navigator.of(context).pop(_entries.map((e) => OrderPayment(method: e.method, amount: e.amount, note: e.note.trim())).toList());
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final multi = _entries.length > 1;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                ),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
              ],
            ),
            if (widget.subtitle.isNotEmpty)
              Text(widget.subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF78716C), fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFAF8F5), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFEDEAE6))),
              child: Row(children: [
                const Text('Total a cobrar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(formatCop(widget.total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.brandDark)),
              ]),
            ),
            const SizedBox(height: 14),
            const Text('Método(s) de pago', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.ink)),
            const SizedBox(height: 8),
            ..._entries.asMap().entries.map((entry) {
              final i = entry.key;
              final e = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFEDEAE6))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('Pago ${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (_entries.length > 1)
                      IconButton(onPressed: () => _removeEntry(i), icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.danger), visualDensity: VisualDensity.compact),
                  ]),
                  Wrap(spacing: 6, runSpacing: 6, children: PaymentMethod.values.map((m) {
                    return ChoiceChip(
                      label: Text(m.label),
                      selected: e.method == m,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => e.method = m),
                    );
                  }).toList()),
                  if (multi) ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: e.amount == e.amount.roundToDouble() ? e.amount.toStringAsFixed(0) : e.amount.toStringAsFixed(2),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Monto', prefixText: '\$ '),
                      onChanged: (v) => setState(() { e.amount = double.tryParse(v.replaceAll(',', '.')) ?? 0; _error = null; }),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: e.note,
                      decoration: const InputDecoration(labelText: 'Nota (opcional)', hintText: 'Referencia, comprobante...'),
                      onChanged: (v) => e.note = v,
                    ),
                  ],
                ]),
              );
            }),
            TextButton.icon(onPressed: _addEntry, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Agregar método de pago')),
            if (multi) ...[
              const SizedBox(height: 4),
              Row(children: [
                Text('Suma: ${formatCop(_sum)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: (_sum - widget.total).abs() > 1 ? AppTheme.danger : AppTheme.success)),
                const Spacer(),
                Text('Falta: ${formatCop((widget.total - _sum).clamp(0, double.infinity))}', style: const TextStyle(fontSize: 11, color: Color(0xFF78716C))),
              ]),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(fontSize: 12, color: AppTheme.danger, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _confirm,
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: Text('Confirmar pago · ${formatCop(widget.total)}'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.brand, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
