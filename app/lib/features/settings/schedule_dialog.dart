import 'package:flutter/material.dart';

import '../../core/models/restaurant_settings.dart';
import '../../core/theme/app_theme.dart';

/// Valor devuelto por [showScheduleDialog].
class ScheduleConfig {
  const ScheduleConfig({
    required this.timeZone,
    required this.openingDays,
    required this.openTime,
    required this.closeTime,
  });

  final String timeZone;
  final List<String> openingDays;
  final String openTime;
  final String closeTime;

  String get hoursLabel => RestaurantSettings.scheduleHours(
        days: openingDays,
        openTime: openTime,
        closeTime: closeTime,
      );
}

Future<ScheduleConfig?> showScheduleDialog(
  BuildContext context, {
  required ScheduleConfig current,
}) {
  return showDialog<ScheduleConfig>(
    context: context,
    builder: (_) => _ScheduleDialog(current: current),
  );
}

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog({required this.current});

  final ScheduleConfig current;

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  late final TextEditingController _timeZone;
  late final TextEditingController _openTime;
  late final TextEditingController _closeTime;
  late List<String> _days;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timeZone = TextEditingController(text: widget.current.timeZone);
    _openTime = TextEditingController(text: widget.current.openTime);
    _closeTime = TextEditingController(text: widget.current.closeTime);
    _days = List<String>.from(widget.current.openingDays);
  }

  @override
  void dispose() {
    _timeZone.dispose();
    _openTime.dispose();
    _closeTime.dispose();
    super.dispose();
  }

  void _save() {
    final zone = _timeZone.text.trim();
    final open = _openTime.text.trim();
    final close = _closeTime.text.trim();
    String? error;
    if (!RestaurantSettings.isValidTimeZone(zone)) {
      error = 'Escribe una zona horaria válida, por ejemplo America/Bogota.';
    } else if (!RestaurantSettings.isValidTimeOfDay(open) ||
        !RestaurantSettings.isValidTimeOfDay(close)) {
      error = 'Las horas deben tener el formato HH:mm (24 horas).';
    } else if (open.compareTo(close) >= 0) {
      error = 'La hora de cierre debe ser posterior a la de apertura.';
    } else if (_days.isEmpty) {
      error = 'Activa al menos un día.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(
      ScheduleConfig(
        timeZone: zone,
        openingDays: RestaurantSettings.cleanOpeningDays(_days),
        openTime: open,
        closeTime: close,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = RestaurantSettings.scheduleHours(
      days: RestaurantSettings.cleanOpeningDays(_days),
      openTime: RestaurantSettings.isValidTimeOfDay(_openTime.text)
          ? _openTime.text.trim()
          : widget.current.openTime,
      closeTime: RestaurantSettings.isValidTimeOfDay(_closeTime.text)
          ? _closeTime.text.trim()
          : widget.current.closeTime,
    );
    return AlertDialog(
      title: const Text('Horario y zona horaria'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _timeZone,
                decoration: const InputDecoration(
                  labelText: 'Zona horaria (IANA)',
                  hintText: 'America/Bogota',
                  helperText: 'Ejemplo: America/Mexico_City, Europe/Madrid, UTC',
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final zone in RestaurantSettings.suggestionsTimeZone)
                    ActionChip(
                      label: Text(zone),
                      onPressed: () {
                        _timeZone.text = zone;
                        setState(() => _error = null);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const Text('Días en que se reciben pedidos',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final day in RestaurantSettings.openingDayKeys)
                    FilterChip(
                      label: Text(RestaurantSettings.openingDayLabels[day] ?? day),
                      selected: _days.contains(day),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _days = RestaurantSettings.cleanOpeningDays([
                              ..._days,
                              day,
                            ]);
                          } else {
                            _days.remove(day);
                          }
                          _error = null;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _openTime,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Apertura',
                        hintText: '11:30',
                      ),
                      onChanged: (_) => setState(() => _error = null),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _closeTime,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Cierre',
                        hintText: '20:30',
                      ),
                      onChanged: (_) => setState(() => _error = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F1EA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'La web mostrará: $preview',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF44403C),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: AppTheme.danger, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Guardar horario')),
      ],
    );
  }
}
