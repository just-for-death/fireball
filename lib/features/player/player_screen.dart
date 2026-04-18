import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/api/fireball_api.dart';
import '../../core/models/models.dart';
import '../../core/models/track.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/empty_state.dart';
import '../../core/widgets/fireball_logo.dart';
import '../../core/widgets/track_options_sheet.dart';
import '../../core/store/providers.dart';

enum _PlayerTab { cover, lyrics, queue }

String? _invidiousWatchUrl(FireballSettings s, Track? t) {
  final vid = t?.videoId;
  if (vid == null || vid.isEmpty || s.invidiousInstance.isEmpty) return null;
  final base = s.invidiousInstance.replaceAll(RegExp(r'/+$'), '');
  return '$base/watch?v=${Uri.encodeComponent(vid)}';
}

String _lrclibLyricsBlobDynamic(dynamic r) {
  if (r == null) return '';
  final synced = r['syncedLyrics'] as String?;
  if (synced != null && synced.trim().isNotEmpty) return synced;
  final plain = r['plainLyrics'] as String?;
  if (plain != null && plain.trim().isNotEmpty) return plain;
  return '';
}

/// Higher = more Latin + Devanagari (English / Hindi); lower = e.g. Urdu/Arabic script.
double _englishHindiLyricsScore(String text) {
  if (text.trim().isEmpty) return 0;
  final sample = text.length > 900 ? text.substring(0, 900) : text;
  var latin = 0, deva = 0, arabic = 0, total = 0;
  for (final c in sample.runes) {
    if (c == 0x20 || c == 0x0A || c == 0x0D) continue;
    total++;
    if ((c >= 0x0041 && c <= 0x024F) || (c >= 0x1E00 && c <= 0x1EFF)) {
      latin++;
    } else if (c >= 0x0900 && c <= 0x097F) {
      deva++;
    } else if ((c >= 0x0600 && c <= 0x06FF) ||
        (c >= 0x0750 && c <= 0x077F) ||
        (c >= 0xFB50 && c <= 0xFDFF)) {
      arabic++;
    }
  }
  if (total == 0) return 0;
  final enHi = (latin + deva) / total;
  final ar = arabic / total;
  return (enHi - ar * 0.85).clamp(0.0, 1.0);
}

bool _isArabicScriptDominant(String text) {
  final sample = text.length > 500 ? text.substring(0, 500) : text;
  var arabic = 0, letters = 0;
  for (final c in sample.runes) {
    if (c == 0x20 || c == 0x0A) continue;
    if (c > 0x20) letters++;
    if ((c >= 0x0600 && c <= 0x06FF) ||
        (c >= 0x0750 && c <= 0x077F) ||
        (c >= 0xFB50 && c <= 0xFDFF)) {
      arabic++;
    }
  }
  if (letters < 10) return false;
  return (arabic / letters) > 0.38;
}

bool _skipLrclibGetForEnHi(dynamic data, bool preferEnHi) {
  if (!preferEnHi || data == null) return false;
  final blob = _lrclibLyricsBlobDynamic(data);
  if (blob.isEmpty) return false;
  if (_englishHindiLyricsScore(blob) >= 0.22) return false;
  return _isArabicScriptDominant(blob);
}

int _lrclibStructuralRank(dynamic r, String title, String artist) {
  final tl = title.toLowerCase();
  final al = artist.toLowerCase();
  final ra = (r['artistName'] as String? ?? '').toLowerCase();
  final rt = (r['trackName'] as String? ?? '').toLowerCase();
  if ((ra.contains(al) || al.contains(ra)) &&
      (rt.contains(tl) || tl.contains(rt))) {
    return 100;
  }
  if (rt.contains(tl) || tl.contains(rt)) return 50;
  return 10;
}

double _combinedLrclibSort(
  dynamic r,
  String title,
  String artist,
  bool preferEnHi,
) {
  var score = _lrclibStructuralRank(r, title, artist).toDouble();
  if (preferEnHi) {
    score += _englishHindiLyricsScore(_lrclibLyricsBlobDynamic(r)) * 45;
  }
  return score;
}

