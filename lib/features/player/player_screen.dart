import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/api/fireball_api.dart';
import '../../core/models/models.dart';
import '../../core/models/track.dart';
import '../../core/store/providers.dart';

enum _PlayerTab { cover, lyrics, queue }

class PlayerScreen extends HookConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final settings = ref.watch(settingsProvider);
    const api = FireballApi();
    final cs = Theme.of(context).colorScheme;

    final track = player.currentTrack;
    final tab = useState(_PlayerTab.cover);
    final lyrics = useState<List<({double time, String text})>>([]);
    final lyricsPlain = useState<List<String>>([]);
    final lyricsLoading = useState(false);
    final lyricError = useState('');
    final lyricsInstrumental = useState(false);
    final activeLyricIdx = useState(0);
    final aiLoading = useState(false);
    final lyricsScrollCtrl = useScrollController();
    final seekBarKey = useMemoized(() => GlobalKey(), const []);
    final artworkAnim = useAnimationController(
        duration: const Duration(milliseconds: 300));

    useEffect(() {
      artworkAnim
        ..reset()
        ..forward();
      lyrics.value = [];
      lyricsPlain.value = [];
      lyricError.value = '';
      lyricsInstrumental.value = false;
      activeLyricIdx.value = 0;
      return null;
    }, [track?.effectiveId]);

    final rotationCtrl =
        useAnimationController(duration: const Duration(seconds: 20));

    useEffect(() {
      if (player.isPlaying) {
        rotationCtrl.repeat();
      } else {
        rotationCtrl.stop();
      }
      return null;
    }, [player.isPlaying]);

    useEffect(() {
      if (tab.value != _PlayerTab.lyrics || track == null) return null;
      if (lyrics.value.isNotEmpty || lyricsPlain.value.isNotEmpty) return null;
      lyricsLoading.value = true;
      lyricError.value = '';
      // Capture trackId so async result can be discarded if track changed
      final fetchId = track.effectiveId;
      // Pass a live getter so stale() compares against the CURRENTLY playing
      // track, not the captured `track` object (which always equals fetchId).
      _doFetchLyrics(
        api,
        track,
        fetchId,
        () => ref.read(playerProvider).currentTrack?.effectiveId ?? '',
        lyrics,
        lyricsPlain,
        lyricError,
        lyricsLoading,
        lyricsInstrumental,
      );
      return null;
    }, [tab.value, track?.effectiveId]);

    useEffect(() {
      // Recalculate active lyric index when lyrics first load or position changes
      if (lyrics.value.isEmpty) return null;
      final currentSec = player.position.inMilliseconds / 1000;
      int idx = 0;
      for (int i = lyrics.value.length - 1; i >= 0; i--) {
        if (lyrics.value[i].time <= currentSec) {
          idx = i;
          break;
        }
      }
      if (idx != activeLyricIdx.value) {
        activeLyricIdx.value = idx;
        _scrollToLyric(lyricsScrollCtrl, idx);
      }
      return null;
    }, [player.position, lyrics.value.length]);

    final artworkUrl = track?.artwork ??
        'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=600';

    final progress = player.duration.inMilliseconds > 0
        ? player.position.inMilliseconds / player.duration.inMilliseconds
        : 0.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (track?.artwork != null)
            CachedNetworkImage(
              imageUrl: track!.artwork!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child:
                Container(color: Colors.black.withValues(alpha: 0.7)),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isTablet = constraints.maxWidth >= 600;
                if (isTablet) {
                  return _buildTabletLayout(
                    context, ref, track, player, settings, api,
                    artworkUrl, progress, tab, lyrics, lyricsPlain,
                    lyricsLoading, lyricError, lyricsInstrumental, activeLyricIdx,
                    lyricsScrollCtrl, artworkAnim, rotationCtrl,
                    seekBarKey, aiLoading, cs,
                  );
                }
                return _buildPhoneLayout(
                  context, ref, track, player, settings, api,
                  artworkUrl, progress, tab, lyrics, lyricsPlain,
                  lyricsLoading, lyricError, lyricsInstrumental, activeLyricIdx,
                  lyricsScrollCtrl, artworkAnim, rotationCtrl,
                  seekBarKey, aiLoading, cs,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared header row ──────────────────────────────────────────────────────
  Widget _buildHeader(
    BuildContext context, WidgetRef ref,
    Track? track,
    ValueNotifier<bool> aiLoading,
    FireballSettings settings,
    FireballApi api,
    ColorScheme cs,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                size: 32, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              track?.album ?? 'Now Playing',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              aiLoading.value
                  ? Icons.hourglass_top_rounded
                  : Icons.auto_awesome_rounded,
              size: 22,
              color: aiLoading.value ? cs.primary : Colors.white60,
            ),
            onPressed: aiLoading.value || track == null || !settings.ollamaEnabled
                ? null
                : () async {
                    aiLoading.value = true;
                    try {
                      final aiTrack = await api.generateAIQueue(
                        track,
                        ollamaUrl: settings.ollamaUrl,
                        ollamaModel: settings.ollamaModel,
                      );
                      if (aiTrack != null) {
                        ref.read(playerProvider.notifier).playNext(aiTrack);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('AI queue failed: $e'),
                          duration: const Duration(seconds: 3),
                        ));
                      }
                    } finally {
                      aiLoading.value = false;
                    }
                  },
          ),
        ],
      ),
    );
  }

  // ── Shared track info + favorite ────────────────────────────────────────────
  Widget _buildTrackInfo(
    BuildContext context, WidgetRef ref,
    Track? track, PlayerState player, ColorScheme cs,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track?.title ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  track?.artist ?? 'Unknown Artist',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (track != null)
            IconButton(
              icon: Icon(
                player.isFavorite(track.effectiveId)
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 28,
                color: player.isFavorite(track.effectiveId)
                    ? Colors.redAccent
                    : Colors.white60,
              ),
              onPressed: () async {
                final fav = player.isFavorite(track.effectiveId);
                if (fav) {
                  await ref
                      .read(localStoreProvider.notifier)
                      .deleteFavorite(track.effectiveId);
                  ref.read(playerProvider.notifier).removeFavorite(track.effectiveId);
                } else {
                  await ref
                      .read(localStoreProvider.notifier)
                      .addFavorite(track);
                  ref.read(playerProvider.notifier).addFavorite(track);
                }
              },
            ),
        ],
      ),
    );
  }

  // ── Shared progress bar ──────────────────────────────────────────────────────
  Widget _buildProgressBar(
    BuildContext context, WidgetRef ref,
    PlayerState player, double progress, GlobalKey seekBarKey,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          SizedBox(
            key: seekBarKey,
            height: 30,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                thumbColor: Colors.white,
                trackShape: const RoundedRectSliderTrackShape(),
              ),
              child: Slider(
                value: progress.clamp(0.0, 1.0),
                onChanged: player.duration.inMilliseconds <= 0
                    ? null
                    : (v) {
                        final target = Duration(
                            milliseconds:
                                (v * player.duration.inMilliseconds).toInt());
                        ref.read(playerProvider.notifier).seekTo(target);
                      },
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(player.position),
                  style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              Text(_fmt(player.duration),
                  style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Shared playback controls ─────────────────────────────────────────────────
  Widget _buildControls(
    BuildContext context, WidgetRef ref,
    PlayerState player, ColorScheme cs,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.shuffle_rounded, size: 24,
                color: player.shuffled
                    ? cs.primary
                    : Colors.white.withValues(alpha: 0.5)),
            onPressed: () =>
                ref.read(playerProvider.notifier).toggleShuffle(),
          ),
          IconButton(
            icon: const Icon(Icons.skip_previous_rounded,
                size: 44, color: Colors.white),
            onPressed: () => ref.read(playerProvider.notifier).previous(),
          ),
          GestureDetector(
            onTap: () => ref.read(playerProvider.notifier).togglePlayPause(),
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
              child: Icon(
                player.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 38,
                color: Colors.black,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.skip_next_rounded,
                size: 44, color: Colors.white),
            onPressed: () => ref.read(playerProvider.notifier).next(),
          ),
          IconButton(
            icon: Icon(_repeatIcon(player.repeatMode), size: 24,
                color: player.repeatMode != ElysiumRepeatMode.off
                    ? cs.primary
                    : Colors.white.withValues(alpha: 0.5)),
            onPressed: () => ref.read(playerProvider.notifier).cycleRepeat(),
          ),
        ],
      ),
    );
  }

  // ── Tab pills row ────────────────────────────────────────────────────────────
  Widget _buildTabPills(
    ValueNotifier<_PlayerTab> tab,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: _PlayerTab.values
            .map((t) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _PlayerTabPill(
                    label: _tabLabel(t),
                    selected: tab.value == t,
                    onTap: () => tab.value = t,
                  ),
                ))
            .toList(),
      ),
    );
  }

  // ── Phone layout (single column) ─────────────────────────────────────────────
  Widget _buildPhoneLayout(
    BuildContext context, WidgetRef ref,
    Track? track, PlayerState player,
    FireballSettings settings, FireballApi api,
    String artworkUrl, double progress,
    ValueNotifier<_PlayerTab> tab,
    ValueNotifier<List<({double time, String text})>> lyrics,
    ValueNotifier<List<String>> lyricsPlain,
    ValueNotifier<bool> lyricsLoading,
    ValueNotifier<String> lyricError,
    ValueNotifier<bool> lyricsInstrumental,
    ValueNotifier<int> activeLyricIdx,
    ScrollController lyricsScrollCtrl,
    AnimationController artworkAnim,
    AnimationController rotationCtrl,
    GlobalKey seekBarKey,
    ValueNotifier<bool> aiLoading,
    ColorScheme cs,
  ) {
    return Column(
      children: [
        _buildHeader(context, ref, track, aiLoading, settings, api, cs),
        _buildTabPills(tab),
        const SizedBox(height: 8),
        Expanded(
          child: _buildTabContent(
            context, ref, tab.value, player, artworkUrl,
            lyrics, lyricsPlain, lyricsLoading, lyricError, lyricsInstrumental,
            activeLyricIdx, lyricsScrollCtrl, artworkAnim, rotationCtrl, cs,
          ),
        ),
        _buildTrackInfo(context, ref, track, player, cs),
        _buildProgressBar(context, ref, player, progress, seekBarKey),
        _buildControls(context, ref, player, cs),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── iPad / tablet layout (two-pane) ──────────────────────────────────────────
  Widget _buildTabletLayout(
    BuildContext context, WidgetRef ref,
    Track? track, PlayerState player,
    FireballSettings settings, FireballApi api,
    String artworkUrl, double progress,
    ValueNotifier<_PlayerTab> tab,
    ValueNotifier<List<({double time, String text})>> lyrics,
    ValueNotifier<List<String>> lyricsPlain,
    ValueNotifier<bool> lyricsLoading,
    ValueNotifier<String> lyricError,
    ValueNotifier<bool> lyricsInstrumental,
    ValueNotifier<int> activeLyricIdx,
    ScrollController lyricsScrollCtrl,
    AnimationController artworkAnim,
    AnimationController rotationCtrl,
    GlobalKey seekBarKey,
    ValueNotifier<bool> aiLoading,
    ColorScheme cs,
  ) {
    return Row(
      children: [
        // ── Left pane: artwork + track meta ──────────────────────────────────
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Back + AI header for left pane on tablet
                _buildHeader(context, ref, track, aiLoading, settings, api, cs),
                const SizedBox(height: 16),
                // Rotating album art
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 40,
                                  spreadRadius: 8,
                                ),
                              ],
                            ),
                          ),
                          RotationTransition(
                            turns: rotationCtrl,
                            child: ScaleTransition(
                              scale: CurvedAnimation(
                                  parent: artworkAnim,
                                  curve: Curves.elasticOut),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF1A1A1A),
                                  border: Border.all(
                                      color: Colors.white10, width: 2),
                                ),
                                child: ClipOval(
                                  child: CachedNetworkImage(
                                    imageUrl: artworkUrl,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      color: cs.surfaceContainerHighest,
                                      child: Icon(Icons.music_note_rounded,
                                          size: 80,
                                          color: cs.primary
                                              .withValues(alpha: 0.4)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white24, width: 1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Track info + favorite
                _buildTrackInfo(context, ref, track, player, cs),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),

        // Vertical divider
        VerticalDivider(
          width: 1,
          thickness: 0.5,
          color: Colors.white.withValues(alpha: 0.10),
        ),

        // ── Right pane: tabs + controls ───────────────────────────────────────
        Expanded(
          flex: 6,
          child: Column(
            children: [
              _buildTabPills(tab),
              const SizedBox(height: 8),
              Expanded(
                child: _buildTabContent(
                  context, ref, tab.value, player, artworkUrl,
                  lyrics, lyricsPlain, lyricsLoading, lyricError, lyricsInstrumental,
                  activeLyricIdx, lyricsScrollCtrl, artworkAnim, rotationCtrl,
                  cs,
                ),
              ),
              _buildProgressBar(context, ref, player, progress, seekBarKey),
              _buildControls(context, ref, player, cs),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabContent(
    BuildContext context,
    WidgetRef ref,
    _PlayerTab tab,
    PlayerState player,
    String artworkUrl,
    ValueNotifier<List<({double time, String text})>> lyrics,
    ValueNotifier<List<String>> lyricsPlain,
    ValueNotifier<bool> lyricsLoading,
    ValueNotifier<String> lyricError,
    ValueNotifier<bool> lyricsInstrumental,
    ValueNotifier<int> activeLyricIdx,
    ScrollController scrollCtrl,
    AnimationController artworkAnim,
    AnimationController rotationCtrl,
    ColorScheme cs,
  ) {
    switch (tab) {
      case _PlayerTab.cover:
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 30,
                          spreadRadius: 5,
                        )
                      ],
                    ),
                  ),
                  RotationTransition(
                    turns: rotationCtrl,
                    child: ScaleTransition(
                      scale: CurvedAnimation(
                          parent: artworkAnim,
                          curve: Curves.elasticOut),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1A1A1A),
                          border: Border.all(
                              color: Colors.white10, width: 2),
                        ),
                        child: ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: artworkUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              color: cs.surfaceContainerHighest,
                              child: Icon(Icons.music_note_rounded,
                                  size: 80,
                                  color: cs.primary
                                      .withValues(alpha: 0.4)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white24, width: 1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

      case _PlayerTab.lyrics:
        if (lyricsLoading.value) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.white60));
        }
        if (lyricsInstrumental.value) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.piano_rounded,
                    size: 48, color: cs.primary.withValues(alpha: 0.55)),
                const SizedBox(height: 14),
                const Text('Instrumental',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 17,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text('No lyrics — this is an instrumental track',
                    style: TextStyle(color: Colors.white38, fontSize: 13)),
              ],
            ),
          );
        }
        if (lyricError.value.isNotEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.music_note_rounded,
                    size: 40, color: Colors.white24),
                const SizedBox(height: 12),
                Text(lyricError.value,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 14)),
              ],
            ),
          );
        }
        if (lyrics.value.isNotEmpty) {
          return ListView.builder(
            controller: scrollCtrl,
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 40),
            itemCount: lyrics.value.length,
            itemBuilder: (context, i) {
              final isActive = i == activeLyricIdx.value;
              final delta = (i - activeLyricIdx.value).abs();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  lyrics.value[i].text,
                  style: TextStyle(
                    color: Colors.white.withValues(
                        alpha: isActive
                            ? 1.0
                            : (0.6 - delta * 0.1).clamp(0.1, 0.6)),
                    fontSize: isActive ? 22 : 18,
                    fontWeight: isActive
                        ? FontWeight.w700
                        : FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              );
            },
          );
        }

        if (lyricsPlain.value.isNotEmpty) {
          return SingleChildScrollView(
            controller: scrollCtrl,
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Plain lyrics · no sync',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                ...lyricsPlain.value.map(
                  (line) => Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 5),
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return const Center(
          child: Text('No lyrics found',
              style: TextStyle(color: Colors.white38)),
        );

      case _PlayerTab.queue:
        if (player.queue.isEmpty) {
          return const Center(
            child: Text('Queue is empty',
                style: TextStyle(color: Colors.white38)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: player.queue.length,
          itemBuilder: (context, i) {
            final t = player.queue[i];
            final isActive = i == player.currentIndex;
            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: t.artwork != null
                    ? CachedNetworkImage(
                        imageUrl: t.artwork!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 44,
                          height: 44,
                          color: Colors.white12,
                          child: const Icon(Icons.music_note_rounded,
                              color: Colors.white38, size: 20),
                        ),
                      )
                    : Container(
                        width: 44,
                        height: 44,
                        color: Colors.white12,
                        child: const Icon(Icons.music_note_rounded,
                            color: Colors.white38, size: 20),
                      ),
              ),
              title: Text(
                t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isActive ? cs.primary : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(t.artist,
                  maxLines: 1,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12)),
              trailing: isActive
                  ? Icon(Icons.equalizer_rounded,
                      color: cs.primary, size: 20)
                  : null,
              onTap: () =>
                  ref.read(playerProvider.notifier).playIndex(i),
            );
          },
        );
    }
  }

  String _tabLabel(_PlayerTab t) {
    switch (t) {
      case _PlayerTab.cover:
        return '♫ Cover';
      case _PlayerTab.lyrics:
        return '☰ Lyrics';
      case _PlayerTab.queue:
        return '≡ Queue';
    }
  }

  IconData _repeatIcon(ElysiumRepeatMode mode) {
    switch (mode) {
      case ElysiumRepeatMode.off:
        return Icons.repeat_rounded;
      case ElysiumRepeatMode.all:
        return Icons.repeat_rounded;
      case ElysiumRepeatMode.one:
        return Icons.repeat_one_rounded;
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _doFetchLyrics(
    FireballApi api,
    Track track,
    String fetchId,
    String Function() liveId,
    ValueNotifier<List<({double time, String text})>> lyrics,
    ValueNotifier<List<String>> lyricsPlain,
    ValueNotifier<String> lyricError,
    ValueNotifier<bool> lyricsLoading,
    ValueNotifier<bool> lyricsInstrumental,
  ) async {
    // Returns true when the player has moved on to a different track.
    bool stale() => liveId() != fetchId;

    final artist = track.artist;
    final title = track.title;

    try {
      // ── Phase 1: LRCLIB exact + NetEase search run in parallel ───────────
      // Mirrors elysium-client's Promise.all approach for lower latency.
      final phase1 = await Future.wait([
        api
            .lrclibGet(artist, title, album: track.album, duration: track.duration)
            .then<dynamic>((v) => v)
            .catchError((_) => null),
        api
            .lyricsSearch('$title $artist'.trim())
            .then<dynamic>((v) => v)
            .catchError((_) => null),
      ]);
      if (stale()) return;

      final lrclibData = phase1[0];
      final neteaseSearchData = phase1[1];

      // Instrumental tracks have no lyrics — show a dedicated UI message.
      if (lrclibData?['instrumental'] == true) {
        lyricsInstrumental.value = true;
        return;
      }

      // ── Parse LRCLIB result ─────────────────────────────────────────────
      var lrclibSynced = <({double time, String text})>[];
      var lrclibPlain = <String>[];
      if (lrclibData != null) {
        final syncedStr = lrclibData['syncedLyrics'] as String?;
        if (syncedStr != null && syncedStr.trim().isNotEmpty) {
          lrclibSynced = _parseLRC(syncedStr);
        }
        if (lrclibSynced.isEmpty) {
          final plainStr = lrclibData['plainLyrics'] as String?;
          if (plainStr != null && plainStr.trim().isNotEmpty) {
            lrclibPlain =
                plainStr.split('\n').where((l) => l.trim().isNotEmpty).toList();
          }
        }
      }

      // ── Fetch NetEase lyric for the best search hit ─────────────────────
      var neteaseSynced = <({double time, String text})>[];
      var neteasePlain = <String>[];
      if (neteaseSearchData != null) {
        final songs = neteaseSearchData['result']?['songs'] as List<dynamic>?;
        if (songs != null && songs.isNotEmpty) {
          final best = _bestNetEaseMatch(songs, artist);
          final bestId = best['id'];
          if (bestId != null) {
            try {
              final lyricData = await api.lyricsGet(bestId.toString());
              if (!stale() && lyricData != null) {
                final lrc = lyricData['lrc']?['lyric'] as String? ?? '';
                neteaseSynced = _parseLRC(lrc);
                if (neteaseSynced.isEmpty) {
                  // klyric is NetEase's secondary LRC track (karaoke/alt);
                  // try parsing it as synced, then fall back to plain.
                  final klyric = lyricData['klyric']?['lyric'] as String?;
                  if (klyric != null && klyric.trim().isNotEmpty) {
                    neteaseSynced = _parseLRC(klyric);
                    if (neteaseSynced.isEmpty) {
                      neteasePlain = klyric
                          .split('\n')
                          .where((l) => l.trim().isNotEmpty)
                          .toList();
                    }
                  }
                }
              }
            } catch (_) {}
          }
        }
      }
      if (stale()) return;

      // ── Pick best result: synced preferred, LRCLIB preferred over NetEase ─
      if (lrclibSynced.isNotEmpty) {
        lyrics.value = lrclibSynced;
        return;
      }
      if (neteaseSynced.isNotEmpty) {
        lyrics.value = neteaseSynced;
        return;
      }
      if (lrclibPlain.isNotEmpty) {
        lyricsPlain.value = lrclibPlain;
        return;
      }
      if (neteasePlain.isNotEmpty) {
        lyricsPlain.value = neteasePlain;
        return;
      }

      // ── Phase 2: LRCLIB search fallback (two queries) ────────────────────
      // Try "artist title" then "title" alone — helps when artist romanisation
      // varies (e.g. K-pop, Bollywood).
      for (final q in ['$artist $title', title]) {
        if (stale()) return;
        try {
          final raw = await api.lrclibSearch(q);
          if (stale()) return;
          final results = raw is List<dynamic> ? raw : null;
          if (results != null && results.isNotEmpty) {
            // Prefer entries that have synced lyrics
            final withSync = results
                .where((r) => (r['syncedLyrics'] as String?) != null)
                .toList();
            final pool = withSync.isNotEmpty ? withSync : results;
            final best = _bestLrclibMatch(pool, title, artist);
            if (best != null && _applyLrclibResult(best, lyrics, lyricsPlain)) {
              return;
            }
          }
        } on Exception catch (_) {}
      }

      // Field search as final fallback
      if (!stale()) {
        try {
          final raw = await api.lrclibSearchByFields(title, artist);
          if (stale()) return;
          final results = raw is List<dynamic> ? raw : null;
          if (results != null && results.isNotEmpty) {
            final best = _bestLrclibMatch(results, title, artist);
            if (best != null &&
                _applyLrclibResult(best, lyrics, lyricsPlain)) {
              return;
            }
          }
        } on Exception catch (_) {}
      }

      throw Exception('No lyrics found');
    } catch (e) {
      if (!stale()) lyricError.value = 'No lyrics found';
    } finally {
      if (!stale()) lyricsLoading.value = false;
    }
  }

  bool _applyLrclibResult(
    dynamic data,
    ValueNotifier<List<({double time, String text})>> lyrics,
    ValueNotifier<List<String>> lyricsPlain,
  ) {
    final synced = data?['syncedLyrics'] as String?;
    if (synced != null && synced.trim().isNotEmpty) {
      final parsed = _parseLRC(synced);
      if (parsed.isNotEmpty) {
        lyrics.value = parsed;
        return true;
      }
    }
    final plain = data?['plainLyrics'] as String?;
    if (plain != null && plain.trim().isNotEmpty) {
      lyricsPlain.value =
          plain.split('\n').where((l) => l.trim().isNotEmpty).toList();
      return true;
    }
    return false;
  }

  dynamic _bestLrclibMatch(
      List<dynamic> results, String title, String artist) {
    final tl = title.toLowerCase();
    final al = artist.toLowerCase();
    for (final r in results) {
      final ra = (r['artistName'] as String? ?? '').toLowerCase();
      final rt = (r['trackName'] as String? ?? '').toLowerCase();
      if ((ra.contains(al) || al.contains(ra)) &&
          (rt.contains(tl) || tl.contains(rt))) {
        return r;
      }
    }
    for (final r in results) {
      final rt = (r['trackName'] as String? ?? '').toLowerCase();
      if (rt.contains(tl) || tl.contains(rt)) return r;
    }
    return results.first;
  }

  Map<String, dynamic> _bestNetEaseMatch(
      List<dynamic> songs, String artist) {
    final al = artist.toLowerCase();
    for (final song in songs) {
      final artists = (song['artists'] as List<dynamic>? ?? [])
          .map((a) => (a['name'] as String? ?? '').toLowerCase())
          .toList();
      if (artists.any((a) => a.contains(al) || al.contains(a))) {
        return song as Map<String, dynamic>;
      }
    }
    return songs.first as Map<String, dynamic>;
  }

  List<({double time, String text})> _parseLRC(String lrc) {
    final result = <({double time, String text})>[];
    // Matches all timestamps in a line: [mm:ss.xx] or [mm:ss:xx]
    final tsRe = RegExp(r'\[(\d+):(\d+(?:[.:]\d+)?)\]');
    for (final rawLine in lrc.split('\n')) {
      final line = rawLine.trim();
      // Skip metadata tags like [ar:...] [ti:...] [offset:...]
      if (RegExp(r'^\[[a-zA-Z]+:').hasMatch(line)) continue;
      final matches = tsRe.allMatches(line);
      if (matches.isEmpty) continue;
      // Text is everything after the last timestamp tag
      final lastMatch = matches.last;
      final text = line.substring(lastMatch.end).trim();
      if (text.isEmpty) continue;
      for (final m in matches) {
        try {
          final secStr = m.group(2)!.replaceAll(':', '.');
          final time = int.parse(m.group(1)!) * 60 + double.parse(secStr);
          result.add((time: time, text: text));
        } catch (_) {
          // Skip malformed timestamp
        }
      }
    }
    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  void _scrollToLyric(ScrollController ctrl, int idx) {
    if (!ctrl.hasClients) return;
    // Estimated item height: font 18×1.4 + 16px vertical padding ≈ 41px for
    // inactive lines; active lines are taller (font 22×1.4+16 ≈ 47px). Use 42
    // as a practical average — close enough for centering without GlobalKey overhead.
    const itemH = 42.0;
    final viewportH = ctrl.position.viewportDimension;
    final raw = idx * itemH - (viewportH / 2) + itemH / 2;
    final offset = raw.clamp(0.0, ctrl.position.maxScrollExtent);
    ctrl.animateTo(
      offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }
}

class _PlayerTabPill extends StatelessWidget {
  const _PlayerTabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.5),
            fontWeight:
                selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
