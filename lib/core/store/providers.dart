import 'dart:developer' as dev;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import '../api/fireball_api.dart';
import '../models/models.dart';
import '../models/track.dart';
import '../../remote/remote_server.dart';
import 'local_store.dart';

export 'local_store.dart' show localStoreProvider, LibraryData, LocalStoreNotifier;

// ── Settings convenience provider ────────────────────────────────────────────
final settingsProvider = Provider<FireballSettings>((ref) {
  return ref.watch(localStoreProvider).settings;
});

// ── Player state ─────────────────────────────────────────────────────────────
enum ElysiumRepeatMode { off, all, one }

class PlayerState {
  final List<Track> queue;
  final int currentIndex;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final bool shuffled;
  final ElysiumRepeatMode repeatMode;
  final List<Track> favorites;
  final bool videoMode;
  final String? playbackError;
  /// Wall-clock time when playback should pause (sleep timer).
  final DateTime? sleepTimerEnd;
  /// When true, pause after the current track finishes (natural end).
  final bool sleepAfterCurrentTrack;

  const PlayerState({
    this.queue = const [],
    this.currentIndex = -1,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.shuffled = false,
    this.repeatMode = ElysiumRepeatMode.off,
    this.favorites = const [],
    this.videoMode = false,
    this.playbackError,
    this.sleepTimerEnd,
    this.sleepAfterCurrentTrack = false,
  });

  Track? get currentTrack =>
      currentIndex >= 0 && currentIndex < queue.length ? queue[currentIndex] : null;

  bool isFavorite(String id) => favorites.any((f) => (f.videoId ?? f.id) == id);

  PlayerState copyWith({
    List<Track>? queue,
    int? currentIndex,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    bool? shuffled,
    ElysiumRepeatMode? repeatMode,
    List<Track>? favorites,
    bool? videoMode,
    String? playbackError,
    bool clearError = false,
    DateTime? sleepTimerEnd,
    bool clearSleepTimerEnd = false,
    bool? sleepAfterCurrentTrack,
    bool clearSleepAfterTrack = false,
  }) =>
      PlayerState(
        queue: queue ?? this.queue,
        currentIndex: currentIndex ?? this.currentIndex,
        isPlaying: isPlaying ?? this.isPlaying,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        shuffled: shuffled ?? this.shuffled,
        repeatMode: repeatMode ?? this.repeatMode,
        favorites: favorites ?? this.favorites,
        videoMode: videoMode ?? this.videoMode,
        playbackError: clearError ? null : (playbackError ?? this.playbackError),
        sleepTimerEnd:
            clearSleepTimerEnd ? null : (sleepTimerEnd ?? this.sleepTimerEnd),
        sleepAfterCurrentTrack: clearSleepAfterTrack
            ? false
            : (sleepAfterCurrentTrack ?? this.sleepAfterCurrentTrack),
      );
}

// ── Player Notifier ───────────────────────────────────────────────────────────
final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerState>((ref) {
  return PlayerNotifier(ref);
});

