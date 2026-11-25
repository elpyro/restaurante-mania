import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/cash_shift.dart';
import '../../core/models/order.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import 'cash_shift_detail_screen.dart';
import 'sales_detail_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.showAppBar = false});

  final bool showAppBar;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _historical = false;
  int _rangeDays = 7;
  DateTime? _customStart;
  DateTime? _customEnd;
  bool _closing = false;

  DateTime _rangeStart() {
    if (_customStart != null) return _customStart!;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: _rangeDays - 1));
  }

  DateTime _rangeEnd() {
    if (_customEnd != null) return _customEnd!;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  List<Order> _scopedOrders(RestaurantRepository repository) =>
      _historical
          ? repository.paidOrdersInRange(_rangeStart(), _rangeEnd())
          : repository.currentShiftOrders;

  SalesBucket _bucket() {
    if (!_historical) return SalesBucket.hour;
    if (_customStart != null) {
      final days = _rangeEnd().difference(_rangeStart()).inDays;
      if (days <= 14) return SalesBucket.day;
      if (days <= 90) return SalesBucket.week;
      return SalesBucket.month;
    }
    if (_rangeDays <= 14) return SalesBucket.day;
    if (_rangeDays <= 90) return SalesBucket.week;
    return SalesBucket.month;
  }

  List<DailySales> _chart(RestaurantRepository repository) => _historical
      ? repository.salesInRange(
          start: _rangeStart(),
          end: _rangeEnd(),
          bucket: _bucket(),
        )
      : repository.salesForShift(repository.activeShift);

  String _rangeLabel() {
    if (!_historical) return 'Ventas del turno actual';
    if (_customStart != null && _customEnd != null) {
      return 'Ventas del ${formatShortDate(_rangeStart())} al '
          '${formatShortDate(_rangeEnd())}';
    }
    return 'Ventas de los últimos $_rangeDays días';
  }

  void _selectDays(int days) {
    setState(() {
      _historical = true;
      _rangeDays = days;
      _customStart = null;
      _customEnd = null;
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: DateTimeRange(start: _rangeStart(), end: now),
      helpText: 'Rango de ventas',
      locale: Localizations.localeOf(context),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _historical = true;
      _customStart = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _customEnd = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
        23,
        59,
        59,
      );
    });
  }

  Future<void> _closeShift(RestaurantRepository repository) async {
    final shift = repository.activeShift;
    final orders = repository.currentShiftOrders;
    final totals = repository.salesByPaymentMethodFor(orders);
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.point_of_sale_outlined, color: AppTheme.brand),
        title: const Text('Cerrar caja'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${shift.label} · ${orders.length} pedido(s)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 10),
              _SummaryRow(
                label: 'Total cobrado',
                value: formatCop(
                  orders.fold(0, (sum, order) => sum + order.total),
                ),
              ),
              ...totals.entries.map(
                (entry) => _SummaryRow(
                  label: entry.key.label,
                  value: formatCop(entry.value),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor contado en efectivo (opcional)',
                  prefixText: '\$ ',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                r'Se guardará el turno y empezará uno nuevo en $ 0.',
                style: TextStyle(fontSize: 11, color: Color(0xFF78716C)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cerrar turno'),
          ),
        ],
      ),
    );
    final amountText = amountController.text;
    final notesText = notesController.text;
    amountController.dispose();
    notesController.dispose();
    if (confirmed != true || !mounted) return;
    final closingAmount = double.tryParse(amountText.replaceAll(',', '.'));
    setState(() => _closing = true);
    try {
      await repository.closeShift(
        closingAmount: closingAmount,
        notes: notesText,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caja cerrada. Nuevo turno iniciado.')),
      );
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();
    final scoped = _scopedOrders(repository);
    final total = scoped.fold<double>(0, (sum, order) => sum + order.total);
    final average = scoped.isEmpty ? 0.0 : total / scoped.length;
    final itemsSold = scoped.fold<int>(0, (sum, order) => sum + order.itemCount);
    final topProducts = repository.topProducts(limit: 5, orders: scoped);
    final maxQuantity = topProducts.isEmpty
        ? 0
        : topProducts
            .map((product) => product.quantity)
            .reduce((a, b) => a > b ? a : b);
    final payments = repository.salesByPaymentMethodFor(scoped).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Reporte de ventas'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _ShiftHeader(
            shift: repository.activeShift,
            pendingClosures: repository.pendingCashShiftClosures.length,
            closing: _closing,
            onClose: () => _closeShift(repository),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('Turno actual'),
                  selected: !_historical,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _historical = false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Text('Histórico'),
                  selected: _historical,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _historical = true),
                ),
              ),
            ],
          ),
          if (_historical) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final days in [7, 30, 90])
                  ChoiceChip(
                    label: Text('$days días'),
                    selected: _customStart == null && _rangeDays == days,
                    showCheckmark: false,
                    onSelected: (_) => _selectDays(days),
                  ),
                ChoiceChip(
                  label: const Text('Personalizado'),
                  selected: _customStart != null,
                  showCheckmark: false,
                  onSelected: (_) => _pickCustomRange(),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Ventas cobradas',
                  value: formatCop(total),
                  icon: Icons.payments_outlined,
                  accent: AppTheme.success,
                  subtitle: '${scoped.length} pedidos · Ver detalle',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SalesDetailScreen(orders: scoped),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'Ticket promedio',
                  value: formatCop(average),
                  icon: Icons.trending_up_rounded,
                  accent: const Color(0xFF2563EB),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Productos vendidos',
                  value: '$itemsSold',
                  icon: Icons.inventory_2_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'Por cobrar',
                  value: formatCop(repository.pendingPayments),
                  icon: Icons.account_balance_wallet_outlined,
                  accent: AppTheme.warning,
                ),
              ),
            ],
          ),
          SectionHeader(title: _rangeLabel()),
          _SalesChart(sales: _chart(repository), bucket: _bucket()),
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
          if (_historical && repository.closedShifts.isNotEmpty) ...[
            const SectionHeader(title: 'Turnos cerrados'),
            ...repository.closedShifts.map(
              (shift) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            CashShiftDetailScreen(shift: shift),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFEDEAE6)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.history_toggle_off_rounded,
                            color: AppTheme.brand,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  shift.label,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${shift.orderCount} pedidos · '
                                  '${formatDateTime(shift.openedAt)}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFF78716C),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            formatCop(shift.total),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
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
                    'Los reportes usan los pedidos pagados guardados en el '
                    'dispositivo y la fecha real del cobro. Los turnos se '
                    'sincronizan con la web cuando hay conexión.',
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
      ),
    );
  }
}

