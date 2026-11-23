import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/repository.dart';
import '../../core/models/menu_item.dart';
import '../../core/models/order.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';

class NewOrderScreen extends StatefulWidget {
  const NewOrderScreen({
    super.key,
    this.initialTableNumber,
    this.orderToEdit,
    this.initialCustomerName,
    this.initialCustomerPhone,
    this.initialDeliveryAddress,
    this.initialType,
  });

  final int? initialTableNumber;
  final Order? orderToEdit;
  final String? initialCustomerName;
  final String? initialCustomerPhone;
  final String? initialDeliveryAddress;
  final OrderType? initialType;

  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen> {
  final Map<String, CartLine> _cart = {};
  final _searchController = TextEditingController();
  String _categoryId = 'all';

  @override
  void initState() {
    super.initState();
    final order = widget.orderToEdit;
    if (order != null) {
      for (final item in order.items) {
        _cart[item.menuItemId] = CartLine(
          menuItemId: item.menuItemId,
          name: item.name,
          price: item.price,
          quantity: item.quantity,
          emoji: item.emoji,
          imageUrl: item.imageUrl,
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int get _count =>
      _cart.values.fold(0, (sum, line) => sum + line.quantity);

  double get _total =>
      _cart.values.fold(0, (sum, line) => sum + line.total);

  bool _add(MenuItem item) {
    final repository = context.read<RestaurantRepository>();
    final canAdd = repository.availableAdditionalServings(
      item.id,
      _cart.values.toList(),
    );
    if (canAdd < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No hay ingredientes suficientes para preparar más "${item.name}".',
          ),
        ),
      );
      return false;
    }
    final current = _cart[item.id];
    _cart[item.id] = current == null
        ? CartLine(
            menuItemId: item.id,
            name: item.name,
            price: item.price,
            quantity: 1,
            emoji: item.emoji,
            imageUrl: item.imageUrl,
          )
        : current.copyWith(quantity: current.quantity + 1);
    setState(() {});
    return true;
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

  void _showDetail(MenuItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _MenuItemDetailSheet(
        item: item,
        quantity: _cart[item.id]?.quantity ?? 0,
        onAdd: () {
          final added = _add(item);
          if (added) Navigator.of(context).pop();
        },
      ),
    );
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
          orderToEdit: widget.orderToEdit,
          initialCustomerName: widget.initialCustomerName,
          initialCustomerPhone: widget.initialCustomerPhone,
          initialDeliveryAddress: widget.initialDeliveryAddress,
          initialType: widget.initialType,
        ),
      ),
    );
    if (order == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          widget.orderToEdit != null
              ? 'Pedido ${order.code} actualizado.'
              : order.synced
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
        title: Text(widget.orderToEdit == null ? 'Nuevo pedido' : 'Editar pedido'),
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
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final line = _cart[item.id];
                      return _MenuItemGridCard(
                        item: item,
                        quantity: line?.quantity ?? 0,
                        onAdd: () => _add(item),
                        onRemove: () => _remove(item),
                        onDetail: () => _showDetail(item),
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
                child: Text(widget.orderToEdit == null ? 'Continuar' : 'Revisar cambios'),
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
    this.orderToEdit,
    this.initialCustomerName,
    this.initialCustomerPhone,
    this.initialDeliveryAddress,
    this.initialType,
  });