class PlayerNotifier extends StateNotifier<PlayerState>
    implements RemotePlayerProxy {
  late final Player _player;
  final Ref _ref;
  int _playVersion = 0;
  bool _scrobbled = false;

  PlayerNotifier(this._ref) : super(const PlayerState()) {
    _player = Player();
    _listenToPlayer();
  }

  FireballApi get _api => const FireballApi();
  FireballSettings get _settings => _ref.read(settingsProvider);

  Player get player => _player;

  void _listenToPlayer() {
    _player.stream.playing.listen((playing) {
      state = state.copyWith(isPlaying: playing);
    });
    _player.stream.position.listen((pos) {
      state = state.copyWith(position: pos);
      _checkScrobble(pos);
      _checkSleepTimer();
    });
    _player.stream.duration.listen((dur) {
      state = state.copyWith(duration: dur);
    });
    _player.stream.completed.listen((completed) {
      if (completed) _onTrackComplete();
    });
  }

  void _onTrackComplete() {
    if (state.sleepAfterCurrentTrack) {
      state = state.copyWith(clearSleepAfterTrack: true, isPlaying: false);
      _player.pause();
      return;
    }
    if (state.queue.isEmpty) return;
    switch (state.repeatMode) {
      case ElysiumRepeatMode.one:
        _player.seek(Duration.zero).then((_) => _player.play());
      case ElysiumRepeatMode.all:
        final next = (state.currentIndex + 1) % state.queue.length;
        playIndex(next);
      case ElysiumRepeatMode.off:
        if (state.currentIndex < state.queue.length - 1) {
          playIndex(state.currentIndex + 1);
        }
    }
  }

  Future<void> fetchSettings() async {
    final s = _ref.read(settingsProvider);
    state = state.copyWith(videoMode: s.videoMode);
  }

  Future<void> toggleVideoMode() async {
    final newMode = !state.videoMode;
    state = state.copyWith(videoMode: newMode);
    await _ref.read(localStoreProvider.notifier).updateSettings({'videoMode': newMode});
    if (state.currentIndex != -1) {
      await playIndex(state.currentIndex);
    }
  }

  void playTrackNow(Track track) {
    state = state.copyWith(queue: [track], currentIndex: 0);
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
  }

  void addToQueue(Track track) {
    state = state.copyWith(queue: [...state.queue, track]);
    if (state.currentIndex == -1) playIndex(0);
  }

  void addAllToQueue(List<Track> tracks) {
    final wasEmpty = state.queue.isEmpty;
    state = state.copyWith(queue: [...state.queue, ...tracks]);
    if (wasEmpty) playIndex(0);
  }

  void playAll(List<Track> tracks) {
    state = state.copyWith(queue: tracks, currentIndex: 0);
    playIndex(0);
  }

  Future<void> playIndex(int index) async {
    if (index < 0 || index >= state.queue.length) return;

    final version = ++_playVersion;
    _scrobbled = false;
    state = state.copyWith(currentIndex: index, clearError: true);
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

      state = state.copyWith(videoMode: settings.videoMode);
      final api = _api;
      final instance = settings.invidiousInstance.isNotEmpty
          ? settings.invidiousInstance
          : '';

      if (instance.isEmpty && track.videoId != null) {
        throw Exception(
            'No Invidious instance configured. Please set one in Settings.');
      }

      // ── Stream Resolution Logic ──────────────────────────────────────────
      if (track.videoId != null) {
        final details = await api.getVideoDetails(track.videoId!,
            instanceUrl: instance, sid: settings.invidiousSid);
        if (version != _playVersion) return;

        final formats = (details['adaptiveFormats'] as List<dynamic>? ?? []);
        dynamic bestFormat;

        if (state.videoMode) {
          bestFormat = formats.firstWhere(
            (f) =>
                (f['type']?.toString().contains('video/') ?? false) &&
                f['videoOnly'] != true,
            orElse: () => formats.firstWhere(
              (f) => f['type']?.toString().contains('video/') ?? false,
              orElse: () => formats.isEmpty ? null : formats.first,
            ),
          );
        } else {
          bestFormat = formats.firstWhere(
            (f) => f['type']?.toString().startsWith('audio/') ?? false,
            orElse: () => formats.isEmpty ? null : formats.first,
          );
        }

        if (bestFormat != null && bestFormat['url'] != null) {
          playUrl = _proxyStreamUrl(bestFormat['url'] as String, instance);
        }
      } else if (playUrl != null &&
          (playUrl.contains('apple.com') || playUrl.contains('itunes'))) {
        if (instance.isEmpty) {
          throw Exception('Invidious instance required to play Apple Music tracks');
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
          final details = await api.getVideoDetails(
              match.videoId ?? match.id,
              instanceUrl: instance,
              sid: settings.invidiousSid);
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
        await _player.open(Media(playUrl));
      } else if (playUrl == null || playUrl.isEmpty) {
        throw Exception('No playable URL found for this track');
      }
    } catch (e) {
      if (version != _playVersion) return;
      dev.log('Playback error: $e');
      final errMsg = e.toString().replaceAll('Exception: ', '');
      if (track.url != null && track.url!.isNotEmpty) {
        try {
          await _player.open(Media(track.url!));
          return;
        } catch (_) {}
      }
      state = state.copyWith(playbackError: errMsg);
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
        await _player.seek(Duration.zero);
        await _player.play();
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
      await _player.seek(Duration.zero);
      return;
    }
    final prev = (state.currentIndex - 1 + q.length) % q.length;
    await playIndex(prev);
  }

  @override
  Future<void> togglePlayPause() async {
    await _player.playOrPause();
  }

  @override
  Future<void> seekTo(Duration position) async {
    await _player.seek(position);
  }

  // State is updated synchronously so callers can immediately call playIndex
  // without a race; the player stop runs in background and is naturally
  // superseded by the open() call in playIndex.
  void setQueue(List<Track> tracks) {
    _player.stop();
    state = state.copyWith(
      queue: tracks,
      currentIndex: -1,
      isPlaying: false,
      position: Duration.zero,
      duration: Duration.zero,
    );
  }


  void toggleShuffle() {
    state = state.copyWith(shuffled: !state.shuffled);
  }

  void cycleRepeat() {
    final next = ElysiumRepeatMode
        .values[(state.repeatMode.index + 1) % ElysiumRepeatMode.values.length];
    state = state.copyWith(repeatMode: next);
  }

  void clearPlaybackError() {
    state = state.copyWith(clearError: true);
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
    state = state.copyWith(clearSleepTimerEnd: true, clearSleepAfterTrack: true);
  }

  void _checkSleepTimer() {
    final end = state.sleepTimerEnd;
    if (end == null) return;
    if (DateTime.now().isBefore(end)) return;
    _player.pause();
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
  }

  Future<void> removeFromQueueAt(int index) async {
    final q = state.queue;
    if (index < 0 || index >= q.length) return;
    final list = List<Track>.from(q);
    final wasCurrent = index == state.currentIndex;
    list.removeAt(index);
    if (list.isEmpty) {
      _player.stop();
      state = state.copyWith(
        queue: [],
        currentIndex: -1,
        position: Duration.zero,
        duration: Duration.zero,
        isPlaying: false,
        clearSleepTimerEnd: true,
        clearSleepAfterTrack: true,
      );
      return;
    }
    var newCi = state.currentIndex;
    if (index < newCi) {
      newCi--;
    } else if (index == newCi) {
      newCi = newCi.clamp(0, list.length - 1);
    }
    state = state.copyWith(queue: list, currentIndex: newCi);
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
      favorites: state.favorites.where((f) => (f.videoId ?? f.id) != id).toList(),
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
      final newUri = Uri.parse('$base/videoplayback')
          .replace(queryParameters: {
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
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

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
    if (pct >= s.listenBrainzScrobblePercent ||
        (maxSec > 0 && pos.inSeconds >= maxSec)) {
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

  Future<void> startRemoteServer() async => RemoteServer.start(this);
  Future<void> stopRemoteServer() async => RemoteServer.stop();

  @override
  void dispose() {
    RemoteServer.stop();
    _player.dispose();
    super.dispose();
  }
}
