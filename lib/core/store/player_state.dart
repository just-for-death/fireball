import '../models/track.dart';

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
  final String? playbackError;
  final DateTime? sleepTimerEnd;
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
    this.playbackError,
    this.sleepTimerEnd,
    this.sleepAfterCurrentTrack = false,
  });

  Track? get currentTrack => currentIndex >= 0 && currentIndex < queue.length
      ? queue[currentIndex]
      : null;

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
        playbackError:
            clearError ? null : (playbackError ?? this.playbackError),
        sleepTimerEnd:
            clearSleepTimerEnd ? null : (sleepTimerEnd ?? this.sleepTimerEnd),
        sleepAfterCurrentTrack: clearSleepAfterTrack
            ? false
            : (sleepAfterCurrentTrack ?? this.sleepAfterCurrentTrack),
      );
}
