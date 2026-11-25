import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/theme/app_theme.dart';

void main() {
  test('la APK conserva su paleta original', () {
    expect(AppTheme.brand, const Color(0xFFEF6408));
    expect(AppTheme.brandDark, const Color(0xFFC64B09));
    expect(AppTheme.ink, const Color(0xFF1C1917));
    expect(AppTheme.canvas, const Color(0xFFFAF8F5));
    expect(AppTheme.success, const Color(0xFF059669));
  });

  test('el tema sigue siendo claro y usa el naranja en botones', () {
    final theme = AppTheme.light();

    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, AppTheme.canvas);
    final buttonBackground = theme.filledButtonTheme.style!.backgroundColor!;
    expect(buttonBackground.resolve(const <WidgetState>{}), AppTheme.brand);

    expect(
      theme.navigationBarTheme.indicatorColor,
      AppTheme.brand.withValues(alpha: 0.14),
    );
  });
}
