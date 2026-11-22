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
import '../orders/order_detail_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onNavigate});

  final void Function(AppTab tab) onNavigate;

  String get _todayLabel {
    const weekdays = [
      'lunes',
      'martes',
      'miércoles',
      'jueves',
      'viernes',
      'sábado',
      'domingo',
    ];
    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    final now = DateTime.now();
    return '${weekdays[now.weekday - 1]}, ${now.day} de ${months[now.month - 1]}';
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Buenos días';
    if (hour < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();
    final role = repository.role ?? UserRole.admin;
    final firstName =
        (repository.currentUser?.name ?? 'equipo').split(' ').first;

    return RefreshIndicator(
      onRefresh: repository.syncPendingOrders,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _GreetingCard(
            greeting: _greeting,
            name: firstName,
            role: role,
            date: _todayLabel,
            isOpen: repository.settings.isOpen,
          ),
          if (!repository.isOnline) ...[
            const SizedBox(height: 12),
            _OfflineBanner(pending: repository.pendingSyncCount),
          ],
          const SizedBox(height: 14),
          _KpiGrid(repository: repository, role: role),
          SectionHeader(
            title: 'Acciones rápidas',
            action: Text(
              role.label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF78716C),
              ),
            ),
          ),
          _QuickActions(
            repository: repository,
            role: role,
            onNavigate: onNavigate,
          ),
          if (role == UserRole.cook) ...[
            const SectionHeader(title: 'Cola de cocina'),
            _KitchenQueue(repository: repository),
          ],
          if (role == UserRole.cashier) ...[
            const SectionHeader(title: 'Por cobrar'),
            _CashierQueue(repository: repository),
          ],
          if (role == UserRole.waiter || role == UserRole.admin) ...[
            SectionHeader(
              title: 'Mesas',
              action: TextButton(
                onPressed: () => onNavigate(AppTab.tables),
                child: const Text('Ver todas'),
              ),
            ),
            _TablesOverview(repository: repository),
          ],
          if (role == UserRole.admin || role == UserRole.cashier) ...[
            const SectionHeader(title: 'Ventas últimos 7 días'),
            _SalesSpark(repository: repository),
          ],
          SectionHeader(
            title: 'Pedidos recientes',
            action: TextButton(
              onPressed: () => onNavigate(AppTab.orders),
              child: const Text('Ver todos'),
            ),
          ),
          if (repository.orders.isEmpty)
            const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Todavía no hay pedidos',
              message: 'Cuando llegue un pedido aparecerá aquí en tiempo real.',
            )
          else
            ...repository.orders.take(4).map(
                  (order) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OrderCard(
                      order: order,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => OrderDetailScreen(orderId: order.id),
                        ),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({
    required this.greeting,
    required this.name,
    required this.role,
    required this.date,
    required this.isOpen,
  });

  final String greeting;
  final String name;
  final UserRole role;
  final String date;
  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.brand, AppTheme.brandDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brand.withValues(alpha: 0.25),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, $name 👋',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  date,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        role.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: (isOpen ? Colors.white : Colors.black)
                            .withValues(alpha: isOpen ? 0.18 : 0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isOpen ? 'Restaurante abierto' : 'Restaurante cerrado',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Text('🍽️', style: TextStyle(fontSize: 44)),
        ],
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
          const Icon(Icons.cloud_off_rounded, size: 18, color: AppTheme.warning),
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
  const _KpiGrid({required this.repository, required this.role});

  final RestaurantRepository repository;
  final UserRole role;

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
          ),
          StatCard(
            label: 'Por cobrar',
            value: formatCop(repository.pendingPayments),
            icon: Icons.account_balance_wallet_outlined,
            accent: AppTheme.warning,
          ),
          StatCard(
            label: 'Pedidos activos',
            value: '${repository.activeOrders.length}',
            icon: Icons.receipt_long_outlined,
            subtitle: '${repository.pendingCount} pendientes',
          ),
          StatCard(
            label: 'Mesas ocupadas',
            value: '${repository.occupiedTables}/${repository.tables.length}',
            icon: Icons.table_restaurant_outlined,
            accent: const Color(0xFF2563EB),
          ),
        ],
      UserRole.cashier => [
          StatCard(
            label: 'Ventas hoy',
            value: formatCop(repository.todaySales),
            icon: Icons.payments_outlined,
            accent: AppTheme.success,
          ),
          StatCard(
            label: 'Por cobrar',
            value: formatCop(repository.pendingPayments),
            icon: Icons.account_balance_wallet_outlined,
            accent: AppTheme.warning,
          ),
          StatCard(
            label: 'Listos para entregar',
            value: '${repository.readyCount}',
            icon: Icons.room_service_outlined,
          ),
          StatCard(
            label: 'Pedidos hoy',
            value: '${repository.todayOrderCount}',
            icon: Icons.receipt_long_outlined,
            accent: const Color(0xFF2563EB),
          ),
        ],
      UserRole.waiter => [
          StatCard(
            label: 'Mesas libres',
            value: '${repository.freeTables}',
            icon: Icons.check_circle_outline_rounded,
            accent: AppTheme.success,
          ),
          StatCard(
            label: 'Mesas ocupadas',
            value: '${repository.occupiedTables}',
            icon: Icons.groups_outlined,
            accent: const Color(0xFF2563EB),
          ),
          StatCard(
            label: 'Pedidos activos',
            value: '${repository.activeOrders.length}',
            icon: Icons.receipt_long_outlined,
          ),
          StatCard(
            label: 'Listos',
            value: '${repository.readyCount}',
            icon: Icons.room_service_outlined,
            accent: AppTheme.success,
          ),
        ],
      UserRole.cook => [
          StatCard(
            label: 'Pendientes',
            value: '${repository.pendingCount}',
            icon: Icons.hourglass_top_rounded,
            accent: AppTheme.warning,
          ),
          StatCard(
            label: 'En preparación',
            value: '${repository.preparingCount}',
            icon: Icons.soup_kitchen_outlined,
          ),
          StatCard(
            label: 'Listos',
            value: '${repository.readyCount}',
            icon: Icons.room_service_outlined,
            accent: AppTheme.success,
          ),
          StatCard(
            label: 'Pedidos hoy',
            value: '${repository.todayOrderCount}',
            icon: Icons.receipt_long_outlined,
            accent: const Color(0xFF2563EB),
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

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.repository,
    required this.role,
    required this.onNavigate,
  });

  final RestaurantRepository repository;
  final UserRole role;
  final void Function(AppTab tab) onNavigate;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (role.canCreateOrders)
          ActionChip(
            avatar: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Nuevo pedido'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NewOrderScreen(),
              ),
            ),
          ),
        ActionChip(
          avatar: const Icon(Icons.receipt_long_outlined, size: 16),
          label: const Text('Pedidos'),
          onPressed: () => onNavigate(AppTab.orders),
        ),
        if (role.canManageTables)
          ActionChip(
            avatar: const Icon(Icons.table_restaurant_outlined, size: 16),
            label: const Text('Mesas'),
            onPressed: () => onNavigate(AppTab.tables),
          ),
        if (role.canManageMenu)
          ActionChip(
            avatar: const Icon(Icons.restaurant_menu_outlined, size: 16),
            label: const Text('Menú'),
            onPressed: () => onNavigate(AppTab.menu),
          ),
        if (role.canSeeReports)
          ActionChip(
            avatar: const Icon(Icons.bar_chart_outlined, size: 16),
            label: const Text('Reportes'),
            onPressed: () => onNavigate(AppTab.reports),
          ),
        if (repository.pendingSyncCount > 0 && repository.isOnline)
          ActionChip(
            avatar: const Icon(Icons.cloud_upload_outlined, size: 16),
            label: Text('Sincronizar (${repository.pendingSyncCount})'),
            onPressed: repository.syncPendingOrders,
          ),
      ],
    );
  }
}

