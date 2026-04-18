import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState, Track;

import '../api/fireball_api.dart';
import '../audio/media_session_bridge.dart';
import '../audio/media_session_player.dart';
import '../models/models.dart';
import '../models/sponsor_segment.dart';
import '../models/track.dart';
import '../../remote/remote_server.dart';
import 'local_store.dart';
import 'player_state.dart';

export 'local_store.dart'
    show localStoreProvider, LibraryData, LocalStoreNotifier;
export 'player_state.dart' show PlayerState, ElysiumRepeatMode;

// ── Settings convenience provider ────────────────────────────────────────────
final settingsProvider = Provider<FireballSettings>((ref) {
  return ref.watch(localStoreProvider).settings;
});

/// True while [RemoteScreen] is on the navigation stack (host or control mode),
/// so the shell mini-player does not cover remote UI.
final remoteScreenCoversShellProvider = StateProvider<bool>((ref) => false);

// ── Player Notifier ───────────────────────────────────────────────────────────
final playerProvider =
    StateNotifierProvider<PlayerNotifier, PlayerState>((ref) {
  return PlayerNotifier(ref);
});

class PlayerNotifier extends StateNotifier<PlayerState>
    implements RemotePlayerProxy, MediaSessionPlayer {
  /// Created after the first frame so native `Player()` does not block splash dismissal.
  Player? _player;
  bool _disposed = false;
  final Ref _ref;
  int _playVersion = 0;
  bool _scrobbled = false;
  Timer? _mediaSessionTicker;

  // ── SponsorBlock state (reset per-track) ──────────────────────────────────
  List<SponsorSegment> _sponsorSegments = [];
  final Set<String> _skippedSegmentUuids = {};

  PlayerNotifier(this._ref) : super(const PlayerState()) {
    void schedule() {
      if (_disposed) return;
      final apple = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS);
      if (!apple) {
        _ensurePlayer();
        return;
      }
      // iOS/macOS: create Player one frame after the first paint so we never
      // contend with splash teardown / first raster.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) _ensurePlayer();
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => schedule());
  }

  /// Idempotent; safe to call from any playback path before using [Player].
  void _ensurePlayer() {
    if (_disposed || _player != null) return;
    MediaKit.ensureInitialized();
    _player = Player();
    _listenToPlayer();
    MediaSessionBridge.attachPlayer(this);
  }

  Player get _p {
    _ensurePlayer();
    return _player!;
  }

  void _syncMediaSession() => MediaSessionBridge.sync();

  void _setMediaTicker(bool playing) {
    _mediaSessionTicker?.cancel();
    _mediaSessionTicker = null;
    if (!playing) return;
    _mediaSessionTicker =
        Timer.periodic(const Duration(seconds: 1), (_) => _syncMediaSession());
  }

  FireballApi get _api => const FireballApi();
  FireballSettings get _settings => _ref.read(settingsProvider);

  Player get player => _p;

  @override
  PlayerState get sessionState => state;

  void _listenToPlayer() {
    final pl = _player!;
    pl.stream.playing.listen((playing) {
      state = state.copyWith(isPlaying: playing);
      _setMediaTicker(playing);
      _syncMediaSession();
    });
    pl.stream.position.listen((pos) {
      state = state.copyWith(position: pos);
      _checkScrobble(pos);
      _checkSleepTimer();
      _checkSponsorBlock(pos);
    });
    pl.stream.duration.listen((dur) {
      state = state.copyWith(duration: dur);
      _syncMediaSession();
    });
    pl.stream.completed.listen((completed) {
      if (completed) _onTrackComplete();
      _syncMediaSession();
    });
  }

  void _onTrackComplete() {
    if (state.sleepAfterCurrentTrack) {
      state = state.copyWith(clearSleepAfterTrack: true, isPlaying: false);
      _p.pause();
      return;
    }
    if (state.queue.isEmpty) return;
    switch (state.repeatMode) {
      case ElysiumRepeatMode.one:
        _p.seek(Duration.zero).then((_) => _p.play());
      case ElysiumRepeatMode.all:
        final next = (state.currentIndex + 1) % state.queue.length;
        playIndex(next);
      case ElysiumRepeatMode.off:
        if (state.currentIndex < state.queue.length - 1) {
          playIndex(state.currentIndex + 1);
        }
    }
  }

  Future<void> fetchSettings() async {}

  void playTrackNow(Track track) {
    state = state.copyWith(queue: [track], currentIndex: 0);
    _syncMediaSession();
    playIndex(0);
  }

  void playNext(Track track) {
    if (state.queue.isEmpty) {
      playTrackNow(track);
      return;
    }
    final newQueue = List<Track>.from(state.queue);
    newQueue.insert(state.currentIndex + 1, track);
    state = state.copyWith(queue: newQueue);
    _syncMediaSession();
  }

  void addToQueue(Track track) {
    state = state.copyWith(queue: [...state.queue, track]);
    _syncMediaSession();
    if (state.currentIndex == -1) playIndex(0);
  }

  void addAllToQueue(List<Track> tracks) {
    final wasEmpty = state.queue.isEmpty;
    state = state.copyWith(queue: [...state.queue, ...tracks]);
    _syncMediaSession();
    if (wasEmpty) playIndex(0);
  }

  void playAll(List<Track> tracks) {
    state = state.copyWith(queue: tracks, currentIndex: 0);
    _syncMediaSession();
    playIndex(0);
  }

  @override
  Future<void> playIndex(int index) async {
    if (index < 0 || index >= state.queue.length) return;

    final version = ++_playVersion;
    _scrobbled = false;
    state = state.copyWith(currentIndex: index, clearError: true);
    _syncMediaSession();
    final track = state.queue[index];

    // Single settings read — used for both playing-now and stream resolution
    // below, so we don't risk two divergent snapshots if settings mutate.
    final settings = _settings;

    // Submit "playing now" to ListenBrainz
    if (settings.listenBrainzEnabled &&
        settings.listenBrainzPlayingNow &&
        settings.listenBrainzToken.isNotEmpty) {
      _api
          .submitPlayingNow(
            token: settings.listenBrainzToken,
            artistName: track.artist,
            trackName: track.title,
          )
          .catchError((Object e) => dev.log('Playing-now error: $e'));
    }

    try {
      String? playUrl = track.url;
      if (version != _playVersion) return;

      final api = _api;
      final instance = settings.invidiousInstance.isNotEmpty
          ? settings.invidiousInstance
          : '';

      if (instance.isEmpty && track.videoId != null) {
        throw Exception(
            'No Invidious instance configured. Please set one in Settings.');
      }

      if (track.videoId != null) {
        final details = await api.getVideoDetails(track.videoId!,
            instanceUrl: instance, sid: settings.invidiousSid);
        if (version != _playVersion) return;

        final formats = (details['adaptiveFormats'] as List<dynamic>? ?? []);
        final bestFormat = formats.firstWhere(
          (f) => f['type']?.toString().startsWith('audio/') ?? false,
          orElse: () => formats.isEmpty ? null : formats.first,
        );

        if (bestFormat != null && bestFormat['url'] != null) {
          playUrl = _proxyStreamUrl(bestFormat['url'] as String, instance);
        }
      } else if (playUrl != null &&
          (playUrl.contains('apple.com') || playUrl.contains('itunes'))) {
        if (instance.isEmpty) {
          throw Exception(
              'Invidious instance required to play Apple Music tracks');
        }
        final results = await api.invidiousSearch(
            '${track.artist} ${track.title} official audio',
            instanceUrl: instance);
        if (version != _playVersion) return;

        if (results.isNotEmpty) {
          final match = results.first;
          final details = await api.getVideoDetails(match.videoId ?? match.id,
              instanceUrl: instance, sid: settings.invidiousSid);
          if (version != _playVersion) return;

          final formats = (details['adaptiveFormats'] as List<dynamic>? ?? []);
          final bestFormat = formats.firstWhere(
            (f) => f['type']?.toString().startsWith('audio/') ?? false,
            orElse: () => formats.isEmpty ? null : formats.first,
          );
          if (bestFormat != null && bestFormat['url'] != null) {
            playUrl = _proxyStreamUrl(bestFormat['url'] as String, instance);
          }
        }
      } else if (playUrl == null || playUrl.isEmpty) {
        if (instance.isEmpty) {
          throw Exception(
              'Invidious instance required to resolve this track. Please set one in Settings.');
        }
        final results = await api.invidiousSearch(
            '${track.artist} ${track.title}',
            instanceUrl: instance);
        if (version != _playVersion) return;

        if (results.isNotEmpty) {
          final match = results.first;
          final details = await api.getVideoDetails(match.videoId ?? match.id,
              instanceUrl: instance, sid: settings.invidiousSid);
          if (version != _playVersion) return;

          final formats = (details['adaptiveFormats'] as List<dynamic>? ?? []);
          final bestFormat = formats.firstWhere(
            (f) => f['type']?.toString().startsWith('audio/') ?? false,
            orElse: () => formats.isEmpty ? null : formats.first,
          );
          if (bestFormat != null && bestFormat['url'] != null) {
            playUrl = _proxyStreamUrl(bestFormat['url'] as String, instance);
          }
        }
      }

      if (playUrl != null && playUrl.isNotEmpty && version == _playVersion) {
        await _p.open(Media(playUrl));
        // SponsorBlock: fetch segments async after opening (only for YouTube)
        if (version == _playVersion && track.videoId != null) {
          _fetchSponsorSegments(track.videoId!, version);
        }
      } else if (playUrl == null || playUrl.isEmpty) {
        throw Exception('No playable URL found for this track');
      }
    } catch (e) {
      if (version != _playVersion) return;
      dev.log('Playback error: $e');
      final errMsg = e.toString().replaceAll('Exception: ', '');
      if (track.url != null && track.url!.isNotEmpty) {
        try {
          await _p.open(Media(track.url!));
          return;
        } catch (_) {}
      }
      state = state.copyWith(playbackError: errMsg);
      _syncMediaSession();
    }
  }

  // ── SponsorBlock helpers ──────────────────────────────────────────────────

  /// Fetches SponsorBlock segments for [videoId] in the background.
  /// [version] is the play-version at the time of opening, used to discard
  /// stale results if the user skips to another track before fetch completes.
  void _fetchSponsorSegments(String videoId, int version) {
    final settings = _settings;
    if (!settings.sponsorBlock) return;
    _sponsorSegments = [];
    _skippedSegmentUuids.clear();

    final cats = settings.sponsorBlockCategories;
    _api.sponsorBlockSegments(videoId, categories: cats).then((raw) {
      if (version != _playVersion) return; // Track changed — discard.
      _sponsorSegments = raw
          .whereType<Map<String, dynamic>>()
          .map(SponsorSegment.fromJson)
          .toList();
      dev.log('SponsorBlock: ${_sponsorSegments.length} segments for $videoId');
    }).catchError((Object e) {
      dev.log('SponsorBlock fetch error: $e');
    });
  }

  /// Called every second from the position listener.
  /// Seeks past any SponsorBlock segment the playhead enters.
  void _checkSponsorBlock(Duration pos) {
    if (_sponsorSegments.isEmpty) return;
    final sec = pos.inMilliseconds / 1000.0;
    for (final seg in _sponsorSegments) {
      if (_skippedSegmentUuids.contains(seg.uuid)) continue;
      if (sec >= seg.start && sec < seg.end) {
        _skippedSegmentUuids.add(seg.uuid);
        final skipTo = Duration(milliseconds: (seg.end * 1000).ceil());
        _p.seek(skipTo);
        dev.log(
            'SponsorBlock: skipped [${seg.category}] ${seg.start}–${seg.end}');
        // Report the view to SponsorBlock (best-effort)
        _api.sponsorBlockMarkViewed(seg.uuid).ignore();
        break;
      }
    }
  }

  @override
  Future<void> next() async {
    final q = state.queue;
    if (q.isEmpty) return;
    if (state.shuffled) {
      // Build candidate list excluding current index; fall back to current if only one track
      final candidates = List.generate(q.length, (i) => i)
        ..remove(state.currentIndex);
      if (candidates.isEmpty) {
        await _p.seek(Duration.zero);
        await _p.play();
        return;
      }
      candidates.shuffle();
      await playIndex(candidates.first);
    } else {
      final nextIdx = state.currentIndex + 1;
      // With repeat-off, don't wrap past the last track — consistent with
      // _onTrackComplete which also stops at the end rather than looping.
      if (state.repeatMode == ElysiumRepeatMode.off && nextIdx >= q.length) {
        return;
      }
      await playIndex(nextIdx % q.length);
    }
  }

  @override
  Future<void> previous() async {
    final q = state.queue;
    if (q.isEmpty) return;
    // Guard against uninitialised index
    if (state.currentIndex < 0) {
      await playIndex(0);
      return;
    }
    if (state.position > const Duration(seconds: 3)) {
      await _p.seek(Duration.zero);
      return;
    }
    final prev = (state.currentIndex - 1 + q.length) % q.length;
    await playIndex(prev);
  }

  @override
  Future<void> togglePlayPause() async {
    await _p.playOrPause();
  }

  @override
  Future<void> seekTo(Duration position) async {
    await _p.seek(position);
  }

  // State is updated synchronously so callers can immediately call playIndex
  // without a race; the player stop runs in background and is naturally
  // superseded by the open() call in playIndex.
  void setQueue(List<Track> tracks) {
    _player?.stop();
    state = state.copyWith(
      queue: tracks,
      currentIndex: -1,
      isPlaying: false,
      position: Duration.zero,
      duration: Duration.zero,
      clearSleepTimerEnd: true,
      clearSleepAfterTrack: true,
    );
    _syncMediaSession();
  }

  @override
  void toggleShuffle() {
    state = state.copyWith(shuffled: !state.shuffled);
    _syncMediaSession();
  }

  @override
  void cycleRepeat() {
    final next = ElysiumRepeatMode
        .values[(state.repeatMode.index + 1) % ElysiumRepeatMode.values.length];
    state = state.copyWith(repeatMode: next);
    _syncMediaSession();
  }

  void clearPlaybackError() {
    state = state.copyWith(clearError: true);
    _syncMediaSession();
  }

  /// Pause after [minutes] (from now). Pass `null` or `0` to clear wall-clock timer only.
  void setSleepTimerMinutes(int? minutes) {
    if (minutes == null || minutes <= 0) {
      state = state.copyWith(clearSleepTimerEnd: true);
      return;
    }
    state = state.copyWith(
      sleepTimerEnd: DateTime.now().add(Duration(minutes: minutes)),
      sleepAfterCurrentTrack: false,
    );
  }

  void setSleepAfterCurrentTrack(bool value) {
    state = state.copyWith(
      sleepAfterCurrentTrack: value,
      clearSleepTimerEnd: value,
    );
  }

  void clearSleepTimer() {
    state =
        state.copyWith(clearSleepTimerEnd: true, clearSleepAfterTrack: true);
  }

  void _checkSleepTimer() {
    final end = state.sleepTimerEnd;
    if (end == null) return;
    if (DateTime.now().isBefore(end)) return;
    _p.pause();
    state = state.copyWith(clearSleepTimerEnd: true, isPlaying: false);
  }

  void reorderQueue(int oldIndex, int newIndex) {
    final q = state.queue;
    if (oldIndex < 0 ||
        oldIndex >= q.length ||
        newIndex < 0 ||
        newIndex > q.length) {
      return;
    }
    var ni = newIndex;
    if (ni > oldIndex) ni -= 1;
    final list = List<Track>.from(q);
    final item = list.removeAt(oldIndex);
    list.insert(ni, item);
    final id = state.currentTrack?.effectiveId;
    var newCi = state.currentIndex;
    if (id != null) {
      final found = list.indexWhere((t) => t.effectiveId == id);
      if (found >= 0) newCi = found;
    } else {
      newCi = newCi.clamp(0, list.length - 1);
    }
    state = state.copyWith(queue: list, currentIndex: newCi);
    _syncMediaSession();
  }

  Future<void> removeFromQueueAt(int index) async {
    final q = state.queue;
    if (index < 0 || index >= q.length) return;
    final list = List<Track>.from(q);
    final wasCurrent = index == state.currentIndex;
    list.removeAt(index);
    if (list.isEmpty) {
      _player?.stop();
      state = state.copyWith(
        queue: [],
        currentIndex: -1,
        position: Duration.zero,
        duration: Duration.zero,
        isPlaying: false,
        clearSleepTimerEnd: true,
        clearSleepAfterTrack: true,
      );
      _syncMediaSession();
      return;
    }
    var newCi = state.currentIndex;
    if (index < newCi) {
      newCi--;
    } else if (index == newCi) {
      newCi = newCi.clamp(0, list.length - 1);
    }
    state = state.copyWith(queue: list, currentIndex: newCi);
    _syncMediaSession();
    if (wasCurrent) {
      await playIndex(newCi);
    }
  }

  void setFavorites(List<Track> favs) {
    state = state.copyWith(favorites: favs);
  }

  void addFavorite(Track track) {
    if (!state.isFavorite(track.effectiveId)) {
      state = state.copyWith(favorites: [...state.favorites, track]);
    }
  }

  void removeFavorite(String id) {
    state = state.copyWith(
      favorites:
          state.favorites.where((f) => (f.videoId ?? f.id) != id).toList(),
    );
  }

  /// Rewrites a direct YouTube CDN URL to route through the Invidious proxy.
  /// YouTube ties stream URLs to the server IP that requested them; proxying
  /// through the same Invidious instance that resolved the URL avoids 403s.
  String _proxyStreamUrl(String url, String instance) {
    if (instance.isEmpty) return url;
    try {
      final uri = Uri.parse(url);
      // Only rewrite googlevideo.com CDN URLs
      if (!uri.host.contains('googlevideo.com')) return url;
      final base = instance.replaceAll(RegExp(r'/+$'), '');
      // Proxy format: instance/videoplayback?...&host=original-host
      final newUri = Uri.parse('$base/videoplayback').replace(queryParameters: {
        ...uri.queryParameters,
        'host': uri.host,
      });
      return newUri.toString();
    } catch (_) {
      return url;
    }
  }

  // ── _RemotePlayerProxy implementation ───────────────────────────────────

  @override
  Map<String, dynamic> stateSnapshot() {
    final t = state.currentTrack;
    return {
      'isPlaying': state.isPlaying,
      'position': state.position.inMilliseconds,
      'duration': state.duration.inMilliseconds,
      'shuffled': state.shuffled,
      'repeatMode': state.repeatMode.name,
      'track': t == null
          ? null
          : {
              'id': t.effectiveId,
              'title': t.title,
              'artist': t.artist,
              'artwork': t.artwork,
            },
      'queueLength': state.queue.length,
      'currentIndex': state.currentIndex,
    };
  }

  @override
  Future<void> play() => _p.play();

  @override
  Future<void> pause() => _p.pause();

  @override
  Future<void> stopFromOs() async {
    await _p.stop();
    state = state.copyWith(isPlaying: false, position: Duration.zero);
    _syncMediaSession();
  }

  // ── ListenBrainz scrobbling ──────────────────────────────────────────────

  void _checkScrobble(Duration pos) {
    final s = _settings;
    if (!s.listenBrainzEnabled || s.listenBrainzToken.isEmpty) return;
    final track = state.currentTrack;
    if (track == null || _scrobbled) return;
    final dur = state.duration;
    if (dur.inSeconds < 30) return; // also guards dur == 0
    final pct = pos.inSeconds / dur.inSeconds * 100.0;
    final maxSec = s.listenBrainzScrobbleMaxSeconds;
    // threshold 0 must not mean "100% of the song" (pct >= 0 is always true)
    final threshold = s.listenBrainzScrobblePercent.clamp(0, 100);
    final byPercent = threshold > 0 && pct >= threshold;
    final byMaxSec = maxSec > 0 && pos.inSeconds >= maxSec;
    if (byPercent || byMaxSec) {
      _scrobbled = true;
      _api
          .scrobble(
            token: s.listenBrainzToken,
            artistName: track.artist,
            trackName: track.title,
          )
          .catchError((Object e) => dev.log('Scrobble error: $e'));
    }
  }

  // ── Remote server control ─────────────────────────────────────────────────

  Future<void> startRemoteServer() async => RemoteServer.start(
        this,
        peerCallback: (host, port) async {
          await _ref.read(localStoreProvider.notifier).updateSettings({
            'remoteHostIp': host,
            'remotePeerPort': port,
          });
        },
      );
  Future<void> stopRemoteServer() async => RemoteServer.stop();

  @override
  void dispose() {
    _disposed = true;
    _mediaSessionTicker?.cancel();
    MediaSessionBridge.detachPlayer();
    RemoteServer.stop();
    _player?.dispose();
    super.dispose();
  }
}
