import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/order.dart';
import '../../core/models/restaurant_table.dart';
import '../../core/models/role.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/status_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../orders/new_order_screen.dart';
import '../orders/order_detail_screen.dart';

class TablesScreen extends StatelessWidget {
  const TablesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();
    final role = repository.role ?? UserRole.admin;
    final tables = repository.tables;

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
            child: Row(
              children: [
                _Counter(
                  label: 'Libres',
                  value: repository.freeTables,
                  color: AppTheme.success,
                ),
                const SizedBox(width: 8),
                _Counter(
                  label: 'Ocupadas',
                  value: repository.occupiedTables,
                  color: AppTheme.warning,
                ),
                const Spacer(),
                Text(
                  '${tables.length} mesas',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF78716C),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 760
                    ? 4
                    : constraints.maxWidth > 520
                        ? 3
                        : 2;
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.05,
                  ),
                  itemCount: tables.length,
                  itemBuilder: (context, index) {
                    final table = tables[index];
                    return _TableCard(
                      table: table,
                      order: table.currentOrderId == null
                          ? null
                          : repository.orderById(table.currentOrderId!),
                      onTap: () => _showTableSheet(
                        context,
                        repository,
                        role,
                        table,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showTableSheet(
    BuildContext context,
    RestaurantRepository repository,
    UserRole role,
    RestaurantTable table,
  ) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ChangeNotifierProvider<RestaurantRepository>.value(
        value: repository,
        child: _TableSheet(tableNumber: table.number, role: role),
      ),
    );
  }
}

class _TableSheet extends StatelessWidget {
  const _TableSheet({required this.tableNumber, required this.role});

  final int tableNumber;
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();
    final table = repository.tableByNumber(tableNumber);
    if (table == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('Mesa no encontrada')),
      );
    }
    final order = table.currentOrderId == null
        ? null
        : repository.orderById(table.currentOrderId!);
    final color = tableStatusColor(table.status);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  'Mesa ${table.number}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(
                label: table.status.label,
                color: color,
                icon: tableStatusIcon(table.status),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          Text(
            'Capacidad: ${table.capacity} personas',
            style: const TextStyle(fontSize: 12, color: Color(0xFF78716C)),
          ),
          if (order != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF8F5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEDEAE6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${order.code} · ${order.customerName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.ink,
                          ),
                        ),
                      ),
                      Text(
                        formatCop(order.total),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.brandDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${order.status.label} · ${order.itemCount} productos',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF78716C),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              OrderDetailScreen(orderId: order.id),
                        ),
                      );
                    },
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('Ver pedido'),
                  ),
                ],
              ),
            ),
          ],
          if (role.canManageTables) ...[
            const SizedBox(height: 16),
            const Text(
              'Cambiar estado',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: TableStatus.values.map((status) {
                return ChoiceChip(
                  label: Text(status.label),
                  selected: table.status == status,
                  onSelected: (_) =>
                      repository.updateTableStatus(table.number, status),
                  showCheckmark: false,
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (role.canCreateOrders)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => NewOrderScreen(
                            initialTableNumber: table.number,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Tomar pedido'),
                  ),
                ),
              if (table.status != TableStatus.libre) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    repository.freeTable(table.number);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Liberar'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.order,
    required this.onTap,
  });

  final RestaurantTable table;
  final Order? order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = tableStatusColor(table.status);
    final currentOrder = order;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.35)),
            gradient: LinearGradient(
              colors: [Colors.white, color.withValues(alpha: 0.06)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Mesa ${table.number}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(tableStatusIcon(table.status), size: 18, color: color),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${table.capacity} personas',
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFFA8A29E),
                ),
              ),
              const Spacer(),
              StatusPill(label: table.status.label, color: color),
              const SizedBox(height: 6),
              if (currentOrder != null)
                Text(
                  '${formatCop(currentOrder.total)} · ${currentOrder.itemCount} ítems',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF57534E),
                  ),
                )
              else
                const Text(
                  'Sin pedido activo',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFFA8A29E)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
