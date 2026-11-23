import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/order.dart';
import '../../core/models/role.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/order_card.dart';
import 'new_order_screen.dart';
import 'order_detail_screen.dart';
import 'payment_sheet.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _searchController = TextEditingController();
  String _filter = 'active';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesFilter(Order order) {
    return switch (_filter) {
      'active' => order.status.isActive,
      'pending' => order.status == OrderStatus.pending,
      'preparing' => order.status == OrderStatus.preparing,
      'ready' => order.status == OrderStatus.ready,
      'delivered' => order.status == OrderStatus.delivered,
      _ => true,
    };
  }

  bool _matchesSearch(Order order) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    return order.code.toLowerCase().contains(query) ||
        order.customerName.toLowerCase().contains(query) ||
        (order.tableNumber?.toString() ?? '').contains(query);
  }
  List<Widget> _groupedOrderWidgets(
    BuildContext context,
    RestaurantRepository repository,
    UserRole role,
    List<Order> orders,
  ) {
    final groups = <int?, List<Order>>{};
    for (final order in orders) {
      groups.putIfAbsent(order.tableNumber, () => <Order>[]).add(order);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        final aOldest = groups[a]!
            .map((o) => o.createdAt)
            .reduce((x, y) => x.isBefore(y) ? x : y);
        final bOldest = groups[b]!
            .map((o) => o.createdAt)
            .reduce((x, y) => x.isBefore(y) ? x : y);
        return aOldest.compareTo(bOldest);
      });

    final widgets = <Widget>[];
    for (final key in keys) {
      final group = groups[key]!
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final label = key == null ? 'Sin mesa' : 'Mesa $key';
      final hasMultiple = key != null && group.length > 1;
      final hasNewOrder = hasMultiple &&
          group.any((o) =>
              o.status == OrderStatus.pending ||
              o.status == OrderStatus.confirmed) &&
          group.any((o) =>
              o.status == OrderStatus.preparing ||
              o.status == OrderStatus.ready);

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              if (hasMultiple) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Text(
                    '${group.length} pedidos',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1D4ED8),
                    ),
                  ),
                ),
              ],
              if (hasNewOrder) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                  ),
                  child: const Text(
                    'Nuevo pedido en mesa',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );

      if (hasMultiple) {
        widgets.add(
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 4),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < group.length; i++) ...[
                    SizedBox(
                      width: 292,
                      child: OrderCard(
                        order: group[i],
                        sequenceLabel: '${i + 1}/${group.length}',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                OrderDetailScreen(orderId: group[i].id),
                          ),
                        ),
                        actions: _actionsFor(
                            context, repository, role, group[i]),
                      ),
                    ),
                    if (i < group.length - 1) const SizedBox(width: 10),
                  ],
                ],
              ),
            ),
          ),
        );
        widgets.add(const SizedBox(height: 8));
      } else {
        for (final order in group) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OrderCard(
                order: order,
                sequenceLabel:
                    key != null ? repository.tableOrderSequence(order) : null,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => OrderDetailScreen(orderId: order.id),
                  ),
                ),
                actions: _actionsFor(context, repository, role, order),
              ),
            ),
          );
        }
      }

      final payable =
          key == null ? <Order>[] : repository.payableTableOrders(key);
      if (payable.isNotEmpty && role.canMarkPaid) {
        final total = payable.fold<double>(0, (s, o) => s + o.total);
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: FilledButton.icon(
              onPressed: () =>
                  _confirmGroupPayment(context, repository, key!, payable, total),
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: Text(
                hasMultiple
                    ? 'Cobrar ${payable.length}/${group.length} pedidos · ${formatCop(total)}'
                    : 'Pagar $label · ${formatCop(total)}',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brand,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  Future<void> _confirmGroupPayment(
    BuildContext context,
    RestaurantRepository repository,
    int tableNumber,
    List<Order> payable,
    double total,
  ) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cobrar Mesa $tableNumber',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                '${payable.length}/${payable.length} pedidos a cancelar · pago automático de todos los pedidos',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF78716C),
                ),
              ),
              const SizedBox(height: 12),
              ...payable.asMap().entries.map((entry) {
                final index = entry.key + 1;
                final order = entry.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF8F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEDEAE6)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$index/${payable.length}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.code,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.ink,
                              ),
                            ),
                            Text(
                              '${order.itemCount} productos · ${order.status.label}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF78716C),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatCop(order.total),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.brandDark,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const Divider(height: 20),
              Row(
                children: [
                  const Text(
                    'Total a cobrar',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formatCop(total),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.brandDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: Text('Continuar al pago · ${formatCop(total)}'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    final payments = await showPaymentSheet(
      context,
      total: total,
      title: 'Cobrar Mesa $tableNumber',
      subtitle: '${payable.length} pedidos · ${formatCop(total)}',
    );
    if (payments == null) return;
    await repository.markGroupPaid(tableNumber, payments: payments);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${payable.length} pedidos cobrados · ${formatCop(total)}',
          ),
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();
    final role = repository.role ?? UserRole.admin;
    final orders = repository.orders
        .where((order) => _matchesFilter(order) && _matchesSearch(order))
        .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: role.canCreateOrders
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const NewOrderScreen(),
                ),
              ),
              backgroundColor: AppTheme.brand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuevo pedido'),
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
                hintText: 'Buscar por código, cliente o mesa',
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
                _FilterChip(
                  label: 'Todos',
                  value: 'all',
                  selected: _filter,
                  onSelected: (value) => setState(() => _filter = value),
                ),
                _FilterChip(
                  label: 'Activos',
                  value: 'active',
                  selected: _filter,
                  onSelected: (value) => setState(() => _filter = value),
                ),
                _FilterChip(
                  label: 'Pendientes',
                  value: 'pending',
                  selected: _filter,
                  onSelected: (value) => setState(() => _filter = value),
                ),
                _FilterChip(
                  label: 'Preparando',
                  value: 'preparing',
                  selected: _filter,
                  onSelected: (value) => setState(() => _filter = value),
                ),
                _FilterChip(
                  label: 'Listos',
                  value: 'ready',
                  selected: _filter,
                  onSelected: (value) => setState(() => _filter = value),
                ),
                _FilterChip(
                  label: 'Entregados',
                  value: 'delivered',
                  selected: _filter,
                  onSelected: (value) => setState(() => _filter = value),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Text(
                  '${orders.length} pedido(s)',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF78716C),
                  ),
                ),
                const Spacer(),
                if (repository.pendingSyncCount > 0)
                  Text(
                    '${repository.pendingSyncCount} sin sincronizar',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.warning,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: orders.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: const [
                      EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No hay pedidos con este filtro',
                        message:
                            'Prueba con otro estado o crea un pedido nuevo.',
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    children: _groupedOrderWidgets(
                      context,
                      repository,
                      role,
                      orders,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _actionsFor(
    BuildContext context,
    RestaurantRepository repository,
    UserRole role,
    Order order,
  ) {
    final actions = <Widget>[];

    Future<void> markSent() async {
      final skipping = order.status != OrderStatus.ready;
      if (skipping) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Marcar como enviado'),
            content: const Text(
              '¿Seguro que deseas marcar este domicilio como enviado? '
              'Se saltarán estados intermedios y se descontarán los ingredientes '
              'si aún no se habían descontado.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('No, esperar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Sí, enviar'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
      await repository.updateOrderStatus(order.id, OrderStatus.sent);
    }

    if (role == UserRole.cook) {
      if (order.status == OrderStatus.pending ||
          order.status == OrderStatus.confirmed) {
        actions.add(
          FilledButton.tonalIcon(
            onPressed: () =>
                repository.updateOrderStatus(order.id, OrderStatus.preparing),
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: const Text('Empezar'),
          ),
        );
      } else if (order.status == OrderStatus.preparing) {
        actions.add(
          FilledButton.icon(
            onPressed: () =>
                repository.updateOrderStatus(order.id, OrderStatus.ready),
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Marcar listo'),
          ),
        );
      } else if (order.type == OrderType.delivery &&
          order.status == OrderStatus.ready) {
        actions.add(
          FilledButton.icon(
            onPressed: markSent,
            icon: const Icon(Icons.local_shipping_outlined, size: 16),
            label: const Text('Marcar enviado'),
          ),
        );
      }
      if (order.type == OrderType.delivery &&
          order.status.isActive &&
          order.status != OrderStatus.ready) {
        actions.add(
          OutlinedButton.icon(
            onPressed: markSent,
            icon: const Icon(Icons.local_shipping_outlined, size: 16),
            label: const Text('Enviado'),
          ),
        );
      }
    } else {
      OrderStatus? target;
      if (role == UserRole.waiter || role == UserRole.cashier) {
        if (order.status == OrderStatus.pending) {
          target = OrderStatus.confirmed;
        } else if (order.status == OrderStatus.confirmed) {
          target = order.type == OrderType.delivery
              ? OrderStatus.sent
              : OrderStatus.delivered;
        } else if (order.status == OrderStatus.ready) {
          target = order.type == OrderType.delivery
              ? OrderStatus.sent
              : OrderStatus.delivered;
        }
      } else {
        target = order.status.nextFor(order.type);
      }

      if (target != null && _canAdvance(role, order)) {
        actions.add(
          FilledButton.tonalIcon(
            onPressed: () async {
              if (target == OrderStatus.sent) {
                await markSent();
                return;
              }
              final skippingPrep =
                  (role == UserRole.waiter || role == UserRole.cashier) &&
                      order.status == OrderStatus.confirmed &&
                      target == OrderStatus.delivered;
              if (skippingPrep) {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Confirmar entrega'),
                    content: const Text(
                      '¿El pedido ya fue preparado y está listo para entregar? '
                      'Si continúas, se marcará como entregado y se descontarán '
                      'los ingredientes si aún no se habían descontado.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(false),
                        child: const Text('No, esperar'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(true),
                        child: const Text('Sí, entregar'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
              }
              await repository.updateOrderStatus(order.id, target!);
            },
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: Text(target.label),
          ),
        );
      }

      if (order.type == OrderType.delivery &&
          order.status.isActive &&
          target != OrderStatus.sent) {
        actions.add(
          OutlinedButton.icon(
            onPressed: markSent,
            icon: const Icon(Icons.local_shipping_outlined, size: 16),
            label: const Text('Enviado'),
          ),
        );
      }

      if (role.canMarkPaid && order.paymentStatus == PaymentStatus.pending) {
        actions.add(
          OutlinedButton.icon(
            onPressed: () async {
              final payments = await showPaymentSheet(
                context,
                total: order.total,
                title: 'Cobrar ${order.code}',
                subtitle: order.customerName,
              );
              if (payments == null) return;
              await repository.markOrderPaid(order.id, payments: payments);
            },
            icon: const Icon(Icons.payments_outlined, size: 16),
            label: const Text('Cobrar'),
          ),
        );
      }
    }

    return actions;
  }

  bool _canAdvance(UserRole role, Order order) {
    final status = order.status;
    if (!status.isActive) return false;
    if (order.type == OrderType.delivery && status != OrderStatus.sent) {
      return true; // todos pueden avanzar/enviar domicilios activos
    }
    return switch (role) {
      UserRole.cook => status == OrderStatus.pending ||
          status == OrderStatus.confirmed ||
          status == OrderStatus.preparing,
      UserRole.waiter => status == OrderStatus.pending ||
          status == OrderStatus.confirmed ||
          status == OrderStatus.ready,
      UserRole.cashier => status == OrderStatus.pending ||
          status == OrderStatus.confirmed ||
          status == OrderStatus.ready,
      UserRole.admin => true,
    };
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onSelected(value),
        labelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isSelected ? Colors.white : const Color(0xFF57534E),
        ),
        selectedColor: AppTheme.ink,
        backgroundColor: Colors.white,
        showCheckmark: false,
        side: BorderSide(
          color: isSelected ? AppTheme.ink : const Color(0xFFE7E5E4),
        ),
      ),
    );
  }
}
