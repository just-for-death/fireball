import 'package:audio_service/audio_service.dart';

import '../models/track.dart';
import '../store/player_state.dart';
import 'media_session_player.dart';

/// Pushes [PlayerState] into [audio_service] for notifications / lock screen / OS controls.
class MediaSessionBridge {
  MediaSessionBridge._();

  static BaseAudioHandler? handler;
  static MediaSessionPlayer? player;

  /// Called from [main] after [AudioService.init] assigns [handler].
  static void attachPlayer(MediaSessionPlayer p) {
    player = p;
    sync();
  }

  /// Clears the in-memory [player] and resets OS media state (notification / MPRIS)
  /// so we do not leave a stale "playing" session after hot restart or provider dispose.
  static void detachPlayer() {
    player = null;
    final h = handler;
    if (h == null) return;
    h.queue.add([]);
    h.mediaItem.add(null);
    h.playbackState.add(PlaybackState(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  static AudioServiceRepeatMode _repeat(ElysiumRepeatMode m) {
    switch (m) {
      case ElysiumRepeatMode.off:
        return AudioServiceRepeatMode.none;
      case ElysiumRepeatMode.one:
        return AudioServiceRepeatMode.one;
      case ElysiumRepeatMode.all:
        return AudioServiceRepeatMode.all;
    }
  }

  static MediaItem _itemForTrack(Track t, PlayerState s) {
    Duration? dur;
    final cur = s.currentTrack;
    final isCurrent = cur != null && cur.effectiveId == t.effectiveId;
    if (isCurrent && s.duration > Duration.zero) {
      dur = s.duration;
    } else if (t.duration != null && t.duration! > 0) {
      dur = Duration(seconds: t.duration!);
    }
    Uri? art;
    final a = t.artwork;
    if (a != null && a.isNotEmpty) {
      final u = Uri.tryParse(a);
      if (u != null && u.hasScheme) art = u;
    }
    return MediaItem(
      id: t.effectiveId,
      title: t.title,
      artist: t.artist,
      album: t.album,
      duration: dur,
      artUri: art,
    );
  }

  /// Updates queue, current [MediaItem], and [PlaybackState] from the active [MediaSessionPlayer].
  static void sync() {
    final h = handler;
    final p = player;
    if (h == null || p == null) return;

    final s = p.sessionState;
    final items = s.queue.map((t) => _itemForTrack(t, s)).toList();
    h.queue.add(items);

    final t = s.currentTrack;
    if (t != null) {
      h.mediaItem.add(_itemForTrack(t, s));
    } else {
      h.mediaItem.add(null);
    }

    AudioProcessingState processing;
    int? errorCode;
    String? errorMessage;
    if (s.playbackError != null && s.playbackError!.isNotEmpty) {
      processing = AudioProcessingState.error;
      errorMessage = s.playbackError;
      errorCode = 1;
    } else if (t == null || s.currentIndex < 0 || s.queue.isEmpty) {
      processing = AudioProcessingState.idle;
    } else {
      processing = AudioProcessingState.ready;
    }

    final playing = s.isPlaying && processing == AudioProcessingState.ready;

    final controls = playing
        ? <MediaControl>[
            MediaControl.skipToPrevious,
            MediaControl.pause,
            MediaControl.skipToNext,
          ]
        : <MediaControl>[
            MediaControl.skipToPrevious,
            MediaControl.play,
            MediaControl.skipToNext,
          ];

    final systemActions = <MediaAction>{
      MediaAction.seek,
      MediaAction.play,
      MediaAction.pause,
      MediaAction.skipToNext,
      MediaAction.skipToPrevious,
      MediaAction.stop,
      MediaAction.setShuffleMode,
      MediaAction.setRepeatMode,
    };

    h.playbackState.add(PlaybackState(
      processingState: processing,
      playing: playing,
      controls: controls,
      systemActions: systemActions,
      androidCompactActionIndices: const [0, 1, 2],
      updatePosition: s.position,
      bufferedPosition: s.position,
      speed: 1.0,
      errorCode: errorCode,
      errorMessage: errorMessage,
      repeatMode: _repeat(s.repeatMode),
      shuffleMode: s.shuffled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
      queueIndex: s.currentIndex >= 0 ? s.currentIndex : null,
    ));
  }
}