class _ShiftHeader extends StatelessWidget {
  const _ShiftHeader({
    required this.shift,
    required this.pendingClosures,
    required this.closing,
    required this.onClose,
  });

  final CashShift shift;
  final int pendingClosures;
  final bool closing;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();
    final orders = repository.currentShiftOrders;
    final total = orders.fold<double>(0, (sum, order) => sum + order.total);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.point_of_sale_outlined,
              size: 20,
              color: AppTheme.brandDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shift.label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${orders.length} pedidos · ${formatCop(total)}',
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF78716C)),
                ),
                if (pendingClosures > 0)
                  const Text(
                    '1 cierre pendiente de sincronizar',
                    style: TextStyle(fontSize: 10, color: AppTheme.warning),
                  ),
              ],
            ),
          ),
          if (repository.role?.canCloseShift ?? false)
            FilledButton.icon(
              onPressed: closing ? null : onClose,
              icon: const Icon(Icons.lock_outline_rounded, size: 16),
              label: Text(closing ? 'Cerrando...' : 'Cerrar caja'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SalesChart extends StatelessWidget {
  const _SalesChart({required this.sales, required this.bucket});

  final List<DailySales> sales;
  final SalesBucket bucket;

  double get _barWidth => switch (bucket) {
        SalesBucket.hour => 52,
        SalesBucket.day => 44,
        SalesBucket.week => 72,
        SalesBucket.month => 78,
      };

  String _label(DateTime day) => switch (bucket) {
        SalesBucket.hour => '${twoDigits(day.hour)}h',
        SalesBucket.day => const ['L', 'M', 'M', 'J', 'V', 'S', 'D'][day.weekday - 1],
        SalesBucket.week => 'sem ${formatShortDate(day)}',
        SalesBucket.month => '${day.month}/${day.year % 100}',
      };

  String _value(double total) {
    if (total <= 0) return '';
    if (total >= 1000) return '${(total / 1000).round()}k';
    return total.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final maxValue = sales.fold<double>(
      0,
      (max, entry) => entry.total > max ? entry.total : max,
    );
    final showDate = bucket == SalesBucket.hour || bucket == SalesBucket.day;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      child: SizedBox(
        height: 150,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: sales.map((entry) {
              final ratio = maxValue <= 0 ? 0.0 : entry.total / maxValue;
              return SizedBox(
                width: _barWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _value(entry.total),
                        style: const TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF78716C),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: 14 + ratio * 72,
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
                        _label(entry.day),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF78716C),
                        ),
                      ),
                      if (showDate)
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
      ),
    );
  }
}
