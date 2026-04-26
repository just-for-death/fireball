import 'package:flutter/material.dart';
import '../theme/fireball_tokens.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final Color? accent;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;

  const GlassCard({
    super.key,
    required this.child,
    this.blur = 20,
    this.opacity = 0.08,
    this.accent,
    this.borderRadius,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(24);
    final surface = const Color(0xFF181818);
    return AnimatedContainer(
      duration: FireballTokens.motionFast,
      curve: FireballTokens.motionCurve,
      padding: padding,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: br,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.6,
        ),
      ),
      child: Stack(
        children: [
          if (accent != null)
            Positioned(
              top: -20,
              right: -20,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent!.withValues(alpha: 0.12),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class GlassPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  const GlassPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = color ?? cs.primary;
    // Reserve space so the selected shadow stays inside layout bounds (avoids
    // clipping / "overflow" halos in tight rows like the home country ListView).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(25),
        onTap: onTap,
        child: AnimatedContainer(
          duration: FireballTokens.motionBase,
          curve: FireballTokens.motionCurve,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.85)
                  : Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.2),
                      blurRadius: 6,
                      spreadRadius: 0,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? (color != null ? Colors.white : cs.onPrimary)
                  : Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

class PremiumBackground extends StatelessWidget {
  final Widget child;

  const PremiumBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080909),
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF1A1A1A),
                    const Color(0xFF121212),
                    const Color(0xFF0A0A0A),
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
