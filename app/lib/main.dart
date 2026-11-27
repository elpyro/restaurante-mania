import 'package:flutter/material.dart';

import 'app.dart';
import 'core/data/repository.dart';
import 'core/services/crash_reporter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CrashReporter.initialize();
  final repository = await RestaurantRepository.load();
  // Sesión restaurada: mantener el dispositivo registrado en all_user.
  await repository.registerDeviceId();
  runApp(RestauranteApp(repository: repository));
}
