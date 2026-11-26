import 'role.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  final String id;
  final String name;
  final String email;
  final UserRole role;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  AppUser copyWith({
    String? name,
    String? email,
    UserRole? role,
  }) =>
      AppUser(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        role: role ?? this.role,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role.name,
      };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        role: UserRole.fromName(json['role'] as String?),
      );
}