List<dynamic> _sortedLrclibPool(
  List<dynamic> pool,
  String title,
  String artist,
  bool preferEnHi,
) {
  final list = List<dynamic>.from(pool);
  list.sort((a, b) => _combinedLrclibSort(b, title, artist, preferEnHi)
      .compareTo(_combinedLrclibSort(a, title, artist, preferEnHi)));
  return list;
}

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
    final artworkAnim =
        useAnimationController(duration: const Duration(milliseconds: 300));
    final resolvedArtwork = useState<String?>(null);

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

    final isTablet = MediaQuery.sizeOf(context).width >= 600;
    useEffect(() {
      if (isTablet && tab.value == _PlayerTab.cover) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (tab.value == _PlayerTab.cover) tab.value = _PlayerTab.lyrics;
        });
      }
      return null;
    }, [isTablet, tab.value]);

    useEffect(() {
      resolvedArtwork.value = null;
      final t = track;
      if (t == null) return null;
      if (t.artwork != null && t.artwork!.isNotEmpty) return null;
      var cancelled = false;
      Future(() async {
        try {
          final url = await api.itunesArtworkForTrack(t.artist, t.title);
          if (!cancelled && url != null) {
            resolvedArtwork.value = url;
          }
        } catch (_) {}
      });
      return () {
        cancelled = true;
      };
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
        settings.lyricsPreferEnglishHindi,
      );
      return null;
    }, [tab.value, track?.effectiveId, settings.lyricsPreferEnglishHindi]);

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
        if (settings.lyricsAutoScroll) {
          _scrollToLyric(
            context,
            lyricsScrollCtrl,
            idx,
            settings.lyricsReducedMotion,
          );
        }
      }
      return null;
    }, [
      player.position,
      lyrics.value.length,
      settings.lyricsAutoScroll,
      settings.lyricsReducedMotion,
    ]);

    final displayArtwork = (track?.artwork?.isNotEmpty ?? false)
        ? track!.artwork
        : resolvedArtwork.value;

    final progress = player.duration.inMilliseconds > 0
        ? player.position.inMilliseconds / player.duration.inMilliseconds
        : 0.0;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          ref.read(playerProvider.notifier).togglePlayPause();
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          ref.read(playerProvider.notifier).next();
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          ref.read(playerProvider.notifier).previous();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: displayArtwork != null
                    ? CachedNetworkImage(
                        imageUrl: displayArtwork,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            Image.asset('assets/icon.png', fit: BoxFit.cover),
                      )
                    : Image.asset('assets/icon.png', fit: BoxFit.cover),
              ),
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                child: Container(color: Colors.black.withValues(alpha: 0.7)),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isTablet = constraints.maxWidth >= 600;
                    if (isTablet) {
                      return _buildTabletLayout(
                        context,
                        ref,
                        track,
                        player,
                        settings,
                        api,
                        displayArtwork,
                        progress,
                        tab,
                        lyrics,
                        lyricsPlain,
                        lyricsLoading,
                        lyricError,
                        lyricsInstrumental,
                        activeLyricIdx,
                        lyricsScrollCtrl,
                        artworkAnim,
                        rotationCtrl,
                        seekBarKey,
                        aiLoading,
                        cs,
                      );
                    }
                    return _buildPhoneLayout(
                      context,
                      ref,
                      track,
                      player,
                      settings,
                      api,
                      displayArtwork,
                      progress,
                      tab,
                      lyrics,
                      lyricsPlain,
                      lyricsLoading,
                      lyricError,
                      lyricsInstrumental,
                      activeLyricIdx,
                      lyricsScrollCtrl,
                      artworkAnim,
                      rotationCtrl,
                      seekBarKey,
                      aiLoading,
                      cs,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Shared header row ──────────────────────────────────────────────────────
  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    Track? track,
    PlayerState player,
    ValueNotifier<bool> aiLoading,
    FireballSettings settings,
    FireballApi api,
    ColorScheme cs,
  ) {
    String? sleepHint;
    final end = player.sleepTimerEnd;
    if (end != null) {
      final left = end.difference(DateTime.now());
      if (!left.isNegative) {
        final m = left.inMinutes;
        final s = left.inSeconds % 60;
        sleepHint = 'Sleep in ${m}m ${s}s';
      }
    } else if (player.sleepAfterCurrentTrack) {
      sleepHint = 'Sleep after track';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                size: 32, color: Colors.white),
            onPressed: () {
              if (context.canPop()) context.pop();
            },
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track?.album ?? 'Now Playing',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                if (sleepHint != null)
                  Text(
                    sleepHint,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.primary.withValues(alpha: 0.85),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded,
                size: 26, color: Colors.white60),
            color: const Color(0xFF1E1E1E),
            onSelected: (v) async {
              final n = ref.read(playerProvider.notifier);
              switch (v) {
                case 's15':
                  n.setSleepTimerMinutes(15);
                case 's30':
                  n.setSleepTimerMinutes(30);
                case 's45':
                  n.setSleepTimerMinutes(45);
                case 's60':
                  n.setSleepTimerMinutes(60);
                case 'send':
                  n.setSleepAfterCurrentTrack(true);
                case 'sclear':
                  n.clearSleepTimer();
                case 'share':
                  if (track != null) {
                    await Share.share('${track.title} — ${track.artist}',
                        subject: track.title);
                  }
                case 'open':
                  final u = _invidiousWatchUrl(settings, track);
                  if (u != null) {
                    await launchUrl(Uri.parse(u),
                        mode: LaunchMode.externalApplication);
                  }
                case 'lyricsScroll':
                  final cur = ref.read(settingsProvider).lyricsAutoScroll;
                  await ref.read(localStoreProvider.notifier).updateSettings({
                    'lyricsAutoScroll': !cur,
                  });
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  'SLEEP TIMER',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
              const PopupMenuItem(value: 's15', child: Text('15 minutes')),
              const PopupMenuItem(value: 's30', child: Text('30 minutes')),
              const PopupMenuItem(value: 's45', child: Text('45 minutes')),
              const PopupMenuItem(value: 's60', child: Text('60 minutes')),
              const PopupMenuItem(
                  value: 'send', child: Text('End of current track')),
              const PopupMenuItem(value: 'sclear', child: Text('Clear timer')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'share', child: Text('Share track')),
              if (_invidiousWatchUrl(settings, track) != null)
                const PopupMenuItem(
                    value: 'open', child: Text('Open in Invidious')),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'lyricsScroll',
                child: Row(
                  children: [
                    Icon(
                      settings.lyricsAutoScroll
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 20,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    const Text('Auto-scroll lyrics'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: Icon(
              aiLoading.value
                  ? Icons.hourglass_top_rounded
                  : Icons.auto_awesome_rounded,
              size: 22,
              color: aiLoading.value ? cs.primary : Colors.white60,
            ),
            onPressed:
                aiLoading.value || track == null || !settings.ollamaEnabled
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
    BuildContext context,
    WidgetRef ref,
    Track? track,
    PlayerState player,
    ColorScheme cs,
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
                GestureDetector(
                  onTap: track == null
                      ? null
                      : () => context.push(
                            '/artist?name=${Uri.encodeComponent(track.artist)}',
                          ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          track?.artist ?? 'Unknown Artist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: track != null
                                ? cs.primary.withValues(alpha: 0.85)
                                : Colors.white60,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            decoration: track != null
                                ? TextDecoration.underline
                                : TextDecoration.none,
                            decorationColor: cs.primary.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      if (track != null) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded,
                            size: 16,
                            color: cs.primary.withValues(alpha: 0.6)),
                      ],
                    ],
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
                  ref
                      .read(playerProvider.notifier)
                      .removeFavorite(track.effectiveId);
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
    BuildContext context,
    WidgetRef ref,
    PlayerState player,
    double progress,
    GlobalKey seekBarKey,
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
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
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
    BuildContext context,
    WidgetRef ref,
    PlayerState player,
    ColorScheme cs,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.shuffle_rounded,
                size: 24,
                color: player.shuffled
                    ? cs.primary
                    : Colors.white.withValues(alpha: 0.5)),
            onPressed: () => ref.read(playerProvider.notifier).toggleShuffle(),
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
            icon: Icon(_repeatIcon(player.repeatMode),
                size: 24,
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
    ValueNotifier<_PlayerTab> tab, {
    List<_PlayerTab> tabs = _PlayerTab.values,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: tabs
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
    BuildContext context,
    WidgetRef ref,
    Track? track,
    PlayerState player,
    FireballSettings settings,
    FireballApi api,
    String? artworkUrl,
    double progress,
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
        _buildHeader(context, ref, track, player, aiLoading, settings, api, cs),
        _buildTabPills(tab),
        const SizedBox(height: 8),
        Expanded(
          child: _buildTabContent(
            context,
            ref,
            tab.value,
            player,
            artworkUrl,
            lyrics,
            lyricsPlain,
            lyricsLoading,
            lyricError,
            lyricsInstrumental,
            activeLyricIdx,
            lyricsScrollCtrl,
            artworkAnim,
            rotationCtrl,
            cs,
            lyricsColumnMaxWidth: null,
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
    BuildContext context,
    WidgetRef ref,
    Track? track,
    PlayerState player,
    FireballSettings settings,
    FireballApi api,
    String? artworkUrl,
    double progress,
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
                _buildHeader(
                    context, ref, track, player, aiLoading, settings, api, cs),
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
                                  child: FireballPlayerArtwork(
                                    networkUrl: artworkUrl,
                                    fit: BoxFit.cover,
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
                              border:
                                  Border.all(color: Colors.white24, width: 1),
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
              _buildTabPills(tab, tabs: const [_PlayerTab.lyrics, _PlayerTab.queue]),
              const SizedBox(height: 8),
              Expanded(
                child: _buildTabContent(
                  context,
                  ref,
                  tab.value,
                  player,
                  artworkUrl,
                  lyrics,
                  lyricsPlain,
                  lyricsLoading,
                  lyricError,
                  lyricsInstrumental,
                  activeLyricIdx,
                  lyricsScrollCtrl,
                  artworkAnim,
                  rotationCtrl,
                  cs,
                  lyricsColumnMaxWidth: 560,
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
    String? artworkUrl,
    ValueNotifier<List<({double time, String text})>> lyrics,
    ValueNotifier<List<String>> lyricsPlain,
    ValueNotifier<bool> lyricsLoading,
    ValueNotifier<String> lyricError,
    ValueNotifier<bool> lyricsInstrumental,
    ValueNotifier<int> activeLyricIdx,
    ScrollController scrollCtrl,
    AnimationController artworkAnim,
    AnimationController rotationCtrl,
    ColorScheme cs, {
    double? lyricsColumnMaxWidth,
  }) {
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
                          parent: artworkAnim, curve: Curves.elasticOut),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1A1A1A),
                          border: Border.all(color: Colors.white10, width: 2),
                        ),
                        child: ClipOval(
                          child: FireballPlayerArtwork(
                            networkUrl: artworkUrl,
                            fit: BoxFit.cover,
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
                      border: Border.all(color: Colors.white24, width: 1),
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.music_note_rounded,
                      size: 40, color: Colors.white24),
                  const SizedBox(height: 12),
                  Text(
                    lyricError.value,
                    textAlign: TextAlign.center,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 14),
                  ),
                ],
              ),
            ),
          );
        }
        if (lyrics.value.isNotEmpty) {
          final list = ListView.builder(
            controller: scrollCtrl,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            itemCount: lyrics.value.length,
            itemBuilder: (context, i) {
              final isActive = i == activeLyricIdx.value;
              final delta = (i - activeLyricIdx.value).abs();
              final lyric = lyrics.value[i];
              final seekPos =
                  Duration(milliseconds: (lyric.time * 1000).toInt());
              return GestureDetector(
                onTap: () {
                  if (!kIsWeb &&
                      (defaultTargetPlatform == TargetPlatform.iOS ||
                          defaultTargetPlatform == TargetPlatform.android)) {
                    HapticFeedback.lightImpact();
                  }
                  ref.read(playerProvider.notifier).seekTo(seekPos);
                  activeLyricIdx.value = i;
                  _scrollToLyric(
                    context,
                    scrollCtrl,
                    i,
                    ref.read(settingsProvider).lyricsReducedMotion,
                  );
                },
                child: Semantics(
                  button: true,
                  label: 'Seek to ${lyric.text}, ${_fmt(seekPos)}',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      lyric.text,
                      style: TextStyle(
                        color: Colors.white.withValues(
                            alpha: isActive
                                ? 1.0
                                : (0.6 - delta * 0.1).clamp(0.1, 0.6)),
                        fontSize: isActive ? 22 : 18,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
          if (lyricsColumnMaxWidth != null) {
            final w = lyricsColumnMaxWidth;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: w),
                child: list,
              ),
            );
          }
          return list;
        }

        if (lyricsPlain.value.isNotEmpty) {
          final plain = SingleChildScrollView(
            controller: scrollCtrl,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                    padding: const EdgeInsets.symmetric(vertical: 5),
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
          if (lyricsColumnMaxWidth != null) {
            final w = lyricsColumnMaxWidth;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: w),
                child: plain,
              ),
            );
          }
          return plain;
        }

        return const Center(
          child:
              Text('No lyrics found', style: TextStyle(color: Colors.white38)),
        );

      case _PlayerTab.queue:
        if (player.queue.isEmpty) {
          return const FireballEmptyState(
            onDarkGlass: true,
            title: 'Queue is empty',
            subtitle: 'Add tracks from search or home.',
            icon: Icons.queue_music_rounded,
          );
        }
        return ReorderableListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: player.queue.length,
          onReorder: (oldIndex, newIndex) {
            ref.read(playerProvider.notifier).reorderQueue(oldIndex, newIndex);
          },
          itemBuilder: (context, i) {
            final t = player.queue[i];
            final isActive = i == player.currentIndex;
            return ListTile(
              key: ValueKey('q-${t.effectiveId}-$i'),
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
              subtitle: Text(
                t.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isActive)
                    Icon(Icons.equalizer_rounded, color: cs.primary, size: 20),
                  IconButton(
                    icon: Icon(
                      Icons.remove_circle_outline_rounded,
                      color: Colors.white.withValues(alpha: 0.35),
                      size: 22,
                    ),
                    onPressed: () =>
                        ref.read(playerProvider.notifier).removeFromQueueAt(i),
                    tooltip: 'Remove from queue',
                  ),
                ],
              ),
              onTap: () => ref.read(playerProvider.notifier).playIndex(i),
              onLongPress: () => showTrackOptions(context, ref, t),
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
    bool preferEnglishHindi,
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
            .lrclibGet(artist, title,
                album: track.album, duration: track.duration)
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
      if (lrclibData != null &&
          !_skipLrclibGetForEnHi(lrclibData, preferEnglishHindi)) {
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
            for (final candidate in _sortedLrclibPool(
              pool,
              title,
              artist,
              preferEnglishHindi,
            )) {
              if (_applyLrclibResult(candidate, lyrics, lyricsPlain)) {
                return;
              }
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
            for (final candidate in _sortedLrclibPool(
              results,
              title,
              artist,
              preferEnglishHindi,
            )) {
              if (_applyLrclibResult(candidate, lyrics, lyricsPlain)) {
                return;
              }
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

  Map<String, dynamic> _bestNetEaseMatch(List<dynamic> songs, String artist) {
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

  void _scrollToLyric(
    BuildContext context,
    ScrollController ctrl,
    int idx,
    bool lyricsReducedMotion,
  ) {
    if (!ctrl.hasClients) return;
    // Estimated item height: font 18×1.4 + 16px vertical padding ≈ 41px for
    // inactive lines; active lines are taller (font 22×1.4+16 ≈ 47px). Use 42
    // as a practical average — close enough for centering without GlobalKey overhead.
    const itemH = 42.0;
    try {
      final viewportH = ctrl.position.viewportDimension;
      final raw = idx * itemH - (viewportH / 2) + itemH / 2;
      final offset = raw.clamp(0.0, ctrl.position.maxScrollExtent);
      final instant =
          lyricsReducedMotion || MediaQuery.of(context).disableAnimations;
      if (instant) {
        ctrl.jumpTo(offset);
      } else {
        ctrl.animateTo(
          offset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    } catch (_) {
      // ScrollPosition may not be laid out yet on first call — safe to ignore.
    }
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                selected ? Colors.white : Colors.white.withValues(alpha: 0.5),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
