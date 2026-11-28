import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/data/repository.dart';
import 'package:app/core/data/tenant.dart';
import 'package:app/core/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('preferencias se serializan y se restauran', () async {
    final original = NotificationPreferences(
      silentAll: false,
      enabled: {
        AppNotificationType.newOrder: true,
        AppNotificationType.orderReady: false,
        AppNotificationType.lowStock: true,
        AppNotificationType.outOfStock: true,
        AppNotificationType.shiftClosed: false,
      },
      tones: {
        AppNotificationType.newOrder: NotificationTone.double,
        AppNotificationType.orderReady: NotificationTone.chime,
        AppNotificationType.lowStock: NotificationTone.classic,
        AppNotificationType.outOfStock: NotificationTone.soft,
        AppNotificationType.shiftClosed: NotificationTone.soft,
      },
      importances: {
        AppNotificationType.newOrder: NotificationImportance.high,
        AppNotificationType.orderReady: NotificationImportance.normal,
        AppNotificationType.lowStock: NotificationImportance.low,
        AppNotificationType.outOfStock: NotificationImportance.high,
        AppNotificationType.shiftClosed: NotificationImportance.low,
      },
    );

    await original.save();
    final restored = await NotificationPreferences.load();

    expect(restored.silentAll, isFalse);
    expect(restored.enabled[AppNotificationType.orderReady], isFalse);
    expect(restored.enabled[AppNotificationType.shiftClosed], isFalse);
    expect(restored.isEnabled(AppNotificationType.newOrder), isTrue);
    expect(restored.isEnabled(AppNotificationType.orderReady), isFalse);
    expect(
      restored.toneFor(AppNotificationType.newOrder),
      NotificationTone.double,
    );
    expect(
      restored.importanceFor(AppNotificationType.lowStock),
      NotificationImportance.low,
    );
    expect(
      restored.importanceFor(AppNotificationType.outOfStock),
      NotificationImportance.high,
    );
  });

  test('silenciar todo desactiva también los tipos habilitados', () {
    const preferences = NotificationPreferences(silentAll: true);
    for (final type in AppNotificationType.values) {
      expect(preferences.isEnabled(type), isFalse);
    }
  });

  test('cada tipo tiene tono e importancia por defecto', () {
    const preferences = NotificationPreferences();
    expect(preferences.toneFor(AppNotificationType.outOfStock),
        NotificationTone.double);
    expect(
      NotificationService.channelIdFor(
        AppNotificationType.outOfStock,
        preferences.importanceFor(AppNotificationType.outOfStock),
      ),
      'rm_pos_alerts_out_of_stock_high',
    );
  });

  test('el payload push resuelve el tipo y el filtro de pedidos', () async {
    final repository = await RestaurantRepository.load(
      watchConnectivity: false,
    );
    addTearDown(repository.dispose);

    await repository.handleNotificationTap({
      'type': 'order_ready',
      'tenantId': defaultTenantId,
      'orderId': 'order-42',
    });

    final target = repository.notificationTarget.value;
    expect(target, isNotNull);
    expect(target!.type, AppNotificationType.orderReady);
    expect(target.orderFilter, 'ready');
    expect(target.orderId, 'order-42');
  });
}
