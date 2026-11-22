import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/role.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../inventory/inventory_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();
    final role = repository.role ?? UserRole.admin;
    final user = repository.currentUser;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.brand, AppTheme.brandDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: Text(
                  user?.initials ?? '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.name ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${role.label} · ${user?.email ?? ''}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEDEAE6)),
          ),
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  repository.isOnline
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_rounded,
                  color:
                      repository.isOnline ? AppTheme.success : AppTheme.warning,
                ),
                title: Text(
                  repository.isOnline ? 'En línea' : 'Sin conexión',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  repository.pendingSyncCount > 0
                      ? '${repository.pendingSyncCount} pedido(s) por sincronizar'
                      : 'Todos los pedidos están sincronizados',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: repository.isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        tooltip: 'Sincronizar',
                        onPressed: repository.isOnline &&
                                !repository.isSyncing
                            ? repository.syncPendingOrders
                            : null,
                        icon: const Icon(Icons.sync_rounded),
                      ),
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: const Icon(Icons.schedule_rounded, size: 20),
                title: const Text(
                  'Última sincronización',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  repository.lastSync == null
                      ? 'Nunca'
                      : formatDateTime(repository.lastSync!),
                  style: const TextStyle(fontSize: 10.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _MenuTile(
          icon: Icons.bar_chart_rounded,
          label: 'Reportes de ventas',
          subtitle: 'Ventas, ticket promedio y productos top',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ReportsScreen()),
          ),
        ),
        _MenuTile(
          icon: Icons.settings_outlined,
          label: 'Configuración',
          subtitle: 'Restaurante, conexión y datos demo',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
        ),
        _MenuTile(
          icon: Icons.inventory_2_outlined,
          label: 'Inventario',
          subtitle:
              '${repository.ingredients.length} insumos · ${repository.lowStockIngredients.length} con stock bajo',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const InventoryScreen()),
          ),
        ),
        _MenuTile(
          icon: Icons.restaurant_menu_outlined,
          label: 'Menú',
          subtitle: '${repository.menuItems.length} productos registrados',
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Usa la pestaña Menú para gestionar productos.'),
              ),
            );
          },
        ),
        _MenuTile(
          icon: Icons.info_outline_rounded,
          label: 'Acerca de',
          subtitle: 'Restaurante Manía POS · versión 1.0.0',
          onTap: () => showAboutDialog(
            context: context,
            applicationName: 'Restaurante Manía POS',
            applicationVersion: '1.0.0',
            applicationLegalese:
                'Sistema integral de restaurantes · Flutter + Firebase ready',
            children: const [
              SizedBox(height: 12),
              Text(
                'App administrativa con arquitectura feature-first, persistencia '
                'offline y cola de sincronización. Roles de administrador, cajero, '
                'mesero y cocinero. La web pública crea pedidos que llegan aquí '
                'en tiempo real al conectar Firestore.',
                style: TextStyle(fontSize: 12, height: 1.45),
              ),
            ],
          ),
        ),
        _MenuTile(
          icon: Icons.logout_rounded,
          label: 'Cerrar sesión',
          subtitle: 'Volver a la pantalla de acceso',
          danger: true,
          onTap: repository.logout,
        ),
      ],
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
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
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (danger ? AppTheme.danger : AppTheme.brand)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 19,
                    color: danger ? AppTheme.danger : AppTheme.brandDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: danger ? AppTheme.danger : AppTheme.ink,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF78716C),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFA8A29E),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
