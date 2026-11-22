import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Detecta el estado de red y permite simular offline en la demo.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final ValueNotifier<bool> online = ValueNotifier<bool>(true);
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _manualOverride = false;

  Future<void> init() async {
    try {
      final results = await _connectivity.checkConnectivity();
      online.value = _hasConnection(results);
      _subscription = _connectivity.onConnectivityChanged.listen((results) {
        if (!_manualOverride) online.value = _hasConnection(results);
      });
    } catch (_) {
      // En entornos sin plugin (tests, desktop) asumimos conexión.
      online.value = true;
    }
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.isNotEmpty &&
        results.any((result) => result != ConnectivityResult.none);
  }

  void setManual(bool value) {
    _manualOverride = true;
    online.value = value;
  }

  void resetManual() {
    _manualOverride = false;
  }

  void dispose() {
    _subscription?.cancel();
    online.dispose();
  }
}