  final List<CartLine> lines;
  final int? initialTableNumber;
  final Order? orderToEdit;
  final String? initialCustomerName;
  final String? initialCustomerPhone;
  final String? initialDeliveryAddress;
  final OrderType? initialType;

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();
  late OrderType _type;
  late int _tableNumber;
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final order = widget.orderToEdit;
    if (order != null) {
      _nameController.text = order.customerName;
      _phoneController.text = order.customerPhone;
      _addressController.text = order.deliveryAddress;
      _notesController.text = order.notes;
      _type = order.type;
      _tableNumber = order.tableNumber ?? widget.initialTableNumber ?? 1;
    } else {
      _nameController.text = widget.initialCustomerName ?? '';
      _phoneController.text = widget.initialCustomerPhone ?? '';
      _addressController.text = widget.initialDeliveryAddress ?? '';
      _type = widget.initialType ??
          (widget.initialTableNumber != null
              ? OrderType.table
              : OrderType.pickup);
      _tableNumber = widget.initialTableNumber ?? 1;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _total =>
      widget.lines.fold(0, (sum, line) => sum + line.total);

  Future<void> _confirm() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final address = _addressController.text.trim();
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
    if (_type == OrderType.delivery && address.length < 5) {
      setState(() => _error = 'Escribe la dirección de entrega.');
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      final repository = context.read<RestaurantRepository>();
      final editing = widget.orderToEdit;
      if (editing != null) {
        final order = await repository.updateOrder(
          orderId: editing.id,
          lines: widget.lines,
          customerName: name,
          customerPhone: phone,
          deliveryAddress: _type == OrderType.delivery ? address : '',
          type: _type,
          tableNumber: _type == OrderType.table ? _tableNumber : null,
          notes: _notesController.text,
        );
        if (!mounted) return;
        Navigator.of(context).pop(order);
        return;
      }
      // Si hay un pedido en preparación para la misma mesa, ofrecer fusionar
      if (_type == OrderType.table) {
        final preparing = repository.preparingOrdersForTable(_tableNumber)
            .where((o) => o.id != editing?.id)
            .toList();
        if (preparing.isNotEmpty) {
          final existing = preparing.first;
          final merge = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Pedido en preparación'),
              content: Text(
                'La mesa $_tableNumber ya tiene un pedido en preparación '
                '(${existing.code}). ¿Deseas agregar estos items al pedido existente?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Crear nuevo'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Agregar al existente'),
                ),
              ],
            ),
          );
          if (merge == true) {
            await repository.addItemsToOrder(existing.id, widget.lines);
            if (!mounted) return;
            Navigator.of(context).pop(existing);
            return;
          }
        }
      }
      final order = await repository.createOrder(
        lines: widget.lines,
        customerName: name,
        customerPhone: phone,
        deliveryAddress: _type == OrderType.delivery ? address : '',
        type: _type,
        tableNumber: _type == OrderType.table ? _tableNumber : null,
        notes: _notesController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(order);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = widget.orderToEdit != null
            ? 'No se pudo actualizar el pedido. Intenta de nuevo.'
            : 'No se pudo crear el pedido. Intenta de nuevo.';
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
                Expanded(
                  child: Text(
                    widget.orderToEdit == null ? 'Confirmar pedido' : 'Guardar cambios',
                    style: const TextStyle(
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
                if (_type == OrderType.delivery) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _addressController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Dirección de entrega *',
                      hintText: 'Calle, número, barrio, referencia...',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                ],
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
                    _submitting
                        ? (widget.orderToEdit == null ? 'Creando pedido...' : 'Guardando cambios...')
                        : (widget.orderToEdit == null ? 'Crear pedido' : 'Guardar cambios'),
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

class _MenuItemGridCard extends StatelessWidget {
  const _MenuItemGridCard({
    required this.item,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
    required this.onDetail,
  });

  final MenuItem item;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: quantity > 0 ? AppTheme.brand : const Color(0xFFEDEAE6),
          width: quantity > 0 ? 1.5 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x081C1917),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onDetail,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(17)),
                    child: _DetailImage(item: item, emojiFontSize: 44),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(999),
                      child: InkWell(
                        onTap: onDetail,
                        borderRadius: BorderRadius.circular(999),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.info_outline_rounded,
                              size: 16, color: AppTheme.ink),
                        ),
                      ),
                    ),
                  ),
                  if (quantity > 0)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.brand,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$quantity',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatCop(item.price),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.brandDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (quantity == 0)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: onAdd,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Agregar'),
                      ),
                    )
                  else
                    Row(
                      children: [
                        _MiniButton(icon: Icons.remove_rounded, onTap: onRemove),
                        Expanded(
                          child: Text(
                            '$quantity',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _MiniButton(icon: Icons.add_rounded, onTap: onAdd),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItemDetailSheet extends StatelessWidget {
  const _MenuItemDetailSheet({
    required this.item,
    required this.quantity,
    required this.onAdd,
  });

  final MenuItem item;
  final int quantity;
  final VoidCallback onAdd;

  Future<void> _openVideo(BuildContext context) async {
    final url = Uri.tryParse(item.videoUrl.trim());
    if (url == null) return;
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el video.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = item.videoUrl.trim().isNotEmpty;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: _DetailImage(item: item, emojiFontSize: 72),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink,
                          height: 1.15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      formatCop(item.price),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.brandDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF57534E),
                    height: 1.5,
                  ),
                ),
                if (item.ingredients.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Ingredientes',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: item.ingredients
                        .map(
                          (i) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F4),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              i,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF57534E),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
                if (item.allergens.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Alérgenos: ${item.allergens.join(', ')}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (hasVideo) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => _openVideo(context),
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    label: const Text('Ver video del plato'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: Text(
                    quantity > 0 ? 'Agregar otro ($quantity en carrito)' : 'Agregar al pedido',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
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

class _DetailImage extends StatelessWidget {
  const _DetailImage({required this.item, required this.emojiFontSize});

  final MenuItem item;
  final double emojiFontSize;

  @override
  Widget build(BuildContext context) {
    final url = item.imageUrl.trim();
    Widget fallback() => Container(
          color: const Color(0xFFFFF7ED),
          alignment: Alignment.center,
          child: Text(item.emoji, style: TextStyle(fontSize: emojiFontSize)),
        );
    if (url.isEmpty) return fallback();
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: const Color(0xFFFFF7ED),
            alignment: Alignment.center,
            child: const CircularProgressIndicator(strokeWidth: 2),
          );
        },
      );
    }
    return Image.file(
      File(url),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback(),
    );
  }
}
