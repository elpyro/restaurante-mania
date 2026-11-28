import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:notification_sound/notification_sound.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tipos de aviso que produce el POS. El mismo `value` viaja en el payload de
/// FCM y en las notificaciones generadas localmente (polling sin conexión).
enum AppNotificationType {
  newOrder('new_order', 'Nuevo pedido', 'toCollect'),
  orderReady('order_ready', 'Pedido listo', 'ready'),
  lowStock('low_stock', 'Stock bajo', 'all'),
  outOfStock('out_of_stock', 'Sin stock', 'all'),
  shiftClosed('shift_closed', 'Cierre de caja', 'all');

  const AppNotificationType(this.value, this.label, this.orderFilter);

  final String value;
  final String label;
  final String orderFilter;

  static AppNotificationType? fromValue(String? value) {
    for (final type in AppNotificationType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// Tonos empaquetados en la APK. Se reproducen desde la app porque MIUI/HyperOS
/// puede restaurar el sonido elegido por el usuario en el canal de Android.
enum NotificationTone {
  classic('Clásico', 'classic'),
  chime('Campana', 'chime'),
  double('Doble', 'double'),
  soft('Suave', 'soft');

  const NotificationTone(this.label, this.value);

  final String label;
  final String value;

  static NotificationTone fromValue(String? value) {
    for (final tone in NotificationTone.values) {
      if (tone.value == value) return tone;
    }
    return NotificationTone.classic;
  }
}

/// Importancia del canal de Android por tipo de aviso. Al cambiarla se usa un
/// canal nuevo (Android no permite cambiar la importancia de uno existente).
enum NotificationImportance {
  high('Alta', 'high', Importance.high, Priority.high),
  normal('Normal', 'default', Importance.defaultImportance,
      Priority.defaultPriority),
  low('Baja', 'low', Importance.low, Priority.low);

  const NotificationImportance(
    this.label,
    this.value,
    this.androidImportance,
    this.androidPriority,
  );

  final String label;
  final String value;
  final Importance androidImportance;
  final Priority androidPriority;

  static NotificationImportance fromValue(String? value) {
    for (final importance in NotificationImportance.values) {
      if (importance.value == value) return importance;
    }
    return NotificationImportance.high;
  }
}

/// Preferencias globales del dispositivo: silenciar todo o solo algún aviso,
/// con tono e importancia independientes por categoría.
class NotificationPreferences {
  const NotificationPreferences({
    this.silentAll = false,
    Map<AppNotificationType, bool>? enabled,
    Map<AppNotificationType, NotificationTone>? tones,
    Map<AppNotificationType, NotificationImportance>? importances,
  })  : enabled = enabled ?? const {
          AppNotificationType.newOrder: true,
          AppNotificationType.orderReady: true,
          AppNotificationType.lowStock: true,
          AppNotificationType.outOfStock: true,
          AppNotificationType.shiftClosed: true,
        },
        tones = tones ?? const {
          AppNotificationType.newOrder: NotificationTone.classic,
          AppNotificationType.orderReady: NotificationTone.chime,
          AppNotificationType.lowStock: NotificationTone.double,
          AppNotificationType.outOfStock: NotificationTone.double,
          AppNotificationType.shiftClosed: NotificationTone.soft,
        },
        importances = importances ?? const {
          AppNotificationType.newOrder: NotificationImportance.high,
          AppNotificationType.orderReady: NotificationImportance.high,
          AppNotificationType.lowStock: NotificationImportance.normal,
          AppNotificationType.outOfStock: NotificationImportance.high,
          AppNotificationType.shiftClosed: NotificationImportance.low,
        };

  static const storageKey = 'rm_notification_preferences_v1';

  final bool silentAll;
  final Map<AppNotificationType, bool> enabled;
  final Map<AppNotificationType, NotificationTone> tones;
  final Map<AppNotificationType, NotificationImportance> importances;

  bool isEnabled(AppNotificationType type) =>
      !silentAll && (enabled[type] ?? true);

  NotificationTone toneFor(AppNotificationType type) =>
      tones[type] ?? NotificationTone.classic;

  NotificationImportance importanceFor(AppNotificationType type) =>
      importances[type] ?? NotificationImportance.high;

  NotificationPreferences copyWith({
    bool? silentAll,
    Map<AppNotificationType, bool>? enabled,
    Map<AppNotificationType, NotificationTone>? tones,
    Map<AppNotificationType, NotificationImportance>? importances,
  }) {
    return NotificationPreferences(
      silentAll: silentAll ?? this.silentAll,
      enabled: enabled ?? Map.from(this.enabled),
      tones: tones ?? Map.from(this.tones),
      importances: importances ?? Map.from(this.importances),
    );
  }

  Map<String, dynamic> toJson() => {
        'silentAll': silentAll,
        'enabled': {
          for (final entry in enabled.entries) entry.key.value: entry.value,
        },
        'tones': {
          for (final entry in tones.entries) entry.key.value: entry.value.value,
        },
        'importances': {
          for (final entry in importances.entries)
            entry.key.value: entry.value.value,
        },
      };

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    final rawEnabled = json['enabled'];
    final enabled = <AppNotificationType, bool>{
      for (final type in AppNotificationType.values) type: true,
    };
    if (rawEnabled is Map) {
      for (final type in AppNotificationType.values) {
        final value = rawEnabled[type.value];
        if (value is bool) enabled[type] = value;
      }
    }
    final rawTones = json['tones'];
    final tones = <AppNotificationType, NotificationTone>{
      for (final type in AppNotificationType.values)
        type: const NotificationPreferences().toneFor(type),
    };
    if (rawTones is Map) {
      for (final type in AppNotificationType.values) {
        tones[type] = NotificationTone.fromValue(
          rawTones[type.value]?.toString(),
        );
      }
    }
    final rawImportances = json['importances'];
    final importances = <AppNotificationType, NotificationImportance>{
      for (final type in AppNotificationType.values)
        type: const NotificationPreferences().importanceFor(type),
    };
    if (rawImportances is Map) {
      for (final type in AppNotificationType.values) {
        importances[type] = NotificationImportance.fromValue(
          rawImportances[type.value]?.toString(),
        );
      }
    }
    return NotificationPreferences(
      silentAll: json['silentAll'] == true,
      enabled: enabled,
      tones: tones,
      importances: importances,
    );
  }

  static Future<NotificationPreferences> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return const NotificationPreferences();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const NotificationPreferences();
      }
      return NotificationPreferences.fromJson(decoded);
    } catch (_) {
      return const NotificationPreferences();
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, jsonEncode(toJson()));
    } catch (_) {
      // El silenciado es best-effort; no debe bloquear la UI.
    }
  }
}

