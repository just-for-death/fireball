import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../core/models/track.dart';
import '../core/store/providers.dart';
import '../features/remote/remote_screen.dart';

void showMiniPlayerOverflowMenu({
  required BuildContext context,
  required Track track,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.cast_rounded),
            title: const Text('Remote control'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RemoteScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_rounded),
            title: const Text('Share track'),
            onTap: () async {
              Navigator.pop(ctx);
              await Share.share(
                '${track.title} — ${track.artist}',
                subject: track.title,
              );
            },
          ),
        ],
      ),
    ),
  );
}

class MiniPlayer extends ConsumerWidget {
  /// [compact] = true renders a small sidebar strip (iPad glass sidebar).
  /// [sidebarIconOnly] = true when the iPad sidebar is collapsed to a narrow rail.
  const MiniPlayer({
    super.key,
    this.compact = false,
    this.sidebarIconOnly = false,
  });
  final bool compact;
  final bool sidebarIconOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final track = player.currentTrack;
    if (track == null) return const SizedBox.shrink();

    if (compact && sidebarIconOnly) {
      return _NarrowRailMiniPlayer(player: player, track: track);
    }
    if (compact) return _CompactMiniPlayer(player: player, track: track);

    final width = MediaQuery.sizeOf(context).width;
    final isTablet = width >= 600;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 12),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _MiniPlayerCard(
            player: player,
            track: track,
            isTablet: isTablet,
          ),
        ),
      ),
    );
  }
}

// ── Full mini-player card ─────────────────────────────────────────────────────
class _MiniPlayerCard extends StatelessWidget {
  const _MiniPlayerCard({
    required this.player,
    required this.track,
    required this.isTablet,
  });

  final PlayerState player;
  final Track track;
  final bool isTablet;

