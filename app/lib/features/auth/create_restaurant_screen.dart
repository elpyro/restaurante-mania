import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/restaurant_settings.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';

/// Alta autocontenida de una nueva instancia de restaurante.
///
/// Pide las credenciales de acceso y la configuración mínima para que la
/// instancia nazca lista para operar (nombre, horario, zona horaria, mesas y
/// teléfono con indicativo). Si el correo ya existe se usan sus credenciales;
/// si no, se crea la cuenta Firebase.
class CreateRestaurantScreen extends StatefulWidget {
  const CreateRestaurantScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<CreateRestaurantScreen> createState() => _CreateRestaurantScreenState();
}

class _CreateRestaurantScreenState extends State<CreateRestaurantScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _openTime = TextEditingController(
    text: RestaurantSettings.defaultOpenTime,
  );
  final _closeTime = TextEditingController(
    text: RestaurantSettings.defaultCloseTime,
  );
  final _tableCount = TextEditingController(text: '0');
  final _phone = TextEditingController();

  String _timeZone = RestaurantSettings.defaultTimeZone;
  String _countryCode = '+57';
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  static const _countryCodes = ['+57', '+52', '+54', '+51', '+56', '+34', '+1'];

  @override
  void initState() {
    super.initState();
    _email.text = widget.initialEmail;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _openTime.dispose();
    _closeTime.dispose();
    _tableCount.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() {
      _error = null;
      _loading = true;
    });
    final repository = context.read<RestaurantRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final tenantId = await repository.createRestaurant(
        email: _email.text.trim(),
        password: _password.text,
        restaurantName: _name.text.trim(),
        timeZone: _timeZone,
        openTime: _openTime.text.trim(),
        closeTime: _closeTime.text.trim(),
        tableCount: int.tryParse(_tableCount.text.trim()) ?? 0,
        countryCode: _countryCode,
        phone: _phone.text.trim(),
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Restaurante «${_name.text.trim()}» creado (${_email.text.trim()}). '
            'ID: $tenantId',
          ),
        ),
      );
      Navigator.of(context).pop();
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'No se pudo crear el restaurante: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Escribe un correo válido.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if ((value ?? '').length < 6) {
      return 'La contraseña debe tener al menos 6 caracteres.';
    }
    return null;
  }

  String? _validateTime(String? value, String label) {
    if (!RestaurantSettings.isValidTimeOfDay(value ?? '')) {
      return '$label en formato HH:mm (00:00 a 23:59).';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F4F1),
      appBar: AppBar(
        title: const Text('Crear restaurante'),
        backgroundColor: AppTheme.brandDark,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.brand, AppTheme.brandDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Configura tu instancia',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFEDEAE6)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Acceso',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.ink,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Si el correo ya tiene cuenta, usa su contraseña actual. '
                            'Si es nuevo, se creará automáticamente.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF78716C),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            enabled: !_loading,
                            validator: _validateEmail,
                            decoration: const InputDecoration(
                              labelText: 'Correo',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            enabled: !_loading,
                            validator: _validatePassword,
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Restaurante',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.ink,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _name,
                            enabled: !_loading,
                            validator: (value) => (value ?? '').trim().isEmpty
                                ? 'Escribe el nombre del restaurante.'
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Nombre del restaurante',
                              prefixIcon: Icon(Icons.restaurant_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            // ignore: deprecated_member_use
                            value: _timeZone,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Zona horaria',
                              prefixIcon: Icon(Icons.public_rounded),
                            ),
                            items: [
                              for (final zone in RestaurantSettings.suggestionsTimeZone)
                                DropdownMenuItem<String>(
                                  value: zone,
                                  child: Text(zone),
                                ),
                            ],
                            onChanged: _loading
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() => _timeZone = value);
                                    }
                                  },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _openTime,
                                  keyboardType: TextInputType.datetime,
                                  enabled: !_loading,
                                  validator: (value) =>
                                      _validateTime(value, 'Apertura'),
                                  decoration: const InputDecoration(
                                    labelText: 'Apertura',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _closeTime,
                                  keyboardType: TextInputType.datetime,
                                  enabled: !_loading,
                                  validator: (value) =>
                                      _validateTime(value, 'Cierre'),
                                  decoration: const InputDecoration(
                                    labelText: 'Cierre',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _tableCount,
                            keyboardType: TextInputType.number,
                            enabled: !_loading,
                            validator: (value) {
                              final parsed = int.tryParse(value?.trim() ?? '');
                              if (parsed == null ||
                                  parsed < 0 ||
                                  parsed > RestaurantSettings.maxTableCount) {
                                return 'Entre 0 y ${RestaurantSettings.maxTableCount}.';
                              }
                              return null;
                            },
                            decoration: const InputDecoration(
                              labelText: 'Cantidad de mesas',
                              prefixIcon: Icon(Icons.table_bar_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 104,
                                child: DropdownButtonFormField<String>(
                                  // ignore: deprecated_member_use
                                  value: _countryCode,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'País',
                                  ),
                                  items: [
                                    for (final code in _countryCodes)
                                      DropdownMenuItem<String>(
                                        value: code,
                                        child: Text(code),
                                      ),
                                  ],
                                  onChanged: _loading
                                      ? null
                                      : (value) {
                                          if (value != null) {
                                            setState(() => _countryCode = value);
                                          }
                                        },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _phone,
                                  keyboardType: TextInputType.phone,
                                  enabled: !_loading,
                                  validator: (value) {
                                    final digits =
                                        (value ?? '').replaceAll(RegExp(r'\D'), '');
                                    if (digits.length < 7) {
                                      return 'Escribe un teléfono válido.';
                                    }
                                    return null;
                                  },
                                  decoration: const InputDecoration(
                                    labelText: 'Teléfono',
                                    prefixIcon: Icon(Icons.phone_outlined),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: AppTheme.danger,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: _loading ? null : () => unawaited(_submit()),
                            icon: _loading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.add_business_rounded, size: 18),
                            label: Text(
                              _loading ? 'Creando…' : 'Crear restaurante',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
