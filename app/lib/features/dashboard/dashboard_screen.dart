import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/app_tab.dart';
import '../../core/models/order.dart';
import '../../core/models/role.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/status_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/order_card.dart';
import '../orders/new_order_screen.dart';
import '../inventory/inventory_screen.dart';
import '../inventory_losses/inventory_losses_screen.dart';
import '../orders/order_detail_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onNavigate});

  final void Function(AppTab tab) onNavigate;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();
    final role = repository.role ?? UserRole.admin;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => role == UserRole.cook
                ? const RegisterLossScreen()
                : const NewOrderScreen(),
          ),
        ),
        backgroundColor: AppTheme.brand,
        foregroundColor: Colors.white,
        icon: Icon(
          role == UserRole.cook
              ? Icons.report_problem_outlined
              : Icons.add_rounded,
        ),
        label: Text(
          role == UserRole.cook ? 'Registrar pérdida' : 'Nuevo pedido',
        ),
      ),
      body: RefreshIndicator(
        onRefresh: repository.refreshAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            if (!repository.isOnline) ...[
              _OfflineBanner(pending: repository.pendingSyncCount),
              const SizedBox(height: 12),
            ],
            _KpiGrid(
              repository: repository,
              role: role,
              onNavigate: onNavigate,
            ),
            if (role == UserRole.cook) ...[
              const SectionHeader(title: 'Cola de cocina'),
              _KitchenQueue(repository: repository),
              const SectionHeader(title: 'Pérdidas de ingredientes'),
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.report_problem_outlined,
                    color: AppTheme.danger,
                  ),
                  title: const Text(
                    'Registrar pérdida',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    repository.hasPendingInventoryLosses
                        ? '${repository.pendingInventoryLosses.length} registro(s) pendiente(s) de sincronizar'
                        : 'Caducados y mermas con foto y auditoría',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RegisterLossScreen(),
                    ),
                  ),
                ),
              ),
            ],
            if (role == UserRole.waiter) ...[
              SectionHeader(
                title: 'Mesas',
                action: TextButton(
                  onPressed: () => onNavigate(AppTab.tables),
                  child: const Text('Ver todas'),
                ),
              ),
              _TablesOverview(
                repository: repository,
                onTap: (tableNumber) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        NewOrderScreen(initialTableNumber: tableNumber),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.pending});

  final int pending;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 18,
            color: AppTheme.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pending > 0
                  ? 'Sin conexión. $pending pedido(s) se sincronizarán al volver.'
                  : 'Sin conexión. Los cambios se guardan en el dispositivo.',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9A3412),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({
    required this.repository,
    required this.role,
    required this.onNavigate,
  });

  final RestaurantRepository repository;
  final UserRole role;
  final void Function(AppTab tab) onNavigate;

  @override
  Widget build(BuildContext context) {
    final cards = switch (role) {
      UserRole.admin => [
        StatCard(
          label: 'Ventas hoy',
          value: formatCop(repository.todaySales),
          icon: Icons.payments_outlined,
          accent: AppTheme.success,
          subtitle: '${repository.todayOrderCount} pedidos',
          onTap: () => onNavigate(AppTab.reports),
        ),
        StatCard(
          label: 'Pedidos por cobrar',
          value: '${repository.ordersToCollect.length}',
          icon: Icons.payments_outlined,
          accent: AppTheme.warning,
          subtitle: '${repository.ordersToCollect.length} pendientes de pago',
          onTap: () => onNavigate(AppTab.orders),
        ),
        StatCard(
          label: 'En preparación',
          value: '${repository.preparingCount}',
          icon: Icons.soup_kitchen_outlined,
          accent: const Color(0xFF2563EB),
          onTap: () => onNavigate(AppTab.orders),
        ),
        StatCard(
          label: 'Pedidos listos',
          value: '${repository.readyCount}',
          icon: Icons.room_service_outlined,
          accent: AppTheme.success,
          onTap: () => onNavigate(AppTab.orders),
        ),
        StatCard(
          label: 'Ingredientes agotados',
          value: '${repository.ingredients.where((i) => i.stock <= 0).length}',
          icon: Icons.inventory_2_outlined,
          accent: AppTheme.danger,
          subtitle: '${repository.lowStockIngredients.length} con stock bajo',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const InventoryScreen(showAppBar: true),
            ),
          ),
        ),
        StatCard(
          label: 'Mesas ocupadas',
          value: '${repository.occupiedTables}/${repository.tables.length}',
          icon: Icons.table_restaurant_outlined,
          accent: const Color(0xFF2563EB),
          onTap: () => onNavigate(AppTab.tables),
        ),
      ],
      UserRole.cashier => [
        StatCard(
          label: 'Ventas hoy',
          value: formatCop(repository.todaySales),
          icon: Icons.payments_outlined,
          accent: AppTheme.success,
          onTap: () => onNavigate(AppTab.reports),
        ),
        StatCard(
          label: 'Pedidos por cobrar',
          value: '${repository.ordersToCollect.length}',
          icon: Icons.payments_outlined,
          accent: AppTheme.warning,
          onTap: () => onNavigate(AppTab.orders),
        ),
        StatCard(
          label: 'Listos para entregar',
          value: '${repository.readyCount}',
          icon: Icons.room_service_outlined,
          onTap: () => onNavigate(AppTab.orders),
        ),
        StatCard(
          label: 'Pedidos hoy',
          value: '${repository.todayOrderCount}',
          icon: Icons.receipt_long_outlined,
          accent: const Color(0xFF2563EB),
          onTap: () => onNavigate(AppTab.orders),
        ),
      ],
      UserRole.waiter => [
        StatCard(
          label: 'Mesas libres',
          value: '${repository.freeTables}',
          icon: Icons.check_circle_outline_rounded,
          accent: AppTheme.success,
          onTap: () => onNavigate(AppTab.tables),
        ),
        StatCard(
          label: 'Mesas ocupadas',
          value: '${repository.occupiedTables}',
          icon: Icons.groups_outlined,
          accent: const Color(0xFF2563EB),
          onTap: () => onNavigate(AppTab.tables),
        ),
        StatCard(
          label: 'Pedidos por cobrar',
          value: '${repository.ordersToCollect.length}',
          icon: Icons.payments_outlined,
          accent: AppTheme.warning,
          onTap: () => onNavigate(AppTab.orders),
        ),
        StatCard(
          label: 'Listos',
          value: '${repository.readyCount}',
          icon: Icons.room_service_outlined,
          accent: AppTheme.success,
          onTap: () => onNavigate(AppTab.orders),
        ),
      ],
      UserRole.cook => [
        StatCard(
          label: 'Pendientes',
          value: '${repository.pendingCount}',
          icon: Icons.hourglass_top_rounded,
          accent: AppTheme.warning,
          onTap: () => onNavigate(AppTab.orders),
        ),
        StatCard(
          label: 'En preparación',
          value: '${repository.preparingCount}',
          icon: Icons.soup_kitchen_outlined,
          onTap: () => onNavigate(AppTab.orders),
        ),
        StatCard(
          label: 'Listos',
          value: '${repository.readyCount}',
          icon: Icons.room_service_outlined,
          accent: AppTheme.success,
          onTap: () => onNavigate(AppTab.orders),
        ),
        StatCard(
          label: 'Pedidos hoy',
          value: '${repository.todayOrderCount}',
          icon: Icons.receipt_long_outlined,
          accent: const Color(0xFF2563EB),
          onTap: () => onNavigate(AppTab.orders),
        ),
      ],
    };

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: cards,
    );
  }
}

