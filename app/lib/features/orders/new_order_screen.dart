import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/menu_item.dart';
import '../../core/models/order.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';

class NewOrderScreen extends StatefulWidget {
  const NewOrderScreen({super.key, this.initialTableNumber});

  final int? initialTableNumber;

  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen> {
  final Map<String, CartLine> _cart = {};
  final _searchController = TextEditingController();
  String _categoryId = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int get _count =>
      _cart.values.fold(0, (sum, line) => sum + line.quantity);

  double get _total =>
      _cart.values.fold(0, (sum, line) => sum + line.total);

  void _add(MenuItem item) {
    final current = _cart[item.id];
    _cart[item.id] = current == null
        ? CartLine(
            menuItemId: item.id,
            name: item.name,
            price: item.price,
            quantity: 1,
            emoji: item.emoji,
          )
        : current.copyWith(quantity: current.quantity + 1);
    setState(() {});
  }

  void _remove(MenuItem item) {
    final current = _cart[item.id];
    if (current == null) return;
    if (current.quantity <= 1) {
      _cart.remove(item.id);
    } else {
      _cart[item.id] = current.copyWith(quantity: current.quantity - 1);
    }
    setState(() {});
  }

  Future<void> _openCheckout() async {
    if (_cart.isEmpty) return;
    final order = await showModalBottomSheet<Order>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: _CheckoutSheet(
          lines: _cart.values.toList(),
          initialTableNumber: widget.initialTableNumber,
        ),
      ),
    );
    if (order == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          order.synced
              ? 'Pedido ${order.code} creado correctamente.'
              : 'Pedido ${order.code} guardado offline. Se sincronizará al volver la conexión.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();
    final query = _searchController.text.trim().toLowerCase();
    final items = repository.availableMenuItems.where((item) {
      final categoryOk = _categoryId == 'all' || item.categoryId == _categoryId;
      final searchOk = query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.description.toLowerCase().contains(query);
      return categoryOk && searchOk;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo pedido'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Buscar plato o bebida',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
              ),
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _CategoryChip(
                  label: 'Todo',
                  selected: _categoryId == 'all',
                  onTap: () => setState(() => _categoryId = 'all'),
                ),
                ...repository.categories.map(
                  (category) => _CategoryChip(
                    label: '${category.emoji} ${category.name}',
                    selected: _categoryId == category.id,
                    onTap: () => setState(() => _categoryId = category.id),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No hay platos disponibles',
                      message: 'Cambia la categoría o la búsqueda.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final line = _cart[item.id];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFEDEAE6)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7ED),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  item.emoji,
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.ink,
                                      ),
                                    ),
                                    Text(
                                      formatCop(item.price),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.brandDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (line == null)
                                IconButton.filledTonal(
                                  onPressed: () => _add(item),
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  visualDensity: VisualDensity.compact,
                                )
                              else
                                Row(
                                  children: [
                                    _MiniButton(
                                      icon: Icons.remove_rounded,
                                      onTap: () => _remove(item),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: Text(
                                        '${line.quantity}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    _MiniButton(
                                      icon: Icons.add_rounded,
                                      onTap: () => _add(item),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    },
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
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_count producto(s)',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF78716C),
                    ),
                  ),
                  Text(
                    formatCop(_total),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.brandDark,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton(
                onPressed: _cart.isEmpty ? null : _openCheckout,
                child: const Text('Continuar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet({
    required this.lines,
    this.initialTableNumber,
  });

  final List<CartLine> lines;
  final int? initialTableNumber;

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();
  late OrderType _type;
  late int _tableNumber;
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _type = widget.initialTableNumber != null
        ? OrderType.table
        : OrderType.pickup;
    _tableNumber = widget.initialTableNumber ?? 1;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _total =>
      widget.lines.fold(0, (sum, line) => sum + line.total);

  Future<void> _confirm() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (_type != OrderType.table) {
      if (name.length < 2) {
        setState(() => _error = 'Escribe el nombre del cliente.');
        return;
      }
      if (digits.length < 7) {
        setState(() => _error = 'Escribe un teléfono válido.');
        return;
      }
    } else {
      if (name.isNotEmpty && name.length < 2) {
        setState(() => _error = 'Escribe un nombre válido.');
        return;
      }
      if (phone.isNotEmpty && digits.length < 7) {
        setState(() => _error = 'Escribe un teléfono válido.');
        return;
      }
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      final repository = context.read<RestaurantRepository>();
      final order = await repository.createOrder(
        lines: widget.lines,
        customerName: name,
        customerPhone: phone,
        type: _type,
        tableNumber: _type == OrderType.table ? _tableNumber : null,
        paymentMethod: _paymentMethod,
        notes: _notesController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(order);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'No se pudo crear el pedido. Intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 10, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Confirmar pedido',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
              children: [
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del cliente (opcional en mesa)',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono (opcional en mesa)',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Modalidad',
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
                  children: OrderType.values.map((type) {
                    return ChoiceChip(
                      label: Text(type.label),
                      selected: _type == type,
                      onSelected: (_) => setState(() => _type = type),
                      showCheckmark: false,
                    );
                  }).toList(),
                ),
                if (_type == OrderType.table) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Mesa',
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
                    children: List.generate(10, (index) {
                      final number = index + 1;
                      return ChoiceChip(
                        label: Text('$number'),
                        selected: _tableNumber == number,
                        onSelected: (_) =>
                            setState(() => _tableNumber = number),
                        showCheckmark: false,
                      );
                    }),
                  ),
                ],
                const SizedBox(height: 14),
                const Text(
                  'Método de pago',
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
                  children: PaymentMethod.values.map((method) {
                    return ChoiceChip(
                      label: Text(method.label),
                      selected: _paymentMethod == method,
                      onSelected: (_) =>
                          setState(() => _paymentMethod = method),
                      showCheckmark: false,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'Notas para la cocina',
                    hintText: 'Sin cebolla, salsa aparte...',
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF8F5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFEDEAE6)),
                  ),
                  child: Column(
                    children: [
                      ...widget.lines.map(
                        (line) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${line.quantity} × ${line.name}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF57534E),
                                  ),
                                ),
                              ),
                              Text(
                                formatCop(line.total),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 16),
                      Row(
                        children: [
                          const Text(
                            'Total',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            formatCop(_total),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.brandDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.danger,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _confirm,
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    _submitting ? 'Creando pedido...' : 'Crear pedido',
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

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        labelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: selected ? Colors.white : const Color(0xFF57534E),
        ),
        selectedColor: AppTheme.ink,
        backgroundColor: Colors.white,
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF5F5F4),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 16, color: AppTheme.ink),
        ),
      ),
    );
  }
}
