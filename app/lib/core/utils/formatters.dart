String formatCop(num value) {
  final rounded = value.round().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < rounded.length; index++) {
    final remaining = rounded.length - index;
    buffer.write(rounded[index]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write('.');
  }
  return '\$ ${buffer.toString()}';
}

String twoDigits(int value) => value.toString().padLeft(2, '0');

String formatTime(DateTime value) =>
    '${twoDigits(value.hour)}:${twoDigits(value.minute)}';

String formatDateTime(DateTime value) =>
    '${twoDigits(value.day)}/${twoDigits(value.month)}/${value.year} '
    '${formatTime(value)}';

String formatShortDate(DateTime value) =>
    '${twoDigits(value.day)}/${twoDigits(value.month)}';

String relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return 'ahora';
  if (difference.inMinutes < 60) return 'hace ${difference.inMinutes} min';
  if (difference.inHours < 24) return 'hace ${difference.inHours} h';
  return 'hace ${difference.inDays} d';
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String dayKey(DateTime value) =>
    '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)}';

String newId(String prefix) {
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final random = DateTime.now().millisecond % 997;
  return '$prefix-$stamp-$random';
}

String orderCode() {
  final now = DateTime.now();
  final date =
      '${now.year}${twoDigits(now.month)}${twoDigits(now.day)}';
  final random = (now.microsecondsSinceEpoch % 9000 + 1000).toString();
  return 'RM-$date-$random';
}
