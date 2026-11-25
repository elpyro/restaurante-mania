import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/restaurant_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _name;
  late final TextEditingController _hours;
  late final TextEditingController _countryCode;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _currency;
  late final TextEditingController _serverUrl;
  late final TextEditingController _aiDescription;
  late final TextEditingController _aiKeywords;
  late final TextEditingController _aiServiceArea;
  late final TextEditingController _aiHighlights;
  late final Map<String, TextEditingController> _paymentLabels;
  late bool _isOpen;
  late bool _showOrderTypeOptions;
  late Map<String, bool> _deliveryOptions;
  late List<String> _paymentMethods;
  String? _error;
  String? _serverMessage;

  @override
  void initState() {
    super.initState();
    final repository = context.read<RestaurantRepository>();
    final settings = repository.settings;
    _name = TextEditingController(text: settings.name);
    _hours = TextEditingController(text: settings.hours);
    _countryCode = TextEditingController(text: settings.countryCode);
    _phone = TextEditingController(text: settings.phone);
    _address = TextEditingController(text: settings.address);
    _city = TextEditingController(text: settings.city);
    _currency = TextEditingController(text: settings.currency);
    _serverUrl = TextEditingController(text: repository.serverUrl);
    _aiDescription = TextEditingController(text: settings.aiDescription);
    _aiKeywords = TextEditingController(text: settings.aiKeywords);
    _aiServiceArea = TextEditingController(text: settings.aiServiceArea);
    _aiHighlights = TextEditingController(text: settings.aiHighlights);
    _paymentLabels = {
      for (final method in RestaurantSettings.availablePaymentMethods)
        method: TextEditingController(
          text: settings.paymentLabel(method),
        ),
    };
    _isOpen = settings.isOpen;
    _showOrderTypeOptions = settings.showOrderTypeOptions;
    _deliveryOptions = Map<String, bool>.from(settings.deliveryOptions);
    _paymentMethods = List<String>.from(settings.paymentMethods);
  }

  @override
  void dispose() {
    _name.dispose();
    _hours.dispose();
    _countryCode.dispose();
    _phone.dispose();
    _address.dispose();
    _city.dispose();
    _currency.dispose();
    _serverUrl.dispose();
    _aiDescription.dispose();
    _aiKeywords.dispose();
    _aiServiceArea.dispose();
    _aiHighlights.dispose();
    for (final controller in _paymentLabels.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save(RestaurantRepository repository) async {
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Escribe el nombre del restaurante.');
      return;
    }
    if (!RegExp(r'^\+\d{1,4}$').hasMatch(_countryCode.text.trim())) {
      setState(() => _error = 'El indicativo debe empezar con +, por ejemplo +57.');
      return;
    }
    if (_phone.text.replaceAll(RegExp(r'\D'), '').length < 7) {
      setState(() => _error = 'Escribe un teléfono válido (mínimo 7 dígitos).');
      return;
    }
    if (_city.text.trim().length < 2) {
      setState(() => _error = 'Escribe la ciudad.');
      return;
    }
    if (!RegExp(r'^[A-Za-z]{3}$').hasMatch(_currency.text.trim())) {
      setState(() => _error = 'La moneda debe tener 3 letras, por ejemplo COP.');
      return;
    }
    if (_paymentMethods.isEmpty) {
      setState(() => _error = 'Activa al menos un método de pago.');
      return;
    }
    if (!_deliveryOptions.values.any((enabled) => enabled)) {
      setState(() => _error = 'Activa al menos una opción de entrega.');
      return;
    }
    setState(() => _error = null);

    final labels = <String, String>{};
    for (final method in _paymentMethods) {
      final label = _paymentLabels[method]?.text.trim() ?? '';
      if (label.isNotEmpty) labels[method] = label;
    }
    final current = repository.settings;
    final next = current.copyWith(
      name: _name.text.trim(),
      hours: _hours.text.trim(),
      countryCode: _countryCode.text.trim(),
      phone: _phone.text.trim(),
      whatsapp: RestaurantSettings.compactNumber(
        _countryCode.text.trim(),
        _phone.text.trim(),
      ),
      address: _address.text.trim(),
      city: _city.text.trim(),
      currency: _currency.text.trim().toUpperCase(),
      isOpen: _isOpen,
      showOrderTypeOptions: _showOrderTypeOptions,
      deliveryOptions: Map<String, bool>.from(_deliveryOptions),
      paymentMethods: List<String>.from(_paymentMethods),
      paymentMethodLabels: labels,
      aiDescription: cleanAiText(_aiDescription.text),
      aiKeywords: cleanAiText(_aiKeywords.text),
      aiServiceArea: cleanAiText(_aiServiceArea.text),
      aiHighlights: cleanAiText(_aiHighlights.text),
    );
    await repository.updateSettings(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configuración guardada y sincronizada con la web.'),
      ),
    );
  }

  Future<void> _reset(RestaurantRepository repository) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reiniciar demo'),
        content: const Text(
          'Se borrarán los pedidos, cambios de menú y la sesión actual. '
          'La aplicación volverá a los datos de ejemplo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reiniciar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.resetDemoData();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const _SectionLabel('Datos del restaurante'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _hours,
            decoration: const InputDecoration(
              labelText: 'Horario',
              hintText: '11:00 - 22:00',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _countryCode,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'País',
                    hintText: '+57',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono',
                    helperText: 'También se usa para WhatsApp',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _city,
            decoration: const InputDecoration(labelText: 'Ciudad'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Dirección'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _currency,
            decoration: const InputDecoration(
              labelText: 'Moneda',
              hintText: 'COP',
              helperText: 'Código ISO de 3 letras',
            ),
          ),
          const SizedBox(height: 10),
          _switchCard(
            value: _isOpen,
            title: 'Restaurante abierto',
            subtitle: 'Controla si la web pública acepta pedidos.',
            onChanged: (value) => setState(() => _isOpen = value),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.danger,
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _save(repository),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Guardar cambios'),
          ),
          const _SectionLabel('Entrega en la web'),
          _switchCard(
            value: _showOrderTypeOptions,
            title: 'Mostrar «¿Cómo quieres recibirlo?»',
            subtitle: 'Si lo desactivas, la web usará un solo tipo de pedido.',
            onChanged: (value) => setState(() => _showOrderTypeOptions = value),
          ),
          const SizedBox(height: 8),
          _switchCard(
            value: _deliveryOptions['pickup'] ?? true,
            title: 'Para recoger',
            subtitle: 'El cliente recoge en el restaurante.',
            onChanged: (value) =>
                setState(() => _deliveryOptions['pickup'] = value),
          ),
          const SizedBox(height: 8),
          _switchCard(
            value: _deliveryOptions['delivery'] ?? true,
            title: 'Domicilio',
            subtitle: 'Entrega en la dirección del cliente.',
            onChanged: (value) =>
                setState(() => _deliveryOptions['delivery'] = value),
          ),
          const SizedBox(height: 8),
          _switchCard(
            value: _deliveryOptions['table'] ?? true,
            title: 'En mesa',
            subtitle: 'Pedido desde la mesa del restaurante.',
            onChanged: (value) =>
                setState(() => _deliveryOptions['table'] = value),
          ),
          const _SectionLabel('Métodos de pago'),
          ...RestaurantSettings.availablePaymentMethods.map((method) {
            final enabled = _paymentMethods.contains(method);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Checkbox(
                      value: enabled,
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          if (!_paymentMethods.contains(method)) {
                            _paymentMethods.add(method);
                          }
                        } else {
                          _paymentMethods.remove(method);
                        }
                      }),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _paymentLabels[method],
                      enabled: enabled,
                      decoration: InputDecoration(
                        labelText: RestaurantSettings.defaultPaymentLabels[method],
                        hintText: 'Nombre visible en la web',
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          FilledButton.icon(
            onPressed: () => _save(repository),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Guardar cambios'),
          ),
          const _SectionLabel('Datos para búsqueda de IA'),
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Estos textos se publican en los metadatos de la web y en /llms.txt '
              'para que ChatGPT, Gemini y Perplexity encuentren el restaurante.',
              style: TextStyle(fontSize: 11, color: Color(0xFF78716C)),
            ),
          ),
          TextField(
            controller: _aiDescription,
            maxLength: RestaurantSettings.aiDescriptionMaxLength,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Descripción para IA',
              hintText: 'Qué comida sirve y qué experiencia ofrece',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _aiKeywords,
            maxLength: RestaurantSettings.aiKeywordsMaxLength,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Palabras clave',
              hintText: 'bandeja paisa, ajiaco, restaurante en Medellín',
              helperText: 'Separa las palabras con comas.',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _aiServiceArea,
            maxLength: RestaurantSettings.aiServiceAreaMaxLength,
            decoration: const InputDecoration(
              labelText: 'Zona de servicio',
              hintText: 'Medellín y área metropolitana',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _aiHighlights,
            maxLength: RestaurantSettings.aiHighlightsMaxLength,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Aspectos destacados',
              hintText: 'Pedidos rápidos, cocina colombiana, domicilio',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _save(repository),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Guardar datos de IA'),
          ),
          const _SectionLabel('Servidor web (pedidos en línea)'),
          TextField(
            controller: _serverUrl,
            decoration: const InputDecoration(
              labelText: 'URL del servidor web',
              hintText: 'http://192.168.101.7:3000',
              helperText:
                  'Pedidos creados en la web se importan automáticamente.',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    await repository.updateServerUrl(_serverUrl.text);
                    setState(() => _serverMessage = 'Servidor guardado.');
                  },
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Guardar URL'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await repository.updateServerUrl(_serverUrl.text);
                    final ok = await repository.testServerConnection();
                    setState(() {
                      _serverMessage = ok
                          ? 'Conexión correcta con la web.'
                          : 'No se pudo conectar. Revisa la URL o la red.';
                    });
                  },
                  icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                  label: const Text('Probar'),
                ),
              ),
            ],
          ),
          if (_serverMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              _serverMessage!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF57534E),
              ),
            ),
          ],
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () async {
              final count = await repository.pullServerOrders();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    count == 0
                        ? 'No hay pedidos nuevos de la web.'
                        : 'Se importaron $count pedido(s) de la web.',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Importar pedidos web ahora'),
          ),
          _syncCard(repository),
          const _SectionLabel('Zona de riesgo'),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.danger,
              side: const BorderSide(color: Color(0xFFFECDD3)),
            ),
            onPressed: () => _reset(repository),
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('Reiniciar datos demo'),
          ),
          const _SectionLabel('Acerca de'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEDEAE6)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Restaurante Manía POS',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Versión 1.0.0 · Restaurante Manía POS',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
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

  Widget _switchCard({
    required bool value,
    required String title,
    required String subtitle,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      child: SwitchListTile.adaptive(
        value: value,
        onChanged: onChanged,
        title: Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  String _pendingLabel(RestaurantRepository repository) {
    final pendingOrders = repository.pendingSyncCount;
    final pendingConfig = repository.hasPendingRestaurantConfig ? 1 : 0;
    final total = pendingOrders + pendingConfig;
    if (total == 0) return 'Todo sincronizado';
    final parts = <String>[];
    if (pendingOrders > 0) parts.add('$pendingOrders pedido(s)');
    if (pendingConfig > 0) parts.add('configuración de la web');
    return '${parts.join(' y ')} pendientes';
  }

  Widget _syncCard(RestaurantRepository repository) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            value: repository.isOnline,
            onChanged: repository.setOnlineForDemo,
            title: const Text(
              'Simular conexión',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              repository.isOnline
                  ? 'En línea: los pedidos nuevos se marcan como sincronizados.'
                  : 'Sin conexión: los pedidos se guardan en cola local.',
              style: const TextStyle(fontSize: 11),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.cloud_upload_outlined, size: 20),
            title: const Text(
              'Sincronizar ahora',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _pendingLabel(repository),
              style: const TextStyle(fontSize: 11),
            ),
            trailing: repository.isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right_rounded),
            onTap: repository.isOnline && !repository.isSyncing
                ? repository.syncPendingOrders
                : null,
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.schedule_rounded, size: 20),
            title: const Text(
              'Última sincronización',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              repository.lastSync == null
                  ? 'Nunca'
                  : formatDateTime(repository.lastSync!),
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
          color: Color(0xFFA8A29E),
        ),
      ),
    );
  }
}
