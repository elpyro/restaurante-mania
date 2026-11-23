import 'dart:io';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/repository.dart';
import '../../core/models/customer.dart';
import '../../core/models/order.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../orders/new_order_screen.dart';

enum _CrmSort { recent, name, spent, orders }

class CrmScreen extends StatefulWidget {
  const CrmScreen({super.key});

  @override
  State<CrmScreen> createState() => _CrmScreenState();
}

class _CrmScreenState extends State<CrmScreen> {
  final _search = TextEditingController();
  String _query = '';
  _CrmSort _sort = _CrmSort.recent;
  bool _exporting = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<CustomerRecord> _filtered(List<CustomerRecord> customers) {
    final q = _query.trim().toLowerCase();
    final list = customers.where((c) {
      if (!c.hasPhone) return false;
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          c.phone.toLowerCase().contains(q) ||
          c.address.toLowerCase().contains(q) ||
          c.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();
    list.sort((a, b) {
      switch (_sort) {
        case _CrmSort.recent:
          return b.lastOrderAt.compareTo(a.lastOrderAt);
        case _CrmSort.name:
          final an = a.name.trim().isEmpty ? 'zzzz' : a.name.toLowerCase();
          final bn = b.name.trim().isEmpty ? 'zzzz' : b.name.toLowerCase();
          return an.compareTo(bn);
        case _CrmSort.spent:
          return b.totalSpent.compareTo(a.totalSpent);
        case _CrmSort.orders:
          return b.orderCount.compareTo(a.orderCount);
      }
    });
    return list;
  }

  Future<void> _exportExcel(List<CustomerRecord> customers) async {
    if (_exporting || customers.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Clientes'];
      excel.delete('Sheet1');
      sheet.appendRow([
        TextCellValue('Nombre'),
        TextCellValue('Teléfono'),
        TextCellValue('Dirección'),
        TextCellValue('Etiquetas'),
        TextCellValue('Pedidos'),
        TextCellValue('Total gastado'),
        TextCellValue('Último pedido'),
        TextCellValue('Último tipo'),
        TextCellValue('Notas'),
      ]);
      for (final c in customers) {
        sheet.appendRow([
          TextCellValue(c.name),
          TextCellValue(c.phone),
          TextCellValue(c.address),
          TextCellValue(c.tags.join(', ')),
          IntCellValue(c.orderCount),
          DoubleCellValue(c.totalSpent),
          TextCellValue(formatDateTime(c.lastOrderAt)),
          TextCellValue(c.lastType.label),
          TextCellValue(c.notes),
        ]);
      }
      final bytes = excel.save();
      if (bytes == null) throw Exception('No se pudo generar el archivo');
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/clientes_restaurante_mania_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      );
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Clientes Restaurante Manía',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo exportar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<RestaurantRepository>();
    final customers = _filtered(repo.crmCustomers);
    final total = repo.crmCustomers.where((c) => c.hasPhone).length;
    final repeat = repo.crmCustomers.where((c) => c.hasPhone && c.orderCount > 1).length;
    final withTags = repo.crmCustomers.where((c) => c.hasPhone && c.tags.isNotEmpty).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.25,
            children: [
              StatCard(
                label: 'Clientes',
                value: '$total',
                icon: Icons.people_outline_rounded,
                accent: const Color(0xFF2563EB),
              ),
              StatCard(
                label: 'Recurrentes',
                value: '$repeat',
                icon: Icons.repeat_rounded,
                accent: AppTheme.brand,
              ),
              StatCard(
                label: 'Con etiquetas',
                value: '$withTags',
                icon: Icons.label_outline_rounded,
                accent: AppTheme.success,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  decoration: InputDecoration(
                    hintText: 'Buscar nombre, teléfono, etiqueta...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFEDEAE6)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFEDEAE6)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<_CrmSort>(
                tooltip: 'Ordenar',
                initialValue: _sort,
                onSelected: (v) => setState(() => _sort = v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: _CrmSort.recent, child: Text('Más recientes')),
                  PopupMenuItem(value: _CrmSort.name, child: Text('Nombre')),
                  PopupMenuItem(value: _CrmSort.spent, child: Text('Mayor gasto')),
                  PopupMenuItem(value: _CrmSort.orders, child: Text('Más pedidos')),
                ],
                child: Container(
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFEDEAE6)),
                  ),
                  child: const Icon(Icons.sort_rounded, color: AppTheme.ink),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _exporting ? null : () => _exportExcel(customers),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFEDEAE6)),
                  ),
                  child: _exporting
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded, color: AppTheme.ink),
                ),
              ),
            ],
          ),
          const SectionHeader(title: 'Clientes con teléfono'),
          if (customers.isEmpty)
            const EmptyState(
              icon: Icons.person_search_outlined,
              title: 'Sin clientes',
              message:
                  'Solo aparecen clientes con número telefónico registrado en pedidos.',
            )
          else
            ...customers.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CustomerCard(
                    customer: c,
                    onTap: () => _openDetail(context, c),
                  ),
                )),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context, CustomerRecord customer) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CustomerDetailSheet(customerId: customer.id),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer, required this.onTap});

  final CustomerRecord customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = customer.name.trim().isNotEmpty ? customer.name : 'Cliente';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEDEAE6)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.brand.withValues(alpha: 0.12),
                child: Text(
                  _initials(name),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.brandDark,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      customer.phone,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF78716C)),
                    ),
                    if (customer.tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: customer.tags.take(3).map((t) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.brand.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  t,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.brandDark,
                                  ),
                                ),
                              )).toList(),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatCop(customer.totalSpent),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.brandDark,
                    ),
                  ),
                  Text(
                    '${customer.orderCount} pedido${customer.orderCount == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF78716C)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerDetailSheet extends StatefulWidget {
  const _CustomerDetailSheet({required this.customerId});
  final String customerId;

  @override
  State<_CustomerDetailSheet> createState() => _CustomerDetailSheetState();
}

