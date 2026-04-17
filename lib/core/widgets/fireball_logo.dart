import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// App mark (`assets/icon.png`) — use for nav chrome, settings, about, etc.
class FireballLogo extends StatelessWidget {
  const FireballLogo({
    super.key,
    this.size = 40,
    this.borderRadius,
  });

  final double size;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final r = borderRadius ?? BorderRadius.circular(size * 0.22);
    return ClipRRect(
      borderRadius: r,
      child: Image.asset(
        'assets/icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

/// Album art in the player: network URL when available, otherwise the app mark.
class FireballPlayerArtwork extends StatelessWidget {
  const FireballPlayerArtwork({
    super.key,
    required this.networkUrl,
    this.fit = BoxFit.cover,
  });

  final String? networkUrl;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (networkUrl != null && networkUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: networkUrl!,
        fit: fit,
        errorWidget: (_, __, ___) => _assetMark(cs),
      );
    }
    return _assetMark(cs);
  }

  Widget _assetMark(ColorScheme cs) => Image.asset(
        'assets/icon.png',
        fit: fit,
        errorBuilder: (_, __, ___) => Container(
          color: cs.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(
            Icons.music_note_rounded,
            size: 64,
            color: cs.primary.withValues(alpha: 0.45),
          ),
        ),
      );
}
