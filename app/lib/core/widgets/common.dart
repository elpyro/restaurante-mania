import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent = AppTheme.brand,
    this.subtitle,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDEAE6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A1C1917),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF78716C),
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                color: Color(0xFF78716C),
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: card,
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.padding = const EdgeInsets.only(top: 20, bottom: 10),
  });

  final String title;
  final Widget? action;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: const Color(0xFFA8A29E)),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.ink,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF78716C),
                height: 1.4,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class ConnectivityBadge extends StatelessWidget {
  const ConnectivityBadge({
    super.key,
    required this.online,
    required this.syncing,
  });

  final bool online;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    final color = syncing
        ? AppTheme.brand
        : online
            ? AppTheme.success
            : AppTheme.danger;
    final label = syncing
        ? 'Sincronizando'
        : online
            ? 'En línea'
            : 'Sin conexión';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (syncing)
            SizedBox(
              width: 9,
              height: 9,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
            )
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class MenuItemImage extends StatelessWidget {
  const MenuItemImage({
    super.key,
    required this.imageUrl,
    required this.emoji,
    this.size = 44,
    this.borderRadius = 12,
    this.emojiFontSize,
  });

  final String imageUrl;
  final String emoji;
  final double size;
  final double borderRadius;
  final double? emojiFontSize;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl.trim();
    final emojiStyle = TextStyle(fontSize: emojiFontSize ?? size * 0.52);
    Widget fallback() => Center(child: Text(emoji, style: emojiStyle));

    final content = url.isEmpty
        ? fallback()
        : (url.startsWith('http://') || url.startsWith('https://'))
            ? Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback(),
              )
            : Image.file(
                File(url),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback(),
              );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFFFFF7ED),
        child: content,
      ),
    );
  }
}