class _KitchenQueue extends StatelessWidget {
  const _KitchenQueue({required this.repository});

  final RestaurantRepository repository;

  @override
  Widget build(BuildContext context) {
    final queue = repository.activeOrders
        .where(
          (order) =>
              order.status == OrderStatus.pending ||
              order.status == OrderStatus.confirmed ||
              order.status == OrderStatus.preparing,
        )
        .toList();

    if (queue.isEmpty) {
      return const EmptyState(
        icon: Icons.soup_kitchen_outlined,
        title: 'Cocina al día',
        message: 'No hay pedidos pendientes de preparar.',
      );
    }

    return Column(
      children: queue
          .map(
            (order) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OrderCard(
                order: order,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => OrderDetailScreen(orderId: order.id),
                  ),
                ),
                actions: [
                  if (order.status == OrderStatus.pending ||
                      order.status == OrderStatus.confirmed)
                    FilledButton.tonalIcon(
                      onPressed: () => repository.updateOrderStatus(
                        order.id,
                        OrderStatus.preparing,
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 16),
                      label: const Text('Empezar'),
                    ),
                  if (order.status == OrderStatus.preparing)
                    FilledButton.icon(
                      onPressed: () => repository.updateOrderStatus(
                        order.id,
                        OrderStatus.ready,
                      ),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('Marcar listo'),
                    ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _TablesOverview extends StatelessWidget {
  const _TablesOverview({required this.repository, required this.onTap});

  final RestaurantRepository repository;
  final void Function(int tableNumber) onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: repository.tables.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final table = repository.tables[index];
          final color = tableStatusColor(table.status);
          return Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: () => onTap(table.number),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 96,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
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
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          tableStatusIcon(table.status),
                          size: 14,
                          color: color,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      table.status.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    Text(
                      '${table.capacity} personas',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFFA8A29E),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
