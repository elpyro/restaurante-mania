import 'package:flutter/material.dart';

import 'app.dart';
import 'core/data/repository.dart';
import 'core/services/crash_reporter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CrashReporter.initialize();
  final repository = await RestaurantRepository.load();
  runApp(RestauranteApp(repository: repository));
}
