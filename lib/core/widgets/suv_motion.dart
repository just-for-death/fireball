import 'package:flutter/material.dart';

import '../theme/fireball_tokens.dart';
import '../theme/suv_ui_tokens.dart';

class SuvFadeSlideIn extends StatelessWidget {
  const SuvFadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.beginOffset = const Offset(0, 0.04),
  });

  final Widget child;
  final Duration delay;
  final Offset beginOffset;

  factory SuvFadeSlideIn.staggered({
    Key? key,
    required Widget child,
    required int index,
    Offset beginOffset = const Offset(0, 0.04),
  }) {
    final clamped = index < 0 ? 0 : index;
    final ms = (clamped * 40).clamp(0, 320);
    return SuvFadeSlideIn(
      key: key,
      delay: Duration(milliseconds: ms),
      beginOffset: beginOffset,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: FireballTokens.motionBase + delay,
      curve: FireballTokens.motionCurve,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) {
        final t = Curves.easeOut.transform(value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(
              beginOffset.dx * (1 - t) * 20,
              beginOffset.dy * (1 - t) * 20,
            ),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class SuvPressScale extends StatefulWidget {
  const SuvPressScale({
    super.key,
    required this.child,
    this.scaleDown = 0.98,
  });

  final Widget child;
  final double scaleDown;

  @override
  State<SuvPressScale> createState() => _SuvPressScaleState();
}

class _SuvPressScaleState extends State<SuvPressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: SuvUiTokens.motionQuick,
        curve: FireballTokens.motionCurve,
        scale: _pressed ? widget.scaleDown : 1,
        child: widget.child,
      ),
    );
  }
}
