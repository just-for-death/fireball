import '../store/player_state.dart';

/// Commands OS media callbacks delegate to; implemented by [PlayerNotifier].
abstract class MediaSessionPlayer {
  /// Current playback snapshot (named to avoid clashing with [StateNotifier.state]).
  PlayerState get sessionState;

  Future<void> play();

  Future<void> pause();

  Future<void> seekTo(Duration position);

  Future<void> next();

  Future<void> previous();

  /// Stop playback from lock screen / notification (not full queue clear).
  Future<void> stopFromOs();

  Future<void> playIndex(int index);

  void toggleShuffle();

  void cycleRepeat();
}
