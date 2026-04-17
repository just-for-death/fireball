import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/api/fireball_api.dart';
import '../../core/models/track.dart';
import '../../core/store/providers.dart';
import '../../core/utils.dart';
import '../../core/widgets/glass_widgets.dart';

const _genres = [
  'Pop', 'Hip-Hop', 'R&B', 'Rock', 'Electronic',
  'Jazz', 'Classical', 'K-Pop', 'Indie',
];

class SearchScreen extends HookConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    const api = FireballApi();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final query = useState('');
    final results = useState<List<Map<String, dynamic>>>([]);
    final trending = useState<List<Map<String, dynamic>>>([]);
    final loading = useState(false);
    final selectedGenre = useState<String?>(null);
    final controller = useTextEditingController();
    final searchMode = useState<String>('invidious');

    // Load trending on mount
    useEffect(() {
      api.itunesTopSongs('us', limit: 20).then((data) {
        final entries = (data?['feed']?['entry'] as List<dynamic>? ?? []);
        trending.value = entries
            .map((e) => {
                  'id': (e['id']?['attributes']?['im:id'] ?? '').toString(),
                  'title': e['im:name']?['label'] ?? '—',
                  'artist': e['im:artist']?['label'] ?? '—',
                  'artwork': e['im:image']?[2]?['label'],
                  'url': extractItunesUrl(e['link']),
                })
            .toList()
            .cast();
      }).catchError((_) {});
      return null;
    }, const []);

    // Debounced search
    useEffect(() {
      if (query.value.trim().isEmpty) {
        results.value = [];
        return null;
      }
      final timer = Stream.fromFuture(
        Future.delayed(
          const Duration(milliseconds: 450),
          () async {
            loading.value = true;
            try {
              if (searchMode.value == 'invidious') {
                final instance = settings.invidiousInstance;
                if (instance.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Please configure an Invidious instance in Settings')),
                    );
                  }
                  loading.value = false;
                  results.value = [];
                  return;
                }

                final tracks = await api.invidiousSearch(query.value,
                    instanceUrl: instance);
                results.value = tracks
                    .map((t) => {
                          'id': t.id,
                          'videoId': t.videoId,
                          'title': t.title,
                          'artist': t.artist,
                          'artwork': t.artwork,
                          'duration': t.duration,
                        })
                    .toList()
                    .cast();
              } else {
                final data = await api.itunesSearch(query.value);
                results.value = ((data['results'] as List<dynamic>? ?? [])
                      .map((t) => {
                            'id': t['trackId']?.toString() ?? '',
                            'title': t['trackName'] ?? '—',
                            'artist': t['artistName'] ?? '—',
                            'artwork': (t['artworkUrl100'] as String?)
                                ?.replaceAll('100x100bb', '400x400bb'),
                            'url': t['previewUrl'],
                          })
                      .toList())
                    .cast();
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Search failed: $e')),
                );
              }
              results.value = [];
            } finally {
              loading.value = false;
            }
          },
        ),
      ).listen((_) {});
      return timer.cancel;
    }, [query.value, searchMode.value]);

    Future<void> searchGenre(String genre) async {
      selectedGenre.value = genre;
      query.value = '';
      controller.clear();
      loading.value = true;
      try {
        final data = await api.itunesSearch('$genre music', limit: 30);
        results.value = ((data['results'] as List<dynamic>? ?? [])
              .map((t) => {
                    'id': t['trackId']?.toString() ?? '',
                    'title': t['trackName'] ?? '—',
                    'artist': t['artistName'] ?? '—',
                    'artwork': (t['artworkUrl100'] as String?)
                        ?.replaceAll('100x100bb', '400x400bb'),
                    'url': t['previewUrl'],
                  })
              .toList())
            .cast();
      } finally {
        loading.value = false;
      }
    }

    void playResult(List<Map<String, dynamic>> source, int index) {
      final tracks = source
          .map((r) => Track(
                id: r['id'] ?? '',
                videoId: r['videoId'],
                title: r['title'] ?? '—',
                artist: r['artist'] ?? '—',
                artwork: r['artwork'],
                url: r['url'] ?? '',
                duration: r['duration'],
              ))
          .toList();
      ref.read(playerProvider.notifier).setQueue(tracks);
      ref.read(playerProvider.notifier).playIndex(index);
    }

    final isSearching =
        query.value.trim().isNotEmpty || selectedGenre.value != null;
    final displayList = isSearching ? results.value : trending.value;

    return PremiumBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Search',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -1,
                        ),
                      ),
                      const Spacer(),
                      _SearchModeToggle(
                        mode: searchMode.value,
                        onChanged: (m) => searchMode.value = m,
                        isDark: isDark,
                        cs: cs,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GlassCard(
                    padding: EdgeInsets.zero,
                    borderRadius: BorderRadius.circular(16),
                    opacity: 0.08,
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded,
                              size: 20,
                              color: Colors.white.withValues(alpha: 0.5)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: controller,
                              onChanged: (v) {
                                query.value = v;
                                selectedGenre.value = null;
                              },
                              style: const TextStyle(
                                  fontSize: 15, color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Songs, artists, albums...',
                                hintStyle: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.3)),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          if (query.value.isNotEmpty)
                            IconButton(
                              icon: Icon(Icons.cancel_rounded,
                                  size: 18,
                                  color:
                                      Colors.white.withValues(alpha: 0.5)),
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
                  ),
                ],
              ),
            ),

            if (!isSearching) ...[
              Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 12),
                child: Text(
                  'BROWSE BY GENRE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _genres.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    return GlassPill(
                      label: _genres[i],
                      selected: selectedGenre.value == _genres[i],
                      onTap: () => searchGenre(_genres[i]),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 12),
                child: Text(
                  'TRENDING NOW',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],

            Expanded(
              child: loading.value
                  ? Center(
                      child: CircularProgressIndicator(color: cs.primary))
                  : displayList.isEmpty && isSearching
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.music_off_rounded,
                                  size: 52,
                                  color:
                                      Colors.white.withValues(alpha: 0.2)),
                              const SizedBox(height: 12),
                              Text(
                                'No results found',
                                style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.4)),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 160),
                          itemCount: displayList.length,
                          itemBuilder: (context, index) {
                            final item = displayList[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: GlassCard(
                                opacity: 0.04,
                                borderRadius: BorderRadius.circular(16),
                                child: ListTile(
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 2),
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: item['artwork'] != null
                                        ? CachedNetworkImage(
                                            imageUrl: item['artwork']!,
                                            width: 48,
                                            height: 48,
                                            fit: BoxFit.cover,
                                            errorWidget: (_, __, ___) =>
                                                _placeholder(cs),
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
                                    item['artist'] ?? '—',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white
                                            .withValues(alpha: 0.5)),
                                  ),
                                  trailing: Icon(
                                      Icons.play_circle_fill_rounded,
                                      color: cs.primary,
                                      size: 28),
                                  onTap: () =>
                                      playResult(displayList, index),
                                ),
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

  Widget _placeholder(ColorScheme cs) => Container(
        width: 52,
        height: 52,
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.music_note_rounded,
            color: cs.primary.withValues(alpha: 0.4), size: 24),
      );
}

class _SearchModeToggle extends StatelessWidget {
  const _SearchModeToggle({
    required this.mode,
    required this.onChanged,
    required this.isDark,
    required this.cs,
  });

  final String mode;
  final void Function(String) onChanged;
  final bool isDark;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleBtn(
            label: 'YouTube',
            isActive: mode == 'invidious',
            onTap: () => onChanged('invidious'),
            cs: cs,
            isDark: isDark,
          ),
          _ToggleBtn(
            label: 'iTunes',
            isActive: mode == 'itunes',
            onTap: () => onChanged('itunes'),
            cs: cs,
            isDark: isDark,
          ),
        ],
      ),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  const _ToggleBtn({
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.cs,
    required this.isDark,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final ColorScheme cs;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isActive
                ? cs.onPrimary
                : (isDark ? Colors.white38 : Colors.black38),
          ),
        ),
      ),
    );
  }
}
