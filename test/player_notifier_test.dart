import 'package:flutter_test/flutter_test.dart';
import 'package:fireball/core/models/track.dart';
import 'package:fireball/core/store/player_state.dart';

// Mock container setup to test the PlayerNotifier logic
// Since media_kit native backend requires complex initialization, we mock
// the environment or test the state transitions.

void main() {
  group('PlayerState', () {
    test('initial state is correct', () {
      final state = const PlayerState();
      expect(state.queue, isEmpty);
      expect(state.currentIndex, -1);
      expect(state.isPlaying, false);
      expect(state.repeatMode, ElysiumRepeatMode.off);
    });

    test('copyWith updates fields correctly', () {
      final state = const PlayerState();
      final updated = state.copyWith(
        currentIndex: 5,
        isPlaying: true,
      );

      expect(updated.currentIndex, 5);
      expect(updated.isPlaying, true);
      // Unchanged fields remain
      expect(updated.repeatMode, ElysiumRepeatMode.off);
      expect(updated.queue, isEmpty);
    });

    test('currentTrack resolves correctly based on queue and index', () {
      final t1 = const Track(id: 't1', title: 'T1', artist: 'A1');
      final t2 = const Track(id: 't2', title: 'T2', artist: 'A2');

      var state = const PlayerState(
        queue: [],
        currentIndex: -1,
      );
      expect(state.currentTrack, isNull);

      state = PlayerState(
        queue: [t1, t2],
        currentIndex: 0,
      );
      expect(state.currentTrack?.id, 't1');

      state = state.copyWith(currentIndex: 1);
      expect(state.currentTrack?.id, 't2');

      // Out of bounds
      state = state.copyWith(currentIndex: 5);
      expect(state.currentTrack, isNull);
    });
  });

  // Since PlayerNotifier instantiates a native media_kit Player, unit testing it
  // in a plain Dart environment throws NativeLibraryNotFoundException.
  // We'll test its non-native pure queue management logic by extending it and
  // overriding the _ensurePlayer method, or just testing the PlayerState above.
  // A full unit test of PlayerNotifier requires mock platform channels or flutter_test GUI environment.
}
