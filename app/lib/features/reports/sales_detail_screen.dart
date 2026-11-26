import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/order.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../orders/order_detail_screen.dart';

class SalesDetailScreen extends StatelessWidget {
  const SalesDetailScreen({super.key, required this.orders});

  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    final total = orders.fold<double>(0, (sum, order) => sum + order.total);
    final sorted = [...orders]
      ..sort((a, b) => b.paidAtOrFallback.compareTo(a.paidAtOrFallback));

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de ventas cobradas')),
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
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.payments_outlined,
                      size: 20, color: AppTheme.success),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total cobrado',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF78716C),
                        ),
                      ),
                      Text(
                        formatCop(total),
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${sorted.length} op.',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF78716C),
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'Operaciones realizadas'),
          if (sorted.isEmpty)
            const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Sin operaciones cobradas',
              message: 'Los cobros aparecerán aquí cuando se paguen pedidos.',
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

class SaleTile extends StatelessWidget {
  const SaleTile({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final settings = context.read<RestaurantRepository>().settings;
    final customer = order.customerName.trim().isEmpty
        ? 'Mesa ${order.tableNumber ?? '-'}'
        : order.customerName.trim();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => OrderDetailScreen(orderId: order.id),
          ),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEDEAE6)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.check_circle_outline_rounded,
                    size: 18, color: AppTheme.success),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.code,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatDateTime(order.paidAtOrFallback),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF78716C),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Cobrado por: ${order.paidByNameOrFallback} · '
                      '${settings.paymentLabel(order.paymentMethod.name)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.brandDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$customer · ${order.itemCount} producto(s)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF78716C),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatCop(order.total),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    order.status.label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.success,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
