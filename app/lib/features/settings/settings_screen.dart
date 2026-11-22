import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
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
  late final TextEditingController _whatsapp;
  late final TextEditingController _address;
  late bool _isOpen;
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = context.read<RestaurantRepository>().settings;
    _name = TextEditingController(text: settings.name);
    _hours = TextEditingController(text: settings.hours);
    _whatsapp = TextEditingController(text: settings.whatsapp);
    _address = TextEditingController(text: settings.address);
    _isOpen = settings.isOpen;
  }

  @override
  void dispose() {
    _name.dispose();
    _hours.dispose();
    _whatsapp.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save(RestaurantRepository repository) async {
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Escribe el nombre del restaurante.');
      return;
    }
    setState(() => _error = null);
    await repository.updateSettings(
      repository.settings.copyWith(
        name: _name.text.trim(),
        hours: _hours.text.trim(),
        whatsapp: _whatsapp.text.trim(),
        address: _address.text.trim(),
        isOpen: _isOpen,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuración guardada.')),
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
          TextField(
            controller: _whatsapp,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'WhatsApp'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Dirección'),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEDEAE6)),
            ),
            child: SwitchListTile.adaptive(
              value: _isOpen,
              onChanged: (value) => setState(() => _isOpen = value),
              title: const Text(
                'Restaurante abierto',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Controla si la web pública acepta pedidos.',
                style: TextStyle(fontSize: 11),
              ),
            ),
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
          const _SectionLabel('Conectividad y sincronización'),
          Container(
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
                    repository.pendingSyncCount > 0
                        ? '${repository.pendingSyncCount} pedido(s) pendientes'
                        : 'Todo sincronizado',
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
          ),
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
                  'Versión 1.0.0 · Flutter + persistencia offline.\n'
                  'Arquitectura feature-first con repositorio local y cola de sincronización. '
                  'Listo para conectar Cloud Firestore en producción.',
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