class _CustomerDetailSheetState extends State<_CustomerDetailSheet> {
  final _tagController = TextEditingController();
  final _notesController = TextEditingController();
  bool _notesDirty = false;

  @override
  void dispose() {
    _tagController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _openWhatsApp(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final waPhone = digits.length == 10 ? '57$digits' : digits;
    final uri = Uri.parse('https://wa.me/$waPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _createOrder(BuildContext context, CustomerRecord customer) async {
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NewOrderScreen(
          initialCustomerName: customer.name,
          initialCustomerPhone: customer.phone,
          initialDeliveryAddress: customer.address,
          initialType: customer.lastType == OrderType.table
              ? OrderType.pickup
              : customer.lastType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<RestaurantRepository>();
    final customer = repo.crmCustomers.where((c) => c.id == widget.customerId).firstOrNull;
    if (customer == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Cliente no disponible'),
      );
    }
    if (!_notesDirty) _notesController.text = customer.notes;

    final normalized = customer.normalizedPhone;
    final orders = repo.orders.where((o) {
      return o.customerPhone.replaceAll(RegExp(r'\D'), '') == normalized;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final name = customer.name.trim().isNotEmpty ? customer.name : 'Cliente';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE7E5E4),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppTheme.brand.withValues(alpha: 0.12),
                      child: Text(_initials(name),
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.brandDark)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                          Text(customer.phone,
                              style: const TextStyle(fontSize: 14, color: Color(0xFF78716C))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _openWhatsApp(customer.phone),
                      icon: const Icon(Icons.chat_outlined, size: 18),
                      label: const Text('WhatsApp'),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _createOrder(context, customer),
                      icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                      label: const Text('Crear pedido'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(icon: Icons.receipt_long_outlined, label: '${customer.orderCount} pedidos'),
                    _InfoChip(icon: Icons.payments_outlined, label: formatCop(customer.totalSpent)),
                    _InfoChip(icon: Icons.calendar_today_outlined, label: 'Último: ${formatDateTime(customer.lastOrderAt)}'),
                  ],
                ),
                _InfoRow(icon: Icons.location_on_outlined, label: 'Dirección', value: customer.address.isNotEmpty ? customer.address : 'No registrada'),
                _InfoRow(icon: Icons.history_rounded, label: 'Cliente desde', value: formatDateTime(customer.createdAt)),
                const SizedBox(height: 16),
                const SectionHeader(title: 'Etiquetas'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ...customer.tags.map((t) => InputChip(
                          label: Text(t),
                          onDeleted: () {
                            final next = [...customer.tags]..remove(t);
                            repo.updateCustomer(customer.copyWith(tags: next));
                          },
                        )),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tagController,
                        decoration: InputDecoration(
                          hintText: 'Nueva etiqueta',
                          filled: true,
                          fillColor: const Color(0xFFFAFAF9),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFEDEAE6)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFEDEAE6)),
                          ),
                        ),
                        onSubmitted: (_) => _addTag(repo, customer),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: () => _addTag(repo, customer),
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const SectionHeader(title: 'Notas'),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  onChanged: (_) => _notesDirty = true,
                  decoration: InputDecoration(
                    hintText: 'Notas internas del cliente...',
                    filled: true,
                    fillColor: const Color(0xFFFAFAF9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFEDEAE6)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFEDEAE6)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: () async {
                      await repo.updateCustomer(
                        customer.copyWith(notes: _notesController.text.trim()),
                      );
                      _notesDirty = false;
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Notas guardadas')),
                        );
                      }
                    },
                    child: const Text('Guardar notas'),
                  ),
                ),
                const SizedBox(height: 16),
                const SectionHeader(title: 'Historial de pedidos'),
                if (orders.isEmpty)
                  const Text('Sin pedidos registrados.', style: TextStyle(color: Color(0xFF78716C)))
                else
                  ...orders.map((o) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAFAF9),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFEDEAE6)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(o.code,
                                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.ink)),
                                  Text('${formatDateTime(o.createdAt)} · ${o.status.label}',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF78716C))),
                                ],
                              ),
                            ),
                            Text(formatCop(o.total),
                                style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.brandDark)),
                          ],
                        ),
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addTag(RestaurantRepository repo, CustomerRecord customer) {
    final tag = _tagController.text.trim();
    if (tag.isEmpty) return;
    if (customer.tags.any((t) => t.toLowerCase() == tag.toLowerCase())) {
      _tagController.clear();
      return;
    }
    repo.updateCustomer(customer.copyWith(tags: [...customer.tags, tag]));
    _tagController.clear();
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFFF5F5F4), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF57534E)),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF57534E))),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF78716C)),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF78716C))),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.ink)),
          ),
        ],
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}
