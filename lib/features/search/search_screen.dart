import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/adapters/fireball_backend_bridge.dart';
import '../../core/models/track.dart';
import '../../core/store/providers.dart';
import '../../core/theme/fireball_tokens.dart';
import '../../core/ui/messenger_service.dart';
import '../../core/ui/shell_content_insets.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/glass_widgets.dart';
import '../../core/widgets/overflow_safe_text.dart';
import '../../core/widgets/songs_table.dart';
import '../../core/widgets/track_options_sheet.dart';

const _genres = [
  'Pop',
  'Hip-Hop',
  'R&B',
  'Rock',
  'Electronic',
  'Jazz',
  'Classical',
  'K-Pop',
  'Indie',
];
const _searchFilters = ['All', 'Songs', 'Playlists', 'Artists', 'Albums'];
const _browseColors = [
  Color(0xFF8D67AB),
  Color(0xFFBA5D07),
  Color(0xFF27856A),
  Color(0xFFBC5900),
  Color(0xFF1E3264),
  Color(0xFFA56752),
  Color(0xFF477D95),
  Color(0xFF5F8109),
  Color(0xFFAF2896),
];

class SearchScreen extends HookConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final library = ref.watch(localStoreProvider);
    final bridge = useMemoized(() => FireballBackendBridge());
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final isTablet = width >= 700;
    final isDesktopWide = width >= 1000;
    final hPad = isTablet ? 20.0 : 24.0;
    final recentSearchRows = library.history.take(6).toList();

    final query = useState('');
    final results = useState<List<Map<String, dynamic>>>([]);
    final trending = useState<List<Map<String, dynamic>>>([]);
    final loading = useState(false);
    final selectedGenre = useState<String?>(null);
    final selectedFilter = useState<String>('All');
    final controller = useTextEditingController();

    // Load trending on mount
    useEffect(() {
      bridge.fetchTopSongs(countryCode: 'us', limit: 20).then((data) {
        trending.value = data;
      }).catchError((_) {});
      return null;
    }, const []);

    // Debounced search — uses a Timer so cancellation also cancels the callback.
    // The old Stream.fromFuture approach only cancelled the listener, not the
    // inner Future.delayed, which could still fire and overwrite newer results.
    useEffect(() {
      if (query.value.trim().isEmpty) {
        results.value = [];
        return null;
      }
      // Capture a request id at the time the effect fires.
      // The async callback checks whether a newer effect has already replaced it.
      final capturedQuery = query.value;
      final timer = Timer(const Duration(milliseconds: 450), () async {
        // Bail out if the query changed while we were waiting.
        if (query.value != capturedQuery) {
          return;
        }
        loading.value = true;
        try {
          // iTunes-first search with Invidious fallback through bridge.
          final mergedResults =
              await bridge.searchAll(query: capturedQuery, settings: settings);
          if (query.value != capturedQuery) return;
          results.value = mergedResults;
        } catch (e) {
          MessengerService.instance.showError('Search failed: $e');
          results.value = [];
        } finally {
          if (query.value == capturedQuery) {
            loading.value = false;
          }
        }
      });
      return timer.cancel;
    }, [query.value]);

    Future<void> searchGenre(String genre) async {
      selectedGenre.value = genre;
      query.value = '';
      controller.clear();
      loading.value = true;
      try {
        results.value = await bridge.searchGenre(genre);
      } finally {
        loading.value = false;
      }
    }

    Future<void> playResult(List<Map<String, dynamic>> source, int index) async {
      final selected = source[index];
      if (selected['kind'] == 'artist') {
        final name = selected['title']?.toString() ?? '';
        if (name.isNotEmpty) {
          context.push('/artist?name=${Uri.encodeComponent(name)}');
        }
        return;
      }

      if (selected['kind'] == 'album') {
        final collectionIdRaw = selected['collectionId'];
        final collectionId = collectionIdRaw is int
            ? collectionIdRaw
            : int.tryParse(collectionIdRaw?.toString() ?? '');
        if (collectionId == null) return;
        loading.value = true;
        try {
          final albumTracks = await bridge.collectionTracks(collectionId);
          if (albumTracks.isNotEmpty) {
            ref.read(playerProvider.notifier).setQueue(albumTracks);
            ref.read(playerProvider.notifier).playIndex(0);
          }
          return;
        } finally {
          loading.value = false;
        }
      }

      if (selected['kind'] == 'playlist') {
        final collectionIdRaw = selected['collectionId'];
        final collectionId = collectionIdRaw is int
            ? collectionIdRaw
            : int.tryParse(collectionIdRaw?.toString() ?? '');
        if (collectionId == null) return;

        loading.value = true;
        try {
          final playlistTracks = await bridge.collectionTracks(collectionId);
          if (playlistTracks.isEmpty) {
            MessengerService.instance.showInfo('Playlist has no playable tracks');
            return;
          }
          if (playlistTracks.isEmpty) return;
          ref.read(playerProvider.notifier).setQueue(playlistTracks);
          ref.read(playerProvider.notifier).playIndex(0);
          return;
        } finally {
          loading.value = false;
        }
      }

      final tracks = source
          .map((r) => Track(
                id: r['id'] ?? '',
                videoId: r['videoId'],
                title: r['title'] ?? '—',
                artist: r['artist'] ?? '—',
                artwork: r['artwork'],
                url: r['url'] ?? '',
                duration: r['duration'],
                album: r['album'],
                year: r['year'],
              ))
          .toList();
      ref.read(playerProvider.notifier).setQueue(tracks);
      ref.read(playerProvider.notifier).playIndex(index);
    }

    final isSearching =
        query.value.trim().isNotEmpty || selectedGenre.value != null;
    final baseList = isSearching ? results.value : trending.value;
    final displayList = selectedFilter.value == 'All'
        ? baseList
        : baseList.where((r) {
            final kind = (r['kind']?.toString() ?? 'song').toLowerCase();
            switch (selectedFilter.value) {
              case 'Songs':
                return kind == 'song';
              case 'Playlists':
                return kind == 'playlist';
              case 'Artists':
                return kind == 'artist';
              case 'Albums':
                return kind == 'album';
              default:
                return true;
            }
          }).toList();

    return PremiumBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, isTablet ? 20 : 28, hPad, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: FireballLineText(
                          'Search',
                          style: TextStyle(
                            fontSize: isTablet ? 27 : 31,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Remote',
                        onPressed: () => context.push('/remote'),
                        icon: Icon(Icons.cast_rounded,
                            color: Colors.white.withValues(alpha: 0.78)),
                      ),
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: () => context.push('/settings'),
                        icon: Icon(Icons.settings_rounded,
                            color: Colors.white.withValues(alpha: 0.78)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'What do you want to play?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 50,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(FireballTokens.radiusMd),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded,
                            size: 20, color: Colors.black87),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: controller,
                            onChanged: (v) {
                              query.value = v;
                              selectedGenre.value = null;
                            },
                            style: const TextStyle(
                                fontSize: 15,
                                color: Colors.black87,
                                fontWeight: FontWeight.w600),
                            decoration: const InputDecoration(
                              hintText: 'Songs, artists, albums...',
                              hintStyle: TextStyle(color: Colors.black45),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        if (query.value.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.cancel_rounded,
                                size: 18, color: Colors.black54),
                            onPressed: () {
                              controller.clear();
                              query.value = '';
                              results.value = [];
                              selectedGenre.value = null;
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (isSearching) ...[
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  itemCount: _searchFilters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final f = _searchFilters[i];
                    final selected = selectedFilter.value == f;
                    return InkWell(
                      borderRadius: BorderRadius.circular(999),
                      hoverColor: Colors.white.withValues(alpha: 0.08),
                      splashColor: Colors.white.withValues(alpha: 0.10),
                      highlightColor: Colors.white.withValues(alpha: 0.06),
                      onTap: () => selectedFilter.value = f,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.white.withValues(alpha: 0.14)
                              : FireballTokens.blackElevated,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: selected
                                ? Colors.white.withValues(alpha: 0.18)
                                : Colors.white.withValues(alpha: 0.12),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          f,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: selected ? 0.95 : 0.78),
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: !isSearching
                  ? ListView(
                      padding: EdgeInsets.fromLTRB(
                        0,
                        0,
                        0,
                        shellScrollBottomPadding(context),
                      ),
                      children: [
                        if (trending.value.isNotEmpty &&
                            selectedGenre.value == null) ...[
                          Padding(
                            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 14),
                            child: _SearchPromoBanner(
                              item: trending.value.first,
                              onTap: () async {
                                await playResult(trending.value, 0);
                              },
                            ),
                          ),
                        ],
                        if (recentSearchRows.isNotEmpty &&
                            selectedGenre.value == null) ...[
                          Padding(
                            padding: EdgeInsets.only(left: hPad, bottom: 10),
                            child: Text(
                              'Recent Searches',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                color: Colors.white.withValues(alpha: 0.94),
                              ),
                            ),
                          ),
                          ...List.generate(recentSearchRows.length, (index) {
                            final t = recentSearchRows[index];
                            return Padding(
                              padding: EdgeInsets.only(
                                left: hPad - 8,
                                right: hPad - 8,
                                bottom: 8,
                              ),
                              child: _searchResultTile(
                                item: {
                                  'id': t.id,
                                  'title': t.title,
                                  'artist': t.artist,
                                  'artwork': t.artwork,
                                  'album': t.album,
                                  'year': t.year,
                                  'url': t.url,
                                  'videoId': t.videoId,
                                  'kind': 'song',
                                },
                                cs: cs,
                                onTap: () async {
                                  ref.read(playerProvider.notifier).playTrackNow(t);
                                },
                                onLongPress: () =>
                                    showTrackOptions(context, ref, t),
                              ),
                            );
                          }),
                          const SizedBox(height: 10),
                        ],
                        Padding(
                          padding: EdgeInsets.only(left: hPad, bottom: 10),
                          child: Text(
                            'Browse All',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                              color: Colors.white.withValues(alpha: 0.36),
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: hPad),
                          child: GridView.builder(
                            itemCount: _genres.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: isTablet ? 3 : 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: isTablet ? 2.45 : 2.2,
                            ),
                            itemBuilder: (context, i) {
                              final color = _browseColors[i % _browseColors.length];
                              return InkWell(
                                borderRadius: BorderRadius.circular(8),
                                hoverColor: Colors.white.withValues(alpha: 0.08),
                                splashColor: Colors.white.withValues(alpha: 0.10),
                                highlightColor: Colors.white.withValues(alpha: 0.06),
                                onTap: () => searchGenre(_genres[i]),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _genres[i],
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                              letterSpacing: -0.2,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          Icons.arrow_outward_rounded,
                                          size: 16,
                                          color: Colors.white.withValues(alpha: 0.9),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: EdgeInsets.only(left: hPad, bottom: 10),
                          child: Text(
                            'Trending Now',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                              color: Colors.white.withValues(alpha: 0.36),
                            ),
                          ),
                        ),
                        ...List.generate(displayList.length, (index) {
                          final item = displayList[index];
                          return Padding(
                            padding:
                                EdgeInsets.only(
                                    left: hPad - 8, right: hPad - 8, bottom: 8),
                            child: _searchResultTile(
                              item: item,
                              cs: cs,
                              onTap: () async => await playResult(displayList, index),
                              onLongPress: () {
                                final t = Track(
                                  id: item['id'] ?? '',
                                  videoId: item['videoId'],
                                  title: item['title'] ?? '—',
                                  artist: item['artist'] ?? '—',
                                  artwork: item['artwork'],
                                  url: item['url'] ?? '',
                                  duration: item['duration'],
                                  album: item['album'],
                                  year: item['year'],
                                );
                                showTrackOptions(context, ref, t);
                              },
                            ),
                          );
                        }),
                      ],
                    )
                  : loading.value
                  ? Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white.withValues(alpha: 0.55),
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : displayList.isEmpty && isSearching
                      ? const FireballEmptyState(
                          onDarkGlass: true,
                          title: 'No results found',
                          subtitle: 'Try another keyword or choose a category.',
                          icon: Icons.music_off_rounded,
                        )
                      : isDesktopWide
                          ? SongsTable(
                              tracks: displayList
                                  .map((item) => Track(
                                        id: item['id'] ?? '',
                                        videoId: item['videoId'],
                                        title: item['title'] ?? '—',
                                        artist: item['artist'] ?? '—',
                                        artwork: item['artwork'],
                                        url: item['url'] ?? '',
                                        duration: item['duration'],
                                        album: item['album'],
                                        year: item['year'],
                                      ))
                                  .toList(),
                              onTrackTap: (index) async =>
                                  await playResult(displayList, index),
                              onTrackLongPress: (track) {
                                showTrackOptions(context, ref, track);
                              },
                            )
                          : ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            hPad - 8,
                            0,
                            hPad - 8,
                            shellScrollBottomPadding(context),
                          ),
                          itemCount: displayList.length,
                          itemBuilder: (context, index) {
                            final item = displayList[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _searchResultTile(
                                item: item,
                                cs: cs,
                                onTap: () async => await playResult(displayList, index),
                                onLongPress: () {
                                  final t = Track(
                                    id: item['id'] ?? '',
                                    videoId: item['videoId'],
                                    title: item['title'] ?? '—',
                                    artist: item['artist'] ?? '—',
                                    artwork: item['artwork'],
                                    url: item['url'] ?? '',
                                    duration: item['duration'],
                                    album: item['album'],
                                    year: item['year'],
                                  );
                                  showTrackOptions(context, ref, t);
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchResultTile({
    required Map<String, dynamic> item,
    required ColorScheme cs,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    final kind = (item['kind'] ?? 'song').toString();
    return Container(
      decoration: BoxDecoration(
        color: FireballTokens.blackElevated,
        borderRadius: BorderRadius.circular(FireballTokens.radiusSm),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 0.6),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        visualDensity: const VisualDensity(
          horizontal: 0,
          vertical: -1,
        ),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: item['artwork'] != null
              ? CachedNetworkImage(
                  imageUrl: item['artwork']!,
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _placeholder(cs),
                )
              : _placeholder(cs),
        ),
        title: Text(
          item['title'] ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Colors.white,
          ),
        ),
        subtitle: Text(
          item['kind'] == 'playlist'
              ? 'Playlist • ${item['artist'] ?? '—'}'
              : item['kind'] == 'artist'
                  ? 'Artist'
                  : item['kind'] == 'album'
                      ? 'Album • ${item['artist'] ?? '—'}'
                      : (item['artist'] ?? '—'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
        ),
        trailing: Icon(Icons.play_circle_fill_rounded,
            color: cs.primary,
            size: (kind == 'playlist' || kind == 'artist' || kind == 'album') ? 23 : 26),
        onTap: onTap,
        onLongPress: onLongPress,
        hoverColor: Colors.white.withValues(alpha: 0.06),
        splashColor: Colors.white.withValues(alpha: 0.09),
        selectedTileColor: Colors.white.withValues(alpha: 0.04),
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) => Container(
        width: 52,
        height: 52,
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.music_note_rounded,
            color: cs.primary.withValues(alpha: 0.4), size: 24),
      );
}

class _SearchPromoBanner extends StatelessWidget {
  const _SearchPromoBanner({
    required this.item,
    required this.onTap,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      hoverColor: Colors.white.withValues(alpha: 0.06),
      splashColor: Colors.white.withValues(alpha: 0.09),
      highlightColor: Colors.white.withValues(alpha: 0.05),
      child: Container(
        height: 92,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              cs.primary.withValues(alpha: 0.75),
              cs.primary.withValues(alpha: 0.35),
              FireballTokens.blackElevated,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Search spotlight',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.84),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item['title']?.toString() ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    item['artist']?.toString() ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.black,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
