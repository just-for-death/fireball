import 'package:flutter_test/flutter_test.dart';
import 'package:fireball/core/models/models.dart';
import 'package:fireball/core/models/track.dart';
import 'package:fireball/core/store/library_data.dart';
import 'package:fireball/core/store/library_merge.dart';

void main() {
  group('LibraryMerge', () {
    test('merges remote playlists into local, unioning tracks', () {
      final localPl = Playlist(
        id: 'pl_1',
        title: 'Local Favs',
        videos: [
          const Track(id: 't1', title: 'T1', artist: 'A1'),
        ],
      );
      final remotePl = Playlist(
        id: 'pl_1',
        title: 'Local Favs', // Same ID and title
        videos: [
          const Track(id: 't2', title: 'T2', artist: 'A2'), // new track
          const Track(id: 't1', title: 'T1', artist: 'A1'), // duplicate
        ],
      );

      final local = LibraryData(playlists: [localPl]);
      final remote = LibraryData(playlists: [remotePl]);

      final merged = mergeLibraryData(local, remote);

      expect(merged.playlists.length, 1);
      final mergedPl = merged.playlists.first;
      expect(mergedPl.videos.length, 2); // t1 and t2 (no duplicates)
      expect(mergedPl.videos.any((t) => t.id == 't1'), true);
      expect(mergedPl.videos.any((t) => t.id == 't2'), true);
    });

    test('preserves local playlists that are not in remote', () {
      final localPl = Playlist(
        id: 'pl_local',
        title: 'Only Local',
        videos: [const Track(id: 't1', title: 'T1', artist: 'A1')],
      );
      final remotePl = Playlist(
        id: 'pl_remote',
        title: 'Only Remote',
        videos: [const Track(id: 't2', title: 'T2', artist: 'A2')],
      );

      final local = LibraryData(playlists: [localPl]);
      final remote = LibraryData(playlists: [remotePl]);

      final merged = mergeLibraryData(local, remote);

      expect(merged.playlists.length, 2);
      expect(merged.playlists.any((p) => p.id == 'pl_local'), true);
      expect(merged.playlists.any((p) => p.id == 'pl_remote'), true);
    });

    test('unions history and favorites, deduplicating by ID', () {
      final t1 = const Track(id: 't1', title: 'T1', artist: 'A1');
      final t2 = const Track(id: 't2', title: 'T2', artist: 'A2');
      final t3 = const Track(id: 't3', title: 'T3', artist: 'A3');

      final local = LibraryData(
        history: [t1, t2],
        favorites: [t1],
      );
      final remote = LibraryData(
        history: [t2, t3],
        favorites: [t1, t2],
      );

      final merged = mergeLibraryData(local, remote);

      expect(merged.history.length, 3);
      expect(merged.history.map((t) => t.id).toSet(), {'t1', 't2', 't3'});

      expect(merged.favorites.length, 2);
      expect(merged.favorites.map((t) => t.id).toSet(), {'t1', 't2'});
    });
  });

  group('FireballSettings Merge', () {
    test('fills empty service/account fields from remote without clobbering local overrides', () {
      final localSettings = const FireballSettings(
        themeMode: 'dark', // Should be preserved
        invidiousInstance: 'https://local.inv',
        listenBrainzToken: '', // Should be filled from remote
      );

      final remoteSettings = const FireballSettings(
        themeMode: 'light', // Should NOT overwrite local
        invidiousInstance: 'https://remote.inv', // Should NOT overwrite local
        listenBrainzToken: 'remote-token', // Should fill local empty
        homeCountries: ['JP', 'UK'],
      );

      final merged = localSettings.mergeSharedFromRemote(remoteSettings);

      expect(merged.themeMode, 'dark'); // Preserved
      expect(merged.invidiousInstance, 'https://local.inv'); // Preserved
      expect(merged.listenBrainzToken, 'remote-token'); // Filled
      expect(merged.homeCountries, ['JP', 'UK']); // Filled
    });
  });
}
