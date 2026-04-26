import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../core/models/track.dart';
import '../core/store/providers.dart';
import '../core/theme/fireball_tokens.dart';

void showMiniPlayerOverflowMenu({
  required BuildContext context,
  required Track track,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useRootNavigator: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.cast_rounded),
            title: const Text('Connect to a device'),
            onTap: () {
              Navigator.pop(ctx);
              context.go('/remote');
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_rounded),
            title: const Text('Share'),
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
    this.desktopDock = false,
  });
  final bool compact;
  final bool sidebarIconOnly;
  final bool desktopDock;

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

    if (desktopDock) {
      return _DesktopBottomBar(player: player, track: track);
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 8 : 6),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
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

class _DesktopBottomBar extends StatelessWidget {
  const _DesktopBottomBar({
    required this.player,
    required this.track,
  });

  final PlayerState player;
  final Track track;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final h = d.inHours.toString().padLeft(2, '0');
      return '$h:$m:$s';
    }
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final ref = ProviderScope.containerOf(context);
    final cs = Theme.of(context).colorScheme;
    final progress = player.duration.inMilliseconds > 0
        ? (player.position.inMilliseconds / player.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return Container(
      height: 80,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(FireballTokens.desktopPlayerRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 232,
            child: Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      hoverColor: Colors.white.withValues(alpha: 0.06),
                      splashColor: Colors.white.withValues(alpha: 0.09),
                      highlightColor: Colors.white.withValues(alpha: 0.05),
                      onTap: () => context.push('/player'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                        child: Row(
                          children: [
                            _ArtworkTile(
                              track: track,
                              isPlaying: player.isPlaying,
                              cs: cs,
                              size: 50,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.64),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                  onPressed: () async {
                    final fav = player.isFavorite(track.effectiveId);
                    if (fav) {
                      await ref
                          .read(localStoreProvider.notifier)
                          .deleteFavorite(track.effectiveId);
                      ref.read(playerProvider.notifier).removeFavorite(track.effectiveId);
                    } else {
                      await ref.read(localStoreProvider.notifier).addFavorite(track);
                      ref.read(playerProvider.notifier).addFavorite(track);
                    }
                  },
                  icon: Icon(
                    player.isFavorite(track.effectiveId)
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 18,
                    color: player.isFavorite(track.effectiveId)
                        ? cs.primary
                        : Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                      onPressed: () =>
                          ref.read(playerProvider.notifier).toggleShuffle(),
                      icon: Icon(
                        Icons.shuffle_rounded,
                        size: 18,
                        color: player.shuffled
                            ? cs.primary
                            : Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    IconButton(
                      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                      onPressed: () => ref.read(playerProvider.notifier).previous(),
                      icon: const Icon(Icons.skip_previous_rounded,
                          size: 22, color: Colors.white),
                    ),
                    IconButton(
                      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                      onPressed: () =>
                          ref.read(playerProvider.notifier).togglePlayPause(),
                      icon: Icon(
                        player.isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_filled_rounded,
                        size: 32,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                      onPressed: () => ref.read(playerProvider.notifier).next(),
                      icon: const Icon(Icons.skip_next_rounded,
                          size: 22, color: Colors.white),
                    ),
                    IconButton(
                      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                      onPressed: () => ref.read(playerProvider.notifier).cycleRepeat(),
                      icon: Icon(
                        player.repeatMode == ElysiumRepeatMode.one
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                        size: 18,
                        color: player.repeatMode != ElysiumRepeatMode.off
                            ? cs.primary
                            : Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    SizedBox(
                      width: 42,
                      child: Text(
                        _fmt(player.position),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 9,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.5,
                          thumbShape:
                              const RoundSliderThumbShape(enabledThumbRadius: 5),
                          overlayShape:
                              const RoundSliderOverlayShape(overlayRadius: 14),
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: progress,
                          onChanged: player.duration.inMilliseconds <= 0
                              ? null
                              : (v) {
                                  final target = Duration(
                                    milliseconds: (v * player.duration.inMilliseconds)
                                        .toInt(),
                                  );
                                  ref.read(playerProvider.notifier).seekTo(target);
                                },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 42,
                      child: Text(
                        _fmt(player.duration),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: 208,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                  onPressed: () => context.go('/remote'),
                  icon: Icon(Icons.cast_rounded,
                      size: 18, color: Colors.white.withValues(alpha: 0.7)),
                ),
                IconButton(
                  visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                  onPressed: () => context.push('/player'),
                  icon: Icon(Icons.open_in_full_rounded,
                      size: 18, color: Colors.white.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
        ],
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
    final progress = player.duration.inMilliseconds > 0
        ? (player.position.inMilliseconds / player.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return Semantics(
      button: true,
      label: 'Now playing ${track.title} by ${track.artist}',
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          final vx = details.velocity.pixelsPerSecond.dx;
          if (vx > 280) {
            ref.read(playerProvider.notifier).previous();
          } else if (vx < -280) {
            ref.read(playerProvider.notifier).next();
          }
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(FireballTokens.miniPlayerRadius),
            onTap: () => context.push('/player'),
            onLongPress: () => showMiniPlayerOverflowMenu(
              context: context,
              track: track,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(FireballTokens.miniPlayerRadius),
              child: AnimatedContainer(
            duration: FireballTokens.motionFast,
            curve: FireballTokens.motionCurve,
            height: isTablet ? 62 : 58,
            decoration: BoxDecoration(
              color: const Color(0xFF181818),
              borderRadius: BorderRadius.circular(FireballTokens.miniPlayerRadius),
              border: Border.all(
                color: player.isPlaying
                    ? cs.primary.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.08),
                width: 0.5,
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
                      bottomLeft: Radius.circular(FireballTokens.miniPlayerRadius),
                      bottomRight: Radius.circular(FireballTokens.miniPlayerRadius),
                    ),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Row(
                    children: [
                      // Artwork with playing indicator overlay
                      _ArtworkTile(
                          track: track,
                          isPlaying: player.isPlaying,
                          cs: cs,
                          size: 40),
                      const SizedBox(width: 10),
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
                                fontSize: isTablet ? 13 : 12,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: isTablet ? 11 : 10,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Tablet: shuffle + repeat controls
                      if (isTablet) ...[
                        IconButton(
                          visualDensity:
                              const VisualDensity(horizontal: -2, vertical: -2),
                          icon: Icon(Icons.shuffle_rounded,
                              size: 18,
                              color: player.shuffled
                                  ? cs.primary
                                  : cs.onSurfaceVariant),
                          onPressed: () =>
                              ref.read(playerProvider.notifier).toggleShuffle(),
                        ),
                        IconButton(
                          visualDensity:
                              const VisualDensity(horizontal: -2, vertical: -2),
                          icon: Icon(
                            player.repeatMode == ElysiumRepeatMode.one
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                            size: 18,
                            color: player.repeatMode != ElysiumRepeatMode.off
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                          onPressed: () =>
                              ref.read(playerProvider.notifier).cycleRepeat(),
                        ),
                      ],
                      // Play / Pause
                      IconButton(
                        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                        icon: Icon(
                          player.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 24,
                          color: cs.onSurface,
                        ),
                        onPressed: () =>
                            ref.read(playerProvider.notifier).togglePlayPause(),
                      ),
                      IconButton(
                        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                        icon: Icon(Icons.skip_next_rounded,
                            size: 22, color: cs.onSurfaceVariant),
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
        ),
      ),
    );
  }
}

// ── Icon-only rail (collapsed iPad sidebar ~70px) ────────────────────────────
class _NarrowRailMiniPlayer extends StatelessWidget {
  const _NarrowRailMiniPlayer({required this.player, required this.track});
  final PlayerState player;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final ref = ProviderScope.containerOf(context);
    final cs = Theme.of(context).colorScheme;
    final progress = player.duration.inMilliseconds > 0
        ? (player.position.inMilliseconds / player.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return Tooltip(
      message: '${track.title} — tap for full player',
      child: Semantics(
        label: 'Now playing: ${track.title}',
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => context.push('/player'),
            onLongPress: () => showMiniPlayerOverflowMenu(
              context: context,
              track: track,
            ),
            child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: FireballTokens.blackElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: _ArtworkTile(
                        track: track,
                        isPlaying: player.isPlaying,
                        cs: cs,
                        size: 42,
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 34,
                      ),
                      icon: Icon(
                        player.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 24,
                        color: Colors.white,
                      ),
                      onPressed: () =>
                          ref.read(playerProvider.notifier).togglePlayPause(),
                    ),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      color: Colors.white.withValues(alpha: 0.82),
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
    final progress = player.duration.inMilliseconds > 0
        ? (player.position.inMilliseconds / player.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/player'),
        onLongPress: () => showMiniPlayerOverflowMenu(
          context: context,
          track: track,
        ),
        child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: FireballTokens.blackElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Row(
                    children: [
                      _ArtworkTile(
                          track: track,
                          isPlaying: player.isPlaying,
                          cs: cs,
                          size: 38),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 30, minHeight: 30),
                        icon: Icon(
                          player.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 22,
                          color: cs.onSurface,
                        ),
                        onPressed: () =>
                            ref.read(playerProvider.notifier).togglePlayPause(),
                      ),
                    ],
                  ),
                ),
                // Thin progress line
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: Colors.white.withValues(alpha: 0.82),
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
              duration: Duration(
                  milliseconds: FireballTokens.motionBase.inMilliseconds + (i * 90)),
              vsync: this,
            ));
    _animations = _controllers
        .map((c) => Tween<double>(begin: 0.3, end: 1.0).animate(
              CurvedAnimation(parent: c, curve: FireballTokens.motionCurve),
            ))
        .toList();

    for (int i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 90), () {
        if (mounted) {
          _controllers[i].repeat(reverse: true);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
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
