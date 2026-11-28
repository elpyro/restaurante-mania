import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/data/repository.dart';
import 'core/services/crash_reporter.dart';
import 'core/services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CrashReporter.initialize();
  final repository = await RestaurantRepository.load();
  await NotificationService.instance.initialize(
    preferences: repository.notificationPreferences,
    onTap: repository.handleNotificationTap,
    onTokenRefresh: (_) => unawaited(repository.registerDeviceId()),
  );
  // Sesión restaurada: mantener el dispositivo registrado en all_user.
  await repository.registerDeviceId();
  runApp(RestauranteApp(repository: repository));
}
