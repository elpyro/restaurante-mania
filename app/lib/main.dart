import 'package:flutter/material.dart';

import 'app.dart';
import 'core/data/repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await RestaurantRepository.load();
  runApp(RestauranteApp(repository: repository));
}
