import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/cash_shift.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import 'sales_detail_screen.dart';

class CashShiftDetailScreen extends StatelessWidget {
  const CashShiftDetailScreen({super.key, required this.shift});

  final CashShift shift;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();
    final orders = repository.paidOrdersForShift(shift);
    final totals = repository.salesByPaymentMethodFor(orders);
    final sorted = [...orders]
      ..sort((a, b) => b.paidAtOrFallback.compareTo(a.paidAtOrFallback));

    return Scaffold(
      appBar: AppBar(title: Text(shift.label)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
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
                    const Icon(
                      Icons.point_of_sale_outlined,
                      color: AppTheme.brand,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Abierto ${formatDateTime(shift.openedAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                    Text(
                      shift.isClosed ? 'Cerrado' : 'En curso',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: shift.isClosed ? AppTheme.success : AppTheme.warning,
                      ),
                    ),
                  ],
                ),
                if (shift.closedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Cerrado ${formatDateTime(shift.closedAt!)} por '
                    '${shift.closedByName ?? 'Sistema'}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF78716C)),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        label: 'Total cobrado',
                        value: formatCop(shift.total),
                      ),
                    ),
                    Expanded(
                      child: _Metric(
                        label: 'Pedidos',
                        value: '${shift.orderCount}',
                      ),
                    ),
                  ],
                ),
                if (totals.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Métodos de pago',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...totals.entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(child: Text(entry.key.label)),
                          Text(
                            formatCop(entry.value),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (shift.closingAmount != null) ...[
                  const SizedBox(height: 14),
                  _Metric(
                    label: 'Valor contado',
                    value: formatCop(shift.closingAmount!),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Diferencia vs. efectivo: ${formatCop(shift.difference ?? 0)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: (shift.difference ?? 0).abs() < 0.01
                          ? AppTheme.success
                          : AppTheme.danger,
                    ),
                  ),
                ],
                if (shift.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    shift.notes.trim(),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF57534E),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SectionHeader(title: 'Ventas del turno'),
          if (sorted.isEmpty)
            const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Sin cobros en este turno',
              message: 'Los pagos registrados aparecerán aquí.',
            )
          else
            ...sorted.map(
              (order) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SaleTile(order: order),
              ),
            ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF78716C)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
      ],
    );
  }
}
