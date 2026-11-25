import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/models/app_user.dart';
import '../../core/models/role.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  UserRole _role = UserRole.cashier;
  AppUser? _editing;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _resetForm() {
    _editing = null;
    _nameController.clear();
    _emailController.clear();
    _role = UserRole.cashier;
    _error = null;
  }

  void _startEditing(AppUser user) {
    setState(() {
      _editing = user;
      _nameController.text = user.name;
      _emailController.text = user.email;
      _role = user.role;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final repository = context.read<RestaurantRepository>();
    try {
      if (_editing == null) {
        await repository.addUser(
          name: _nameController.text,
          email: _emailController.text,
          role: _role,
        );
      } else {
        await repository.updateUser(
          _editing!.id,
          name: _nameController.text,
          email: _emailController.text,
          role: _role,
        );
      }
      _resetForm();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuario guardado correctamente.')),
        );
      }
    } catch (error) {
      setState(() => _error = error.toString().replaceFirst('Invalid argument(s): ', ''));
    }
  }

  Future<void> _remove(AppUser user, RestaurantRepository repository) async {
    try {
      await repository.deleteUser(user.id);
      if (_editing?.id == user.id) _resetForm();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Usuario ${user.name} eliminado.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Invalid argument(s): ', ''),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();
    final users = repository.users;
    final admins = users.where((user) => user.role == UserRole.admin).length;
    final current = repository.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFEDEAE6)),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _editing == null ? 'Nuevo usuario' : 'Editar usuario',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Las cuentas se guardan en este dispositivo. Clave demo compartida.',
                    style: TextStyle(fontSize: 10.5, color: Color(0xFF78716C)),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value == null || value.trim().length < 2)
                        ? 'Escribe el nombre del usuario.'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final email = value?.trim().toLowerCase() ?? '';
                      if (!email.contains('@') || !email.contains('.')) {
                        return 'Escribe un correo válido.';
                      }
                      return repository.isEmailTaken(
                        email,
                        excludeId: _editing?.id,
                      )
                          ? 'Ya existe un usuario con ese correo.'
                          : null;
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<UserRole>(
                    initialValue: _role,
                    decoration: const InputDecoration(
                      labelText: 'Rol',
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: UserRole.values
                        .map(
                          (role) => DropdownMenuItem<UserRole>(
                            value: role,
                            child: Text(role.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _role = value ?? _role),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.danger,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _submit,
                          icon: Icon(
                            _editing == null
                                ? Icons.person_add_alt_1_rounded
                                : Icons.save_outlined,
                          ),
                          label: Text(
                            _editing == null ? 'Crear usuario' : 'Guardar cambios',
                          ),
                        ),
                      ),
                      if (_editing != null) ...[
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => setState(_resetForm),
                          child: const Text('Cancelar'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SectionHeader(
            title: 'Cuentas registradas',
            action: Text('$admins administrador(es)'),
          ),
          if (users.isEmpty)
            const EmptyState(
              icon: Icons.people_outline_rounded,
              title: 'Sin usuarios',
              message: 'Crea la primera cuenta para acceder al sistema.',
            )
          else
            ...users.map(
              (user) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEDEAE6)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppTheme.brand.withValues(alpha: 0.12),
                        child: Text(
                          user.initials,
                          style: const TextStyle(
                            fontSize: 12,
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
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    user.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.ink,
                                    ),
                                  ),
                                ),
                                if (current?.id == user.id) ...[
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Tú',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.brand,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF78716C),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.brand.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                user.role.label,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.brandDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Editar',
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _startEditing(user),
                      ),
                      IconButton(
                        tooltip: 'Eliminar',
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: AppTheme.danger,
                        ),
                        onPressed: () => _remove(user, repository),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
