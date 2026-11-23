import 'package:flutter/material.dart';

import '../models/order.dart';
import '../models/restaurant_table.dart';
import '../theme/app_theme.dart';

Color orderStatusColor(OrderStatus status) => switch (status) {
      OrderStatus.pending => AppTheme.warning,
      OrderStatus.confirmed => const Color(0xFF2563EB),
      OrderStatus.preparing => AppTheme.brand,
      OrderStatus.ready => AppTheme.success,
      OrderStatus.sent => const Color(0xFF0EA5E9),
      OrderStatus.delivered => const Color(0xFF57534E),
      OrderStatus.cancelled => AppTheme.danger,
    };

IconData orderStatusIcon(OrderStatus status) => switch (status) {
      OrderStatus.pending => Icons.hourglass_top_rounded,
      OrderStatus.confirmed => Icons.check_circle_outline_rounded,
      OrderStatus.preparing => Icons.soup_kitchen_rounded,
      OrderStatus.ready => Icons.room_service_rounded,
      OrderStatus.sent => Icons.local_shipping_outlined,
      OrderStatus.delivered => Icons.done_all_rounded,
      OrderStatus.cancelled => Icons.cancel_outlined,
    };

Color tableStatusColor(TableStatus status) => switch (status) {
      TableStatus.libre => AppTheme.success,
      TableStatus.ocupada => const Color(0xFF2563EB),
      TableStatus.esperandoPedido => AppTheme.warning,
      TableStatus.pidiendoCuenta => AppTheme.brand,
    };

IconData tableStatusIcon(TableStatus status) => switch (status) {
      TableStatus.libre => Icons.check_circle_outline_rounded,
      TableStatus.ocupada => Icons.groups_rounded,
      TableStatus.esperandoPedido => Icons.restaurant_rounded,
      TableStatus.pidiendoCuenta => Icons.receipt_long_rounded,
    };

Color paymentColor(PaymentStatus status) => switch (status) {
      PaymentStatus.pending => AppTheme.warning,
      PaymentStatus.paid => AppTheme.success,
      PaymentStatus.refunded => AppTheme.danger,
    };
