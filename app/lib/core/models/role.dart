enum UserRole {
  admin('Administrador', 'Acceso total al sistema'),
  cashier('Cajero', 'Cobros, caja y reportes'),
  waiter('Mesero', 'Mesas y comandas'),
  cook('Cocinero', 'Pedidos y cocina');

  const UserRole(this.label, this.description);

  final String label;
  final String description;

  static UserRole fromName(String? value) {
    return UserRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => UserRole.admin,
    );
  }

  bool get canManageMenu => this == UserRole.admin;
  bool get canSeeReports => this == UserRole.admin || this == UserRole.cashier;
  bool get canManageTables =>
      this == UserRole.admin ||
      this == UserRole.waiter ||
      this == UserRole.cashier;
  bool get canMarkPaid => this == UserRole.admin || this == UserRole.cashier;
  bool get canCancelOrders => this == UserRole.admin;
  bool get canAccessSettings => this == UserRole.admin;
  bool get canCreateOrders => this != UserRole.cook;
  bool get canViewRecipe => this == UserRole.admin || this == UserRole.cook;
}
