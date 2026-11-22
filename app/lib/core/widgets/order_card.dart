import 'package:flutter/material.dart';

import '../models/order.dart';
import '../theme/app_theme.dart';
import '../theme/status_colors.dart';
import '../utils/formatters.dart';
import 'common.dart';

class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.order,
    this.onTap,
    this.actions = const [],
  });

  final Order order;
  final VoidCallback? onTap;
  final List<Widget> actions;

  IconData get _typeIcon => switch (order.type) {
        OrderType.pickup => Icons.shopping_bag_outlined,
        OrderType.delivery => Icons.delivery_dining_outlined,
        OrderType.table => Icons.table_restaurant_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final statusColor = orderStatusColor(order.status);
    final itemsSummary = order.items
        .take(3)
        .map((item) => '${item.quantity}× ${item.name}')
        .join(' · ');
    final remaining = order.items.length - 3;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEDEAE6)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x081C1917),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(_typeIcon, size: 16, color: const Color(0xFF78716C)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            order.code,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                              color: AppTheme.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!order.synced) ...[
                    const Tooltip(
                      message: 'Pendiente de sincronizar',
                      child: Icon(
                        Icons.cloud_off_rounded,
                        size: 15,
                        color: AppTheme.warning,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  StatusPill(
                    label: order.status.label,
                    color: statusColor,
                    icon: orderStatusIcon(order.status),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                order.customerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${relativeTime(order.createdAt)} · ${order.type.label}'
                '${order.tableNumber != null ? ' ${order.tableNumber}' : ''}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF78716C),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                remaining > 0
                    ? '$itemsSummary · +$remaining más'
                    : itemsSummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF57534E),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  StatusPill(
                    label: order.paymentStatus.label,
                    color: paymentColor(order.paymentStatus),
                  ),
                  const Spacer(),
                  Text(
                    formatCop(order.total),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.brandDark,
                    ),
                  ),
                ],
              ),
              if (actions.isNotEmpty) ...[
                const Divider(height: 20),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
