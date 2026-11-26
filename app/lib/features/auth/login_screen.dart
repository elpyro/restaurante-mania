import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/data/seed_data.dart';
import '../../core/data/tenant.dart';
import '../../core/models/role.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController(text: 'admin@restaurante.com');
  final _passwordController = TextEditingController(
    text: AuthService.firebaseApiKey.isEmpty ? SeedData.demoPassword : '',
  );
  bool _obscure = true;
  bool _loading = false;
  bool _switchingTenant = false;
  String? _error;

  bool get _usesFirebase => AuthService.firebaseApiKey.isNotEmpty;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit(RestaurantRepository repository) async {
    if (_loading) return;
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      if (_usesFirebase) {
        await repository.loginWithFirebase(
          _emailController.text,
          _passwordController.text,
        );
        return;
      }
      final ok = repository.login(
        _emailController.text,
        _passwordController.text,
      );
      if (!ok) {
        setState(() {
          _error =
              'Credenciales inválidas. Usa una cuenta demo y la clave 1234.';
        });
      }
    } on AuthException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = 'No se pudo iniciar sesión: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _switchTenant(
    RestaurantRepository repository,
    String tenantId,
  ) async {
    if (_switchingTenant || tenantId == repository.tenantId) return;
    setState(() {
      _switchingTenant = true;
      _error = null;
    });
    try {
      await repository.switchTenant(tenantId);
    } catch (error) {
      setState(() => _error = 'No se pudo cambiar de instancia: $error');
    } finally {
      if (mounted) {
        setState(() => _switchingTenant = false);
      }
    }
  }

  Widget _tenantSelector(RestaurantRepository repository) {
    final current = tenants[repository.tenantId] ?? tenants[defaultTenantId]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(current.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AuthService.firebaseApiKey.isNotEmpty
                      ? 'INSTANCIA CON FIREBASE'
                      : 'INSTANCIA DE LA DEMO',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: Color(0xFFA8A29E),
                  ),
                ),
              ),
              if (_switchingTenant)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            current.description,
            style: const TextStyle(fontSize: 11, color: Color(0xFF78716C)),
          ),
          const SizedBox(height: 2),
          DropdownButton<String>(
            value: repository.tenantId,
            isExpanded: true,
            isDense: true,
            underline: const SizedBox.shrink(),
            items: [
              for (final tenant in tenants.values)
                DropdownMenuItem<String>(
                  value: tenant.id,
                  child: Text(
                    '${tenant.emoji} ${tenant.label}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _switchingTenant
                ? null
                : (value) {
                    if (value != null) {
                      unawaited(_switchTenant(repository, value));
                    }
                  },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.brand, AppTheme.brandDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text('🍽️', style: TextStyle(fontSize: 26)),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Restaurante Manía',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'POS administrativo · pedidos, mesas y cocina en tiempo real',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _tenantSelector(repository),
                  const SizedBox(height: 14),
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
                          'Inicia sesión',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.ink,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Correo',
                            prefixIcon: Icon(Icons.mail_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscure,
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
                          onSubmitted: (_) => unawaited(_submit(repository)),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: AppTheme.danger,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loading
                              ? null
                              : () => unawaited(_submit(repository)),
                          child: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Ingresar'),
                        ),
                        if (_usesFirebase) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: _loading
                                  ? null
                                  : () => unawaited(
                                      _showPasswordResetDialog(repository),
                                    ),
                              icon: const Icon(Icons.help_outline_rounded, size: 15),
                              label: const Text('Recuperar contraseña'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          _usesFirebase
                              ? 'Acceso con tu cuenta registrada.'
                              : 'Demo: cualquier cuenta de la lista · clave 1234',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF78716C),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_usesFirebase)
                    const Padding(
                      padding: EdgeInsets.only(top: 18),
                      child: Text(
                        'Los cambios se publican en la web con esta sesión.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFFA8A29E),
                        ),
                      ),
                    )
                  else ...[
                    const SizedBox(height: 18),
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'ACCESO RÁPIDO DEMO',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: Color(0xFF78716C),
                            ),
                          ),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.55,
                      children: UserRole.values
                          .map((role) => _RoleCard(
                                role: role,
                                onTap: () => repository.loginAs(role),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Los datos se guardan en este dispositivo.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 10.5, color: Color(0xFFA8A29E)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showPasswordResetDialog(RestaurantRepository repository) async {
    final controller = TextEditingController(
      text: _emailController.text.trim(),
    );
    var sending = false;
    String? error;
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Recuperar contraseña'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Firebase enviará un correo para establecer la contraseña de la cuenta.',
                style: TextStyle(fontSize: 12, color: Color(0xFF78716C)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enabled: !sending,
                decoration: const InputDecoration(
                  labelText: 'Correo',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(
                  error!,
                  style: const TextStyle(
                    color: AppTheme.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: sending
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      setDialogState(() {
                        sending = true;
                        error = null;
                      });
                      try {
                        await repository.sendPasswordReset(controller.text);
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              'Enviamos un correo a ${controller.text.trim()} para establecer tu contraseña.',
                            ),
                          ),
                        );
                      } on AuthException catch (authError) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          sending = false;
                          error = authError.message;
                        });
                      } catch (resetError) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          sending = false;
                          error = 'No se pudo enviar el correo: $resetError';
                        });
                      }
                    },
              child: sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Enviar enlace'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.role, required this.onTap});

  final UserRole role;
  final VoidCallback onTap;

  IconData get _icon => switch (role) {
        UserRole.admin => Icons.admin_panel_settings_outlined,
        UserRole.cashier => Icons.point_of_sale_outlined,
        UserRole.waiter => Icons.room_service_outlined,
        UserRole.cook => Icons.soup_kitchen_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEDEAE6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(_icon, size: 22, color: AppTheme.brandDark),
              Text(
                role.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              Text(
                role.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9.5,
                  color: Color(0xFF78716C),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
