import 'package:audio_service/audio_service.dart';

import '../store/player_state.dart';
import 'media_session_bridge.dart';

/// Routes headset / notification / lock-screen actions into [MediaSessionPlayer].
class FireballAudioHandler extends BaseAudioHandler with SeekHandler {
  @override
  Future<void> play() async {
    await MediaSessionBridge.player?.play();
    MediaSessionBridge.sync();
  }

  @override
  Future<void> pause() async {
    await MediaSessionBridge.player?.pause();
    MediaSessionBridge.sync();
  }

  @override
  Future<void> seek(Duration position) async {
    await MediaSessionBridge.player?.seekTo(position);
    MediaSessionBridge.sync();
  }

  @override
  Future<void> skipToNext() async {
    await MediaSessionBridge.player?.next();
    MediaSessionBridge.sync();
  }

  @override
  Future<void> skipToPrevious() async {
    await MediaSessionBridge.player?.previous();
    MediaSessionBridge.sync();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await MediaSessionBridge.player?.playIndex(index);
    MediaSessionBridge.sync();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final p = MediaSessionBridge.player;
    if (p == null) return;
    final wantOn = shuffleMode != AudioServiceShuffleMode.none;
    if (wantOn != p.sessionState.shuffled) {
      p.toggleShuffle();
    }
    MediaSessionBridge.sync();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final p = MediaSessionBridge.player;
    if (p == null) return;
    final target = _elysiumRepeat(repeatMode);
    if (p.sessionState.repeatMode == target) return;
    for (var i = 0; i < 8 && p.sessionState.repeatMode != target; i++) {
      p.cycleRepeat();
    }
    MediaSessionBridge.sync();
  }

  static ElysiumRepeatMode _elysiumRepeat(AudioServiceRepeatMode m) {
    switch (m) {
      case AudioServiceRepeatMode.none:
      case AudioServiceRepeatMode.group:
        return ElysiumRepeatMode.off;
      case AudioServiceRepeatMode.one:
        return ElysiumRepeatMode.one;
      case AudioServiceRepeatMode.all:
        return ElysiumRepeatMode.all;
    }
  }

  @override
  Future<void> stop() async {
    await MediaSessionBridge.player?.stopFromOs();
    await super.stop();
  }
}
