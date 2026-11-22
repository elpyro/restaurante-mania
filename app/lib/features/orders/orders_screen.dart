import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/order.dart';
import '../../core/models/role.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/order_card.dart';
import 'new_order_screen.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _searchController = TextEditingController();
  String _filter = 'all';

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
        if (a == null) return 1;
        if (b == null) return -1;
        return a.compareTo(b);
      });

    final widgets = <Widget>[];
    for (final key in keys) {
      final label = key == null ? 'Sin mesa' : 'Mesa $key';
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
        ),
      );
      for (final order in groups[key]!) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OrderCard(
              order: order,
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
    return widgets;
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
                hintText: 'Buscar por cÃ³digo, cliente o mesa',
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
      }
    } else {
      final next = order.status.next;
      if (next != null && _canAdvance(role, order.status)) {
        actions.add(
          FilledButton.tonalIcon(
            onPressed: () => repository.updateOrderStatus(order.id, next),
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: Text(next.label),
          ),
        );
      }
      if (role.canMarkPaid && order.paymentStatus == PaymentStatus.pending) {
        actions.add(
          OutlinedButton.icon(
            onPressed: () => repository.markOrderPaid(order.id),
            icon: const Icon(Icons.payments_outlined, size: 16),
            label: const Text('Cobrar'),
          ),
        );
      }
    }

    return actions;
  }

  bool _canAdvance(UserRole role, OrderStatus status) {
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
