import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/ingredient.dart';
import '../../core/models/order.dart';
import '../../core/models/restaurant_settings.dart';
import '../../core/models/role.dart';
import '../../core/services/receipt_print_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/status_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import 'new_order_screen.dart';
import 'payment_sheet.dart';

Future<void> _printOrderReceipt(
  BuildContext context,
  Order order,
  RestaurantSettings settings,
) async {
  try {
    await ReceiptPrintService(order: order, settings: settings).printReceipt();
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No se pudo imprimir el recibo: $error')),
    );
  }
}

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
              IconButton(
                tooltip: 'Imprimir recibo',
                icon: const Icon(Icons.print_outlined),
                onPressed: () =>
                    _printOrderReceipt(context, order, repository.settings),
              ),
              if ((role.canCreateOrders && repository.canEditOrder(order)) || order.status.isActive)
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'edit') {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => NewOrderScreen(orderToEdit: order),
                        ),
                      );
                      return;
                    }
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
                  itemBuilder: (context) => [
                    if (repository.canEditOrder(order))
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Editar pedido'),
                          ],
                        ),
                      ),
                    if (order.status.isActive)
                      const PopupMenuItem<String>(
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
              _HeaderCard(order: order, sequenceLabel: repository.tableOrderSequence(order)),
              if (order.tableNumber != null)
                Builder(builder: (context) {
                  final group = repository.tableOrders(order.tableNumber!, activeOnly: true);
                  if (group.length <= 1) return const SizedBox.shrink();
                  final idx = group.indexWhere((o) => o.id == order.id);
                  final safeIdx = idx < 0 ? 0 : idx;
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFEDEAE6)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton.filledTonal(
                                onPressed: safeIdx > 0
                                    ? () => Navigator.of(context).pushReplacement(
                                          MaterialPageRoute<void>(
                                            builder: (_) => OrderDetailScreen(orderId: group[safeIdx - 1].id),
                                          ),
                                        )
                                    : null,
                                icon: const Icon(Icons.chevron_left_rounded),
                                visualDensity: VisualDensity.compact,
                              ),
                              Expanded(
                                child: Text(
                                  'Pedido ${safeIdx + 1}/${group.length} de la mesa',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.ink),
                                ),
                              ),
                              IconButton.filledTonal(
                                onPressed: safeIdx < group.length - 1
                                    ? () => Navigator.of(context).pushReplacement(
                                          MaterialPageRoute<void>(
                                            builder: (_) => OrderDetailScreen(orderId: group[safeIdx + 1].id),
                                          ),
                                        )
                                    : null,
                                icon: const Icon(Icons.chevron_right_rounded),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 34,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: group.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 6),
                              itemBuilder: (context, i) {
                                final o = group[i];
                                final selected = o.id == order.id;
                                return ChoiceChip(
                                  label: Text('${i + 1}/${group.length} · ${o.status.label}'),
                                  selected: selected,
                                  showCheckmark: false,
                                  onSelected: (_) {
                                    if (selected) return;
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute<void>(
                                        builder: (_) => OrderDetailScreen(orderId: o.id),
                                      ),
                                    );
                                  },
                                  labelStyle: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: selected ? Colors.white : const Color(0xFF57534E),
                                  ),
                                  selectedColor: AppTheme.ink,
                                  backgroundColor: Colors.white,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
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
                            MenuItemImage(
                              imageUrl: item.imageUrl,
                              emoji: item.emoji,
                              size: 36,
                              borderRadius: 10,
                            ),
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
              if (role.canViewRecipe &&
                  order.items.any(
                    (item) =>
                        (repository.menuItemById(item.menuItemId)?.hasRecipe ??
                            false),
                  )) ...[
                const SectionHeader(title: 'Receta (cocina)'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFEDEAE6)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final orderItem in order.items) ...[
                      if ((repository.menuItemById(orderItem.menuItemId)
                              ?.hasRecipe ??
                          false)) ...[
                        Text(
                          '${orderItem.quantity} × ${orderItem.name}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                          ... (repository
                                  .menuItemById(orderItem.menuItemId)
                                  ?.recipe ??
                              const <RecipeIngredient>[])
                              .map((line) {
                            final ingredient = repository
                                .ingredientById(line.ingredientId);
                            final name =
                                ingredient?.name ?? line.ingredientId;
                            final unit = ingredient?.unit.symbol ?? '';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                '• $name: '
                                '${line.quantity * orderItem.quantity} $unit',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF57534E),
                                ),
                              ),
                            );
                          }),
                          if ((repository
                                      .menuItemById(orderItem.menuItemId)
                                      ?.recipeSteps ??
                                  '')
                              .trim()
                              .isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                repository
                                    .menuItemById(orderItem.menuItemId)!
                                    .recipeSteps,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF57534E),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                      ],
                    ],
                  ],
                ),
              ),
              ],
              const SectionHeader(title: 'Sincronización'),
              const SectionHeader(title: 'Auditoría'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEDEAE6)),
                ),
                child: order.auditLog.isEmpty
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _AuditRow(
                            label: 'Creado por',
                            value: order.createdByName ?? 'Sin registro',
                          ),
                          const SizedBox(height: 4),
                          _AuditRow(
                            label: 'Última acción',
                            value: order.updatedByName ?? 'Sin registro',
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          for (var i = order.auditLog.length - 1; i >= 0; i--)
                            _AuditEntryTile(
                              entry: order.auditLog[i],
                              isLast: i == 0,
                            ),
                        ],
                      ),
              ),
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
                        final table = order.tableNumber;
                        final payable = table != null
                            ? repository.payableTableOrders(table)
                            : <Order>[order];
                        final total = payable.fold<double>(0, (s, o) => s + o.total);
                        if (payable.length > 1 && table != null) {
                          final confirmed = await showModalBottomSheet<bool>(
                            context: context,
                            useSafeArea: true,
                            backgroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                            ),
                            builder: (ctx) => Padding(
                              padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Cobrar Mesa $table', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                                  const SizedBox(height: 4),
                                  Text('${payable.length}/${payable.length} pedidos a cancelar · pago automático de todos', style: const TextStyle(fontSize: 12, color: Color(0xFF78716C))),
                                  const SizedBox(height: 12),
                                  ...payable.asMap().entries.map((e) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(children: [
                                      Text('${e.key + 1}/${payable.length} ${e.value.code}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                      const Spacer(),
                                      Text(formatCop(e.value.total), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                    ]),
                                  )),
                                  const Divider(),
                                  Row(children: [
                                    const Text('Total', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                                    const Spacer(),
                                    Text(formatCop(total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.brandDark)),
                                  ]),
                                  const SizedBox(height: 12),
                                  SizedBox(width: double.infinity, child: FilledButton(
                                    onPressed: () => Navigator.of(ctx).pop(true),
                                    style: FilledButton.styleFrom(backgroundColor: AppTheme.brand, foregroundColor: Colors.white),
                                    child: Text('Continuar al pago · ${formatCop(total)}'),
                                  )),
                                ],
                              ),
                            ),
                          );
                          if (confirmed != true || !context.mounted) return;
                          final payments = await showPaymentSheet(context, total: total, title: 'Cobrar Mesa $table', subtitle: '${payable.length} pedidos · ${formatCop(total)}');
                          if (payments == null) return;
                          await repository.markGroupPaid(table, payments: payments);
                        } else {
                          final payments = await showPaymentSheet(context, total: total, title: 'Cobrar ${order.code}', subtitle: order.customerName);
                          if (payments == null) return;
                          await repository.markOrderPaid(order.id, payments: payments);
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Cobrado: ${formatCop(total)}')),
                          );
                        }
                      },
                      icon: const Icon(Icons.payments_outlined, size: 17),
                      label: Text(
                        order.tableNumber != null && repository.payableTableOrders(order.tableNumber!).length > 1
                            ? 'Cobrar mesa (${repository.payableTableOrders(order.tableNumber!).length}) · ${formatCop(repository.tablePendingTotal(order.tableNumber!))}'
                            : 'Cobrar ${formatCop(order.total)}',
                      ),
                    ),
                  if (order.type == OrderType.delivery &&
                      order.status.isActive &&
                      target != OrderStatus.sent)
                    OutlinedButton.icon(
                      onPressed: () async {
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
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(false),
                                  child: const Text('No, esperar'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(true),
                                  child: const Text('Sí, enviar'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true || !context.mounted) return;
                        }
                        await repository.updateOrderStatus(order.id, OrderStatus.sent);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Pedido marcado como enviado.'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.local_shipping_outlined, size: 17),
                      label: const Text('Marcar enviado'),
                    ),
                  if (order.status.isActive)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.danger,
                        side: BorderSide(
                          color: AppTheme.danger.withValues(alpha: 0.55),
                        ),
                      ),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Cancelar pedido'),
                            content: Text(
                              '¿Cancelar el pedido ${order.code}? '
                              'Los ingredientes descontados volverán al inventario.',
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
                                child: const Text('Sí, cancelar'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true || !context.mounted) return;
                        await repository.cancelOrder(order.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Pedido cancelado. Ingredientes repuestos.',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.cancel_outlined, size: 17),
                      label: const Text('Cancelar pedido'),
                    ),
                  if (target != null)
                    FilledButton.icon(
                      onPressed: () async {
                        if (target == OrderStatus.sent) {
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
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(false),
                                    child: const Text('No, esperar'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(true),
                                    child: const Text('Sí, enviar'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true || !context.mounted) return;
                          }
                        } else {
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
                            if (confirmed != true || !context.mounted) return;
                          }
                        }
                        await repository.updateOrderStatus(order.id, target);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Pedido actualizado a ${target.label}.',
                            ),
                          ),
                        );
                        if (role == UserRole.cook && target == OrderStatus.ready) {
                          Navigator.of(context).pop();
                        }
                      },
                      icon: Icon(
                        target == OrderStatus.sent
                            ? Icons.local_shipping_outlined
                            : Icons.arrow_forward_rounded,
                        size: 17,
                      ),
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
    if (order.type == OrderType.delivery) {
      // Domicilios: todos los roles pueden marcar Enviado desde cualquier estado activo.
      // El flujo principal sigue el siguiente paso; Enviado siempre disponible por separado.
      if (role == UserRole.cook) {
        if (order.status == OrderStatus.pending ||
            order.status == OrderStatus.confirmed) {
          return OrderStatus.preparing;
        }
        if (order.status == OrderStatus.preparing) return OrderStatus.ready;
        if (order.status == OrderStatus.ready) return OrderStatus.sent;
        return OrderStatus.sent;
      }
      if (role == UserRole.waiter || role == UserRole.cashier) {
        if (order.status == OrderStatus.pending) return OrderStatus.confirmed;
        if (order.status == OrderStatus.confirmed) return OrderStatus.sent;
        if (order.status == OrderStatus.ready) return OrderStatus.sent;
        if (order.status == OrderStatus.preparing) return OrderStatus.sent;
        return OrderStatus.sent;
      }
      return order.status.nextFor(order.type);
    }
    if (role == UserRole.cook) {
      if (order.status == OrderStatus.pending ||
          order.status == OrderStatus.confirmed) {
        return OrderStatus.preparing;
      }
      if (order.status == OrderStatus.preparing) return OrderStatus.ready;
      return null;
    }
    if (role == UserRole.waiter || role == UserRole.cashier) {
      if (order.status == OrderStatus.pending) return OrderStatus.confirmed;
      if (order.status == OrderStatus.confirmed) return OrderStatus.delivered;
      if (order.status == OrderStatus.ready) return OrderStatus.delivered;
      return null;
    }
    return order.status.nextFor(order.type);
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.order, this.sequenceLabel});

  final Order order;
  final String? sequenceLabel;

  @override
  Widget build(BuildContext context) {
    final color = orderStatusColor(order.status);
    final paymentLabel = context
        .read<RestaurantRepository>()
        .settings
        .paymentLabel(order.paymentMethod.name);
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
              if (sequenceLabel != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFFFCD34D))),
                  child: Text('Pedido $sequenceLabel', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF92400E))),
                ),
              ],
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
          if (order.deliveryAddress.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 14, color: Color(0xFF78716C)),
                const SizedBox(width: 4),
                Expanded(
                  child: SelectableText(
                    order.deliveryAddress,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF57534E),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
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
                label: paymentLabel,
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
    final timeline = order.type == OrderType.delivery
        ? const [
            OrderStatus.pending,
            OrderStatus.confirmed,
            OrderStatus.preparing,
            OrderStatus.ready,
            OrderStatus.sent,
          ]
        : const [
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

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF78716C),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppTheme.ink,
            ),
          ),
        ),
      ],
    );
  }
}

class _AuditEntryTile extends StatelessWidget {
  const _AuditEntryTile({required this.entry, required this.isLast});

  final OrderAuditEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(
                  color: AppTheme.brand,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Container(width: 2, height: 28, color: const Color(0xFFE7E5E4)),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.action,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                if (entry.detail.trim().isNotEmpty)
                  Text(
                    entry.detail,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF57534E),
                      height: 1.3,
                    ),
                  ),
                Text(
                  '${entry.actorName ?? 'Sistema'} · ${formatDateTime(entry.timestamp)}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF78716C),
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
