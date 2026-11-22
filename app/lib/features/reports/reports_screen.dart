import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/order.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();
    final paidOrders = repository.orders
        .where((order) =>
            order.paymentStatus == PaymentStatus.paid &&
            order.status != OrderStatus.cancelled)
        .toList();
    final total = paidOrders.fold<double>(
      0,
      (sum, order) => sum + order.total,
    );
    final average = paidOrders.isEmpty ? 0.0 : total / paidOrders.length;
    final itemsSold =
        paidOrders.fold<int>(0, (sum, order) => sum + order.itemCount);
    final sales = repository.salesByDay(days: 7);
    final topProducts = repository.topProducts(limit: 5);
    final maxQuantity = topProducts.isEmpty
        ? 0
        : topProducts
            .map((product) => product.quantity)
            .reduce((a, b) => a > b ? a : b);
    final payments = repository.salesByPaymentMethod.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.5,
          children: [
            StatCard(
              label: 'Ventas cobradas',
              value: formatCop(total),
              icon: Icons.payments_outlined,
              accent: AppTheme.success,
              subtitle: '${paidOrders.length} pedidos',
            ),
            StatCard(
              label: 'Ticket promedio',
              value: formatCop(average),
              icon: Icons.trending_up_rounded,
              accent: const Color(0xFF2563EB),
            ),
            StatCard(
              label: 'Productos vendidos',
              value: '$itemsSold',
              icon: Icons.inventory_2_outlined,
            ),
            StatCard(
              label: 'Por cobrar',
              value: formatCop(repository.pendingPayments),
              icon: Icons.account_balance_wallet_outlined,
              accent: AppTheme.warning,
            ),
          ],
        ),
        const SectionHeader(title: 'Ventas de los últimos 7 días'),
        _SalesChart(sales: sales),
        const SectionHeader(title: 'Productos más vendidos'),
        if (topProducts.isEmpty)
          const EmptyState(
            icon: Icons.bar_chart_outlined,
            title: 'Aún no hay ventas registradas',
            message: 'Cuando cobres pedidos verás aquí el ranking de productos.',
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFEDEAE6)),
            ),
            child: Column(
              children: topProducts.map((product) {
                final ratio =
                    maxQuantity == 0 ? 0.0 : product.quantity / maxQuantity;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              product.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.ink,
                              ),
                            ),
                          ),
                          Text(
                            '${product.quantity} uds · ${formatCop(product.total)}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF78716C),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 6,
                          backgroundColor: const Color(0xFFF5F5F4),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppTheme.brand,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        const SectionHeader(title: 'Métodos de pago'),
        if (payments.isEmpty)
          const EmptyState(
            icon: Icons.credit_card_outlined,
            title: 'Sin pagos registrados',
            message: 'Los cobros aparecerán agrupados por método de pago.',
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFEDEAE6)),
            ),
            child: Column(
              children: payments.map((entry) {
                final ratio = total <= 0 ? 0.0 : entry.value / total;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 88,
                        child: Text(
                          entry.key.label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.ink,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 8,
                            backgroundColor: const Color(0xFFF5F5F4),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppTheme.success,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 86,
                        child: Text(
                          formatCop(entry.value),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF57534E),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.warning),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Reportes calculados con los pedidos pagados guardados en el dispositivo. '
                  'En producción se sincronizan con Firestore y se pueden exportar desde el panel web.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF92400E),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SalesChart extends StatelessWidget {
  const _SalesChart({required this.sales});

  final List<DailySales> sales;

  @override
  Widget build(BuildContext context) {
    final maxValue = sales.fold<double>(
      0,
      (max, entry) => entry.total > max ? entry.total : max,
    );
    const weekdays = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      child: SizedBox(
        height: 150,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: sales.map((entry) {
            final ratio = maxValue <= 0 ? 0.0 : entry.total / maxValue;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
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
                      height: 14 + ratio * 84,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.brand.withValues(alpha: 0.45),
                            AppTheme.brand,
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      weekdays[entry.day.weekday - 1],
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF78716C),
                      ),
                    ),
                    Text(
                      formatShortDate(entry.day),
                      style: const TextStyle(
                        fontSize: 8,
                        color: Color(0xFFA8A29E),
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