/// Destino solicitado al tocar una notificación. Lo consume `AppShell` para
/// llevar al usuario a Pedidos con el filtro correcto.
class NotificationTarget {
  const NotificationTarget({
    required this.type,
    required this.orderFilter,
    this.orderId,
  });

  final AppNotificationType type;
  final String orderFilter;
  final String? orderId;
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await NotificationService.instance.initializeForBackground();
  await NotificationService.instance.showRemote(message);
}

/// Puente entre Firebase Cloud Messaging y las notificaciones locales sonoras.
///
/// FCM entrega mensajes `data` en segundo plano; este servicio decide si se
/// muestran (según preferencias), con qué canal/tono y qué hacer al tocarlos.
/// Cada tipo tiene su propio canal Android, así que importancia y sonido se
/// pueden diferenciar en los ajustes de la app y en los del sistema.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const legacyChannelId = 'rm_pos_alerts';
  static const channelDescription = 'Alertas del restaurante';

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final Set<String> _recentEventIds = <String>{};

  bool _initialized = false;
  bool _pluginReady = false;
  String? _token;
  NotificationPreferences _preferences = const NotificationPreferences();
  void Function(Map<String, dynamic> data)? _onTap;
  void Function(String token)? _onTokenRefresh;

  Future<void> initialize({
    required NotificationPreferences preferences,
    required void Function(Map<String, dynamic> data) onTap,
    void Function(String token)? onTokenRefresh,
  }) async {
    _preferences = preferences;
    _onTap = onTap;
    _onTokenRefresh = onTokenRefresh;
    if (_initialized) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      await _initPlugin();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      FirebaseMessaging.onMessage.listen(showRemote);
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _notifyTap(message.data);
      });
      // `onRegistered` de firebase_messaging 17 entrega el FID, no el token FCM
      // que necesita `sendEach()`. El token real sigue en `onTokenRefresh`.
      // ignore: deprecated_member_use
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _token = token;
        _onTokenRefresh?.call(token);
      });
      // ignore: deprecated_member_use
      final fcmToken = await FirebaseMessaging.instance.getToken();
      _token = fcmToken;
      if (fcmToken != null) _onTokenRefresh?.call(fcmToken);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _notifyTap(initial.data);
      _initialized = true;
    } catch (_) {
      // Sin google-services.json (modo demo/tests) la app sigue funcionando.
    }
  }

  /// Inicialización mínima para el isolate del handler en segundo plano.
  /// Cada isolate tiene su propia copia de este singleton: las preferencias se
  /// releen del almacenamiento para que «Silenciar todas» también aplique aquí.
  Future<void> initializeForBackground() async {
    _preferences = await NotificationPreferences.load();
    if (_pluginReady) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      await _initPlugin();
    } catch (_) {
      // Nada que mostrar sin configuración nativa.
    }
  }

  static String channelIdFor(
    AppNotificationType type,
    NotificationImportance importance,
  ) =>
      'rm_pos_alerts_${type.value}_${importance.value}';

  static String channelNameFor(AppNotificationType type) =>
      'Alertas · ${type.label}';

  Future<void> _initPlugin() async {
    if (_pluginReady) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _local.initialize(
      settings: InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );
    final plugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      await plugin?.deleteNotificationChannel(channelId: legacyChannelId);
    } catch (_) {
      // Canal heredado: solo existe en instalaciones anteriores.
    }
    for (final type in AppNotificationType.values) {
      await _ensureChannel(type, _preferences.importanceFor(type));
    }
    _pluginReady = true;
  }

  Future<void> _ensureChannel(
    AppNotificationType type,
    NotificationImportance importance,
  ) async {
    final plugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (plugin == null) return;
    await plugin.createNotificationChannel(
      AndroidNotificationChannel(
        channelIdFor(type, importance),
        channelNameFor(type),
        description: '$channelDescription · ${type.label} · ${importance.label}',
        importance: importance.androidImportance,
        playSound: false,
      ),
    );
  }

  Future<void> setPreferences(NotificationPreferences preferences) async {
    final previous = _preferences;
    _preferences = preferences;
    await preferences.save();
    if (!_pluginReady) return;
    final plugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (plugin == null) return;
    for (final type in AppNotificationType.values) {
      final before = previous.importanceFor(type);
      final after = preferences.importanceFor(type);
      if (before == after) continue;
      // Android no permite cambiar la importancia de un canal creado: se
      // elimina y se crea uno nuevo con el mismo tipo y la nueva importancia.
      try {
        await plugin.deleteNotificationChannel(
          channelId: channelIdFor(type, before),
        );
      } catch (_) {
        // El canal quizá nunca llegó a crearse.
      }
    }
    for (final type in AppNotificationType.values) {
      await _ensureChannel(type, preferences.importanceFor(type));
    }
  }

  Future<String?> getToken() async {
    if (!_initialized) return null;
    if (_token == null) {
      try {
        // En firebase_messaging 17 `register()` entrega el FID; el token FCM
        // para envíos directos lo devuelve `getToken()`.
        // ignore: deprecated_member_use
        _token = await FirebaseMessaging.instance.getToken();
      } catch (_) {
        // Sin permiso no hay token; onTokenRefresh lo registrará luego.
      }
    }
    return _token;
  }

  Future<void> deleteToken() async {
    try {
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
      _token = null;
    } catch (_) {
      // Best-effort al cerrar sesión.
    }
  }

  Future<void> showRemote(RemoteMessage message) async {
    final data = Map<String, dynamic>.from(message.data);
    data.putIfAbsent('title', () => message.notification?.title ?? '');
    data.putIfAbsent('body', () => message.notification?.body ?? '');
    await _show(data);
  }

  /// Aviso generado dentro de la APK (por ejemplo al detectar un pedido nuevo
  /// por polling mientras FCM no está disponible).
  Future<void> showLocal({
    required AppNotificationType type,
    required String tenantId,
    required String title,
    required String body,
    String? orderId,
  }) async {
    await _show({
      'type': type.value,
      'tenantId': tenantId,
      'title': title,
      'body': body,
      'orderId': ?orderId,
      'eventId': '${type.value}:$tenantId:${orderId ?? title}:'
          '${DateTime.now().microsecondsSinceEpoch}',
    });
  }

  Future<void> cancelAll() async {
    if (!_pluginReady) return;
    try {
      await _local.cancelAll();
    } catch (_) {
      // Nada que cancelar.
    }
  }

  Future<void> _show(Map<String, dynamic> data) async {
    final type = AppNotificationType.fromValue(data['type']?.toString());
    if (type == null || !_preferences.isEnabled(type)) return;
    if (!_pluginReady) {
      try {
        await _initPlugin();
      } catch (_) {
        return;
      }
    }

    final eventId = (data['eventId']?.toString() ?? '').isNotEmpty
        ? data['eventId']!.toString()
        : '${type.value}:${data['tenantId'] ?? ''}:${data['orderId'] ?? ''}';
    if (_recentEventIds.contains(eventId)) return;
    _recentEventIds.add(eventId);
    if (_recentEventIds.length > 120) {
      _recentEventIds.clear();
      _recentEventIds.add(eventId);
    }

    final title = data['title']?.toString().trim().isNotEmpty == true
        ? data['title']!.toString()
        : type.label;
    final body = data['body']?.toString() ?? '';
    final importance = _preferences.importanceFor(type);
    final channelId = channelIdFor(type, importance);
    try {
      await _ensureChannel(type, importance);
      await _local.show(
        id: eventId.hashCode & 0x7fffffff,
        title: title,
        body: body,
        payload: jsonEncode(data),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelNameFor(type),
            channelDescription: '$channelDescription · ${type.label}',
            importance: importance.androidImportance,
            priority: importance.androidPriority,
            playSound: false,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: 'default',
          ),
        ),
      );
      await _playSound(_preferences.toneFor(type));
    } catch (_) {
      // Sin plugin nativo (tests/modo demo) no hay notificación que mostrar.
    }
  }

  /// El sonido del canal no es confiable en MIUI/HyperOS: el usuario puede
  /// dejarlo bloqueado y la ROM lo restaura. Lo reproduce el plugin nativo,
  /// con el tono elegido para esta categoría.
  Future<void> _playSound(NotificationTone tone) async {
    try {
      await NotificationSound.play(tone: tone.value);
    } catch (_) {
      // Sin plugin nativo (tests/modo demo) no hay audio que reproducir.
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) _notifyTap(decoded);
    } catch (_) {
      // Payload ajeno: se ignora.
    }
  }

  void _notifyTap(Map<String, dynamic> data) => _onTap?.call(data);
}
