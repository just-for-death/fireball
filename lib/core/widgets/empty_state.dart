import 'package:flutter/material.dart';

/// Shared empty / error placeholder for Home, Search, Library, and lists.
class FireballEmptyState extends StatelessWidget {
  const FireballEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,

    /// Use light text/icons on dark glass / PremiumBackground screens.
    this.onDarkGlass = false,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool onDarkGlass;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconC = onDarkGlass
        ? Colors.white.withValues(alpha: 0.35)
        : cs.onSurface.withValues(alpha: 0.35);
    final titleC = onDarkGlass
        ? Colors.white.withValues(alpha: 0.88)
        : cs.onSurface.withValues(alpha: 0.85);
    final subC = onDarkGlass
        ? Colors.white.withValues(alpha: 0.45)
        : cs.onSurface.withValues(alpha: 0.5);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: iconC),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: titleC,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: subC,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