class _KitchenQueue extends StatelessWidget {
  const _KitchenQueue({required this.repository});

  final RestaurantRepository repository;

  @override
  Widget build(BuildContext context) {
    final queue = repository.activeOrders
        .where((order) =>
            order.status == OrderStatus.pending ||
            order.status == OrderStatus.confirmed ||
            order.status == OrderStatus.preparing)
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
                      onPressed: () =>
                          repository.updateOrderStatus(order.id, OrderStatus.preparing),
                      icon: const Icon(Icons.play_arrow_rounded, size: 16),
                      label: const Text('Empezar'),
                    ),
                  if (order.status == OrderStatus.preparing)
                    FilledButton.icon(
                      onPressed: () =>
                          repository.updateOrderStatus(order.id, OrderStatus.ready),
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

class _CashierQueue extends StatelessWidget {
  const _CashierQueue({required this.repository});

  final RestaurantRepository repository;

  @override
  Widget build(BuildContext context) {
    final queue = repository.orders
        .where((order) =>
            order.paymentStatus == PaymentStatus.pending &&
            order.status != OrderStatus.cancelled)
        .take(4)
        .toList();

    if (queue.isEmpty) {
      return const EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Todo cobrado',
        message: 'No hay cuentas pendientes por cobrar.',
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
                  FilledButton.tonalIcon(
                    onPressed: () => repository.markOrderPaid(order.id),
                    icon: const Icon(Icons.payments_outlined, size: 16),
                    label: const Text('Cobrar'),
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
  const _TablesOverview({required this.repository});

  final RestaurantRepository repository;

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
          return Container(
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
                    Icon(tableStatusIcon(table.status), size: 14, color: color),
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
          );
        },
      ),
    );
  }
}

class _SalesSpark extends StatelessWidget {
  const _SalesSpark({required this.repository});

  final RestaurantRepository repository;

  @override
  Widget build(BuildContext context) {
    final sales = repository.salesByDay(days: 7);
    final maxValue = sales.fold<double>(
      0,
      (max, entry) => entry.total > max ? entry.total : max,
    );
    const weekdays = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      child: SizedBox(
        height: 120,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: sales.map((entry) {
            final ratio = maxValue <= 0 ? 0.0 : entry.total / maxValue;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      entry.total <= 0 ? '' : '${(entry.total / 1000).round()}k',
                      style: const TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF78716C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 12 + ratio * 62,
                      decoration: BoxDecoration(
                        color: AppTheme.brand.withValues(alpha: 0.25 + ratio * 0.75),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      weekdays[entry.day.weekday - 1],
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF78716C),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
