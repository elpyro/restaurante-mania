import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/order.dart';
import '../../core/models/role.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/status_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';

class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return Consumer<RestaurantRepository>(
      builder: (context, repository, _) {
        final order = repository.orderById(orderId);
        if (order == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Pedido')),
            body: const Padding(
              padding: EdgeInsets.all(16),
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Pedido no encontrado',
                message: 'Puede que se haya eliminado o reiniciado la demo.',
              ),
            ),
          );
        }
        final role = repository.role ?? UserRole.admin;
        final target = _primaryTarget(role, order);
        final canPay =
            role.canMarkPaid && order.paymentStatus == PaymentStatus.pending;

        return Scaffold(
          appBar: AppBar(
            title: Text(order.code),
            actions: [
              if (role.canCancelOrders && order.status.isActive)
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value != 'cancel') return;
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Cancelar pedido'),
                        content: Text(
                          '¿Cancelar el pedido ${order.code}? Esta acción no se puede deshacer.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: const Text('Volver'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.danger,
                            ),
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: const Text('Cancelar pedido'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await repository.cancelOrder(order.id);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'cancel',
                      child: Row(
                        children: [
                          Icon(Icons.cancel_outlined,
                              size: 18, color: AppTheme.danger),
                          SizedBox(width: 8),
                          Text('Cancelar pedido'),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              _HeaderCard(order: order),
              if (order.status == OrderStatus.cancelled) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFECDD3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.cancel_outlined,
                          color: AppTheme.danger, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Este pedido fue cancelado. No requiere preparación.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF9F1239),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SectionHeader(title: 'Progreso'),
                _Timeline(order: order),
              ],
              const SectionHeader(title: 'Productos'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFEDEAE6)),
                ),
                child: Column(
                  children: [
                    ...order.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          children: [
                            Text(item.emoji,
                                style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item.quantity} × ${item.name}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.ink,
                                    ),
                                  ),
                                  Text(
                                    '${formatCop(item.price)} c/u',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: Color(0xFF78716C),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              formatCop(item.subtotal),
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 20),
                    _TotalRow(label: 'Subtotal', value: order.subtotal),
                    _TotalRow(
                      label: 'Impuestos',
                      value: order.tax,
                      valueLabel: order.tax == 0 ? 'Incluidos' : null,
                    ),
                    const SizedBox(height: 4),
                    _TotalRow(
                      label: 'Total',
                      value: order.total,
                      emphasize: true,
                    ),
                  ],
                ),
              ),
              if (order.notes.trim().isNotEmpty) ...[
                const SectionHeader(title: 'Notas de la cocina'),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Text(
                    order.notes,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF92400E),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              const SectionHeader(title: 'Sincronización'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEDEAE6)),
                ),
                child: Row(
                  children: [
                    Icon(
                      order.synced
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_rounded,
                      size: 20,
                      color: order.synced ? AppTheme.success : AppTheme.warning,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        order.synced
                            ? 'Pedido sincronizado correctamente.'
                            : 'Guardado en el dispositivo. Se enviará al recuperar la conexión.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF57534E),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFEDEAE6))),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  if (order.tableNumber != null && role.canManageTables)
                    TextButton(
                      onPressed: () async {
                        await repository.freeTable(order.tableNumber!);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Mesa ${order.tableNumber} liberada.',
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text('Liberar mesa'),
                    ),
                  if (canPay)
                    OutlinedButton.icon(
                      onPressed: () async {
                        await repository.markOrderPaid(order.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Pedido cobrado: ${formatCop(order.total)}',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.payments_outlined, size: 17),
                      label: Text('Cobrar ${formatCop(order.total)}'),
                    ),
                  if (target != null)
                    FilledButton.icon(
                      onPressed: () async {
                        await repository.updateOrderStatus(order.id, target);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Pedido actualizado a ${target.label}.',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                      label: Text('Marcar ${target.label.toLowerCase()}'),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  OrderStatus? _primaryTarget(UserRole role, Order order) {
    if (!order.status.isActive) return null;
    if (role == UserRole.cook) {
      if (order.status == OrderStatus.pending ||
          order.status == OrderStatus.confirmed) {
        return OrderStatus.preparing;
      }
      if (order.status == OrderStatus.preparing) return OrderStatus.ready;
      return null;
    }
    if (role == UserRole.waiter) {
      if (order.status == OrderStatus.pending) return OrderStatus.confirmed;
      if (order.status == OrderStatus.ready) return OrderStatus.delivered;
      return null;
    }
    if (role == UserRole.cashier) {
      if (order.status == OrderStatus.pending) return OrderStatus.confirmed;
      if (order.status == OrderStatus.ready) return OrderStatus.delivered;
      return null;
    }
    return order.status.next;
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final color = orderStatusColor(order.status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusPill(
                label: order.status.label,
                color: color,
                icon: orderStatusIcon(order.status),
              ),
              const Spacer(),
              StatusPill(
                label: order.paymentStatus.label,
                color: paymentColor(order.paymentStatus),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            order.customerName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            order.customerPhone,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF78716C),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(
                icon: switch (order.type) {
                  OrderType.pickup => Icons.shopping_bag_outlined,
                  OrderType.delivery => Icons.delivery_dining_outlined,
                  OrderType.table => Icons.table_restaurant_outlined,
                },
                label: order.tableNumber != null
                    ? '${order.type.label} ${order.tableNumber}'
                    : order.type.label,
              ),
              _MetaChip(
                icon: Icons.schedule_rounded,
                label: formatDateTime(order.createdAt),
              ),
              _MetaChip(
                icon: Icons.payments_outlined,
                label: order.paymentMethod.label,
              ),
              _MetaChip(
                icon: Icons.inventory_2_outlined,
                label: '${order.itemCount} unidades',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            formatCop(order.total),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppTheme.brandDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF78716C)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF57534E),
            ),
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    const timeline = [
      OrderStatus.pending,
      OrderStatus.confirmed,
      OrderStatus.preparing,
      OrderStatus.ready,
      OrderStatus.delivered,
    ];
    final current = timeline.indexOf(order.status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      child: Row(
        children: List.generate(timeline.length, (index) {
          final status = timeline[index];
          final done = index <= current;
          final color = done ? AppTheme.success : const Color(0xFFD6D3D1);
          return Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 2,
                        color: index == 0
                            ? Colors.transparent
                            : (index <= current
                                ? AppTheme.success
                                : const Color(0xFFE7E5E4)),
                      ),
                    ),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        done ? Icons.check_rounded : Icons.circle,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 2,
                        color: index == timeline.length - 1
                            ? Colors.transparent
                            : (index < current
                                ? AppTheme.success
                                : const Color(0xFFE7E5E4)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  status.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight:
                        done ? FontWeight.w700 : FontWeight.w500,
                    color: done
                        ? const Color(0xFF57534E)
                        : const Color(0xFFA8A29E),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.valueLabel,
    this.emphasize = false,
  });

  final String label;
  final double value;
  final String? valueLabel;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: emphasize ? 14 : 12,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w500,
              color: emphasize ? AppTheme.ink : const Color(0xFF78716C),
            ),
          ),
          const Spacer(),
          Text(
            valueLabel ?? formatCop(value),
            style: TextStyle(
              fontSize: emphasize ? 16 : 12,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              color: emphasize ? AppTheme.brandDark : AppTheme.ink,
            ),
          ),
        ],
      ),
    );
  }
}