  @override
  Widget build(BuildContext context) {
    final ref = ProviderScope.containerOf(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = player.duration.inMilliseconds > 0
        ? (player.position.inMilliseconds / player.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: () => context.push('/player'),
      onVerticalDragEnd: (details) {
        if (details.velocity.pixelsPerSecond.dy < -100) {
          context.push('/player');
        }
      },
      onHorizontalDragEnd: (details) {
        final vx = details.velocity.pixelsPerSecond.dx;
        if (vx > 280) {
          ref.read(playerProvider.notifier).previous();
        } else if (vx < -280) {
          ref.read(playerProvider.notifier).next();
        }
      },
      onLongPress: () => showMiniPlayerOverflowMenu(
            context: context,
            track: track,
          ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: isTablet ? 80 : 72,
            decoration: BoxDecoration(
              color: isDark
                  ? cs.surfaceContainer.withValues(alpha: 0.88)
                  : cs.surfaceContainerHigh.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
                width: 0.5,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.05),
                  Colors.transparent,
                ],
              ),
            ),
            child: Stack(
              children: [
                // Progress bar at bottom
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 2.5,
                      backgroundColor: Colors.transparent,
                      color: cs.primary.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      // Artwork with playing indicator overlay
                      _ArtworkTile(
                          track: track,
                          isPlaying: player.isPlaying,
                          cs: cs),
                      const SizedBox(width: 12),
                      // Title + artist
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: isTablet ? 15 : 14,
                                color: player.isPlaying
                                    ? cs.primary
                                    : cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: isTablet ? 13 : 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Tablet: shuffle + repeat controls
                      if (isTablet) ...[
                        IconButton(
                          icon: Icon(Icons.shuffle_rounded,
                              size: 20,
                              color: player.shuffled
                                  ? cs.primary
                                  : cs.onSurfaceVariant),
                          onPressed: () => ref
                              .read(playerProvider.notifier)
                              .toggleShuffle(),
                        ),
                        IconButton(
                          icon: Icon(
                            player.repeatMode == ElysiumRepeatMode.one
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                            size: 20,
                            color: player.repeatMode != ElysiumRepeatMode.off
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                          onPressed: () => ref
                              .read(playerProvider.notifier)
                              .cycleRepeat(),
                        ),
                      ],
                      // Play / Pause
                      IconButton(
                        icon: Icon(
                          player.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 28,
                          color: cs.onSurface,
                        ),
                        onPressed: () => ref
                            .read(playerProvider.notifier)
                            .togglePlayPause(),
                      ),
                      IconButton(
                        icon: Icon(Icons.skip_next_rounded,
                            size: 26, color: cs.onSurfaceVariant),
                        onPressed: () =>
                            ref.read(playerProvider.notifier).next(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Icon-only rail (collapsed iPad sidebar ~72px) ────────────────────────────
class _NarrowRailMiniPlayer extends StatelessWidget {
  const _NarrowRailMiniPlayer({required this.player, required this.track});
  final PlayerState player;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final ref = ProviderScope.containerOf(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = player.duration.inMilliseconds > 0
        ? (player.position.inMilliseconds / player.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return Tooltip(
      message: '${track.title} — tap for full player',
      child: Semantics(
        label: 'Now playing: ${track.title}',
        button: true,
        child: GestureDetector(
          onTap: () => context.push('/player'),
          onLongPress: () => showMiniPlayerOverflowMenu(
                context: context,
                track: track,
              ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark
                      ? cs.surfaceContainer.withValues(alpha: 0.85)
                      : cs.surfaceContainerHigh.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: _ArtworkTile(
                        track: track,
                        isPlaying: player.isPlaying,
                        cs: cs,
                        size: 44,
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 36,
                      ),
                      icon: Icon(
                        player.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 26,
                        color: cs.primary,
                      ),
                      onPressed: () =>
                          ref.read(playerProvider.notifier).togglePlayPause(),
                    ),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      color: cs.primary.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Compact mini-player (iPad sidebar) ───────────────────────────────────────
class _CompactMiniPlayer extends StatelessWidget {
  const _CompactMiniPlayer({required this.player, required this.track});
  final PlayerState player;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final ref = ProviderScope.containerOf(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = player.duration.inMilliseconds > 0
        ? (player.position.inMilliseconds / player.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: () => context.push('/player'),
      onLongPress: () => showMiniPlayerOverflowMenu(
            context: context,
            track: track,
          ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? cs.surfaceContainer.withValues(alpha: 0.8)
                  : cs.surfaceContainerHigh.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
                width: 0.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      _ArtworkTile(
                          track: track,
                          isPlaying: player.isPlaying,
                          cs: cs,
                          size: 40),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: player.isPlaying
                                ? cs.primary
                                : cs.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                        icon: Icon(
                          player.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 24,
                          color: cs.onSurface,
                        ),
                        onPressed: () => ref
                            .read(playerProvider.notifier)
                            .togglePlayPause(),
                      ),
                    ],
                  ),
                ),
                // Thin progress line
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: cs.primary.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared artwork tile ───────────────────────────────────────────────────────
class _ArtworkTile extends StatelessWidget {
  const _ArtworkTile({
    required this.track,
    required this.isPlaying,
    required this.cs,
    this.size = 48,
  });

  final Track track;
  final bool isPlaying;
  final ColorScheme cs;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.21),
          child: track.artwork != null
              ? CachedNetworkImage(
                  imageUrl: track.artwork!,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _placeholder(),
                )
              : _placeholder(),
        ),
        if (isPlaying)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.21),
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: const Center(child: _PlayingIndicator()),
              ),
            ),
          ),
      ],
    );
  }

  Widget _placeholder() => Image.asset(
        'assets/icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: cs.surfaceContainerHighest,
          child: Icon(Icons.music_note_rounded,
              color: cs.primary.withValues(alpha: 0.6), size: size * 0.5),
        ),
      );
}

// ── Animated bars playing indicator ──────────────────────────────────────────
class _PlayingIndicator extends StatefulWidget {
  const _PlayingIndicator();

  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
        3,
        (i) => AnimationController(
              duration: Duration(milliseconds: 300 + (i * 100)),
              vsync: this,
            ));
    _animations = _controllers
        .map((c) => Tween<double>(begin: 0.3, end: 1.0).animate(
              CurvedAnimation(parent: c, curve: Curves.easeInOut),
            ))
        .toList();

    for (int i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 100), () {
        if (mounted) { _controllers[i].repeat(reverse: true); }
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
          3,
          (i) => AnimatedBuilder(
                animation: _animations[i],
                builder: (context, child) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 3,
                    height: 12 * _animations[i].value,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  );
                },
              )),
    );
  }
}
