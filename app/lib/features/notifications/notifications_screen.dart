import 'dart:async';

import 'package:flutter/material.dart';
import 'package:notification_sound/notification_sound.dart';
import 'package:provider/provider.dart';

import '../../core/data/repository.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_theme.dart';

/// Preferencias de avisos del dispositivo. Los tipos desactivados no muestran
/// notificación ni suenan; FCM sigue entregando el mensaje, pero el servicio lo
/// descarta antes de crear la notificación local. Cada categoría tiene tono e
/// importancia propios.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static const _descriptions = {
    AppNotificationType.newOrder: 'Pedidos nuevos de la web y del POS.',
    AppNotificationType.orderReady: 'Cuando un pedido queda listo para entregar.',
    AppNotificationType.lowStock: 'Insumos que bajan de su stock mínimo.',
    AppNotificationType.outOfStock: 'Insumos agotados (stock en cero).',
    AppNotificationType.shiftClosed: 'Cierre de caja y del turno.',
  };

  Future<void> _update(
    BuildContext context,
    NotificationPreferences preferences,
  ) async {
    await context.read<RestaurantRepository>().updateNotificationPreferences(
          preferences,
        );
  }

  Future<void> _updateTone(
    BuildContext context,
    NotificationPreferences preferences,
    AppNotificationType type,
    NotificationTone tone,
  ) async {
    final tones = Map<AppNotificationType, NotificationTone>.from(
      preferences.tones,
    );
    tones[type] = tone;
    await _update(context, preferences.copyWith(tones: tones));
  }

  Future<void> _updateImportance(
    BuildContext context,
    NotificationPreferences preferences,
    AppNotificationType type,
    NotificationImportance importance,
  ) async {
    final importances = Map<AppNotificationType, NotificationImportance>.from(
      preferences.importances,
    );
    importances[type] = importance;
    await _update(context, preferences.copyWith(importances: importances));
  }

  IconData _iconFor(AppNotificationType type) {
    switch (type) {
      case AppNotificationType.newOrder:
        return Icons.receipt_long;
      case AppNotificationType.orderReady:
        return Icons.check_circle;
      case AppNotificationType.lowStock:
        return Icons.inventory_2;
      case AppNotificationType.outOfStock:
        return Icons.block;
      case AppNotificationType.shiftClosed:
        return Icons.point_of_sale;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<RestaurantRepository>();
    final preferences = repository.notificationPreferences;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F4F1),
      appBar: AppBar(
        title: const Text('Notificaciones'),
        backgroundColor: AppTheme.brandDark,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEDEAE6)),
            ),
            child: SwitchListTile(
              value: preferences.silentAll,
              onChanged: (value) => unawaited(
                _update(context, preferences.copyWith(silentAll: value)),
              ),
              title: const Text(
                'Silenciar todas',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'No mostrar ni sonar ningún aviso en este dispositivo.',
                style: TextStyle(fontSize: 11),
              ),
              activeThumbColor: AppTheme.brand,
            ),
          ),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Categorías',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                for (final type in AppNotificationType.values) ...[
                  SwitchListTile(
                    value: preferences.isEnabled(type),
                    onChanged: (value) {
                      final enabled = Map<AppNotificationType, bool>.from(
                        preferences.enabled,
                      );
                      enabled[type] = value;
                      unawaited(
                        _update(
                          context,
                          preferences.copyWith(enabled: enabled),
                        ),
                      );
                    },
                    secondary: Icon(
                      _iconFor(type),
                      color: AppTheme.brandDark,
                    ),
                    title: Text(
                      type.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      _descriptions[type] ?? '',
                      style: const TextStyle(fontSize: 11),
                    ),
                    activeThumbColor: AppTheme.brand,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<NotificationTone>(
                            // ignore: deprecated_member_use
                            value: preferences.toneFor(type),
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Tono',
                              isDense: true,
                            ),
                            items: [
                              for (final tone in NotificationTone.values)
                                DropdownMenuItem<NotificationTone>(
                                  value: tone,
                                  child: Text(
                                    tone.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                unawaited(
                                  _updateTone(context, preferences, type, value),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<NotificationImportance>(
                            // ignore: deprecated_member_use
                            value: preferences.importanceFor(type),
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Importancia',
                              isDense: true,
                            ),
                            items: [
                              for (final importance
                                  in NotificationImportance.values)
                                DropdownMenuItem<NotificationImportance>(
                                  value: importance,
                                  child: Text(
                                    importance.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                unawaited(
                                  _updateImportance(
                                    context,
                                    preferences,
                                    type,
                                    value,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: 'Probar tono',
                          onPressed: () => unawaited(
                            NotificationSound.play(
                              tone: preferences.toneFor(type).value,
                            ),
                          ),
                          icon: const Icon(Icons.volume_up_rounded),
                          color: AppTheme.brandDark,
                        ),
                      ],
                    ),
                  ),
                  if (type != AppNotificationType.values.last)
                    const Divider(height: 1),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'El sonido respeta el modo Silencio/No molestar del teléfono y se '
            'reproduce desde la app para que MIUI/HyperOS no lo silencie. '
            'Cambiar la importancia crea una categoría nueva en Android. '
            'Para recibir avisos con la app cerrada, mantén la sesión iniciada '
            'y el permiso de notificaciones activo.',
            style: TextStyle(fontSize: 11, color: Color(0xFF78716C)),
          ),
        ],
      ),
    );
  }
}
