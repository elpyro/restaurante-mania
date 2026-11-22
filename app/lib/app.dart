import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/data/repository.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/shell/app_shell.dart';

class RestauranteApp extends StatelessWidget {
  const RestauranteApp({super.key, required this.repository});

  final RestaurantRepository repository;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RestaurantRepository>.value(
      value: repository,
      child: MaterialApp(
        title: 'Restaurante Manía POS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RestaurantRepository>(
      builder: (context, repository, _) {
        if (!repository.isAuthenticated) {
          return const LoginScreen();
        }
        return const AppShell();
      },
    );
  }
}
