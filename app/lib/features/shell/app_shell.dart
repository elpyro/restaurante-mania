import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/app_tab.dart';
import '../../core/models/role.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../crm/crm_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../menu/menu_admin_screen.dart';
import '../more/more_screen.dart';
import '../orders/orders_screen.dart';
import '../reports/reports_screen.dart';
import '../tables/tables_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _navigate(AppTab tab) {
    final destinations = _destinationsFor(
      context.read<RestaurantRepository>().role ?? UserRole.admin,
    );
    final target = destinations.indexWhere((item) => item.tab == tab);
    if (target >= 0) setState(() => _index = target);
  }

  List<_Destination> _destinationsFor(UserRole role) {
    final dashboard = _Destination(
      tab: AppTab.dashboard,
      label: 'Inicio',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      builder: () => DashboardScreen(onNavigate: _navigate),
    );
    final orders = _Destination(
      tab: AppTab.orders,
      label: 'Pedidos',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      builder: () => const OrdersScreen(),
    );
    final tables = _Destination(
      tab: AppTab.tables,
      label: 'Mesas',
      icon: Icons.table_restaurant_outlined,
      selectedIcon: Icons.table_restaurant_rounded,
      builder: () => const TablesScreen(),
    );
    final menu = _Destination(
      tab: AppTab.menu,
      label: 'Menú',
      icon: Icons.restaurant_menu_outlined,
      selectedIcon: Icons.restaurant_menu_rounded,
      builder: () => const MenuAdminScreen(),
    );
    final reports = _Destination(
      tab: AppTab.reports,
      label: 'Reportes',
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart_rounded,
      builder: () => const ReportsScreen(),
    );
    final more = _Destination(
      tab: AppTab.more,
      label: 'Más',
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view_rounded,
      builder: () => const MoreScreen(),
    );
    final crm = _Destination(
      tab: AppTab.crm,
      label: 'CRM',
      icon: Icons.people_outline_rounded,
      selectedIcon: Icons.people_rounded,
      builder: () => const CrmScreen(),
    );

    return switch (role) {
      UserRole.admin => [dashboard, orders, crm, menu, more],
      UserRole.cashier => [dashboard, orders, tables, reports],
      UserRole.waiter => [dashboard, tables, orders, menu],
      UserRole.cook => [dashboard, orders, menu],
    };
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();
    final role = repository.role ?? UserRole.admin;
    final destinations = _destinationsFor(role);
    final index = _index < destinations.length ? _index : 0;
    final destination = destinations[index];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(destination.label),
            Text(
              '${role.label} · ${repository.currentUser?.name ?? ''}',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF78716C),
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Cuenta',
            onSelected: (value) {
              if (value == 'logout') repository.logout();
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      repository.currentUser?.name ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.ink,
                      ),
                    ),
                    Text(
                      repository.currentUser?.email ?? '',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF78716C),
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Cerrar sesión'),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.brand.withValues(alpha: 0.14),
                child: Text(
                  repository.currentUser?.initials ?? '?',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.brandDark,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(34),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                ConnectivityBadge(
                  online: repository.isOnline,
                  syncing: repository.isSyncing,
                ),
                const SizedBox(width: 8),
                if (repository.pendingSyncCount > 0)
                  Text(
                    '${repository.pendingSyncCount} pedido(s) por sincronizar',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.warning,
                    ),
                  )
                else
                  Text(
                    'Datos locales offline · ${repository.todayOrderCount} pedidos hoy',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFFA8A29E),
                    ),
                  ),
                const Spacer(),
                if (repository.pendingSyncCount > 0)
                  InkWell(
                    onTap: repository.isOnline
                        ? repository.syncPendingOrders
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Text(
                        'Sincronizar',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.brandDark,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: index,
        children: destinations.map((item) => item.builder()).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: destinations
            .map(
              (item) => NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.selectedIcon),
                label: item.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _Destination {
  const _Destination({
    required this.tab,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
  });

  final AppTab tab;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;
}
