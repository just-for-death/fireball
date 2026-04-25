import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/api/fireball_api.dart';
import '../../core/models/models.dart';
import '../../core/models/track.dart';
import '../../core/store/providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Route entry point: /artist?name=XYZ
// ─────────────────────────────────────────────────────────────────────────────
class ArtistScreen extends HookConsumerWidget {
  const ArtistScreen({super.key, required this.artistName});
  final String artistName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = const FireballApi();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // State
    final artistData = useState<Map<String, dynamic>?>(null);
    final topSongs = useState<List<Map<String, dynamic>>>([]);
    final albums = useState<List<Map<String, dynamic>>>([]);
    final isLoading = useState(true);
    final error = useState<String?>(null);

    // Fetch everything on mount
    useEffect(() {
      () async {
        try {
          isLoading.value = true;
          error.value = null;

          final artist = await api.itunesFindArtist(artistName);
          artistData.value = artist;

          if (artist != null) {
            final id = artist['artistId'] as int?;
            if (id != null) {
              final results = await Future.wait<List<Map<String, dynamic>>>([
                api.itunesArtistTopSongs(id, limit: 20),
                api.itunesArtistAlbums(id, limit: 20),
              ]);
              topSongs.value = results[0];
              albums.value = results[1];
            }
          }
        } catch (e) {
          error.value = 'Failed to load artist: $e';
        } finally {
          isLoading.value = false;
        }
      }();
      return null;
    }, const []);

    final artworkUrl = _bestArtistArt(topSongs.value, albums.value);
    final genre = artistData.value?['primaryGenreName'] as String?;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D10),
      body: isLoading.value
          ? const Center(child: CircularProgressIndicator())
          : error.value != null
              ? _ErrorState(message: error.value!, artistName: artistName)
              : CustomScrollView(
                  slivers: [
                    // ── Hero header ───────────────────────────────────────────
                    SliverAppBar(
                      expandedHeight: 280,
                      pinned: true,
                      backgroundColor: const Color(0xFF0D0D10),
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white),
                        onPressed: () => context.pop(),
                      ),
                      flexibleSpace: FlexibleSpaceBar(
                        collapseMode: CollapseMode.parallax,
                        background: _ArtistHero(
                          artworkUrl: artworkUrl,
                          artistName: artistName,
                          genre: genre,
                          cs: cs,
                          isDark: isDark,
                        ),
                      ),
                    ),

                    // ── Top Songs header ──────────────────────────────────────
                    if (topSongs.value.isNotEmpty) ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                        sliver: SliverToBoxAdapter(
                          child: _SectionHeader(
                            icon: Icons.music_note_rounded,
                            label: 'Top Songs',
                            cs: cs,
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverList.builder(
                          itemCount: topSongs.value.length,
                          itemBuilder: (context, i) => _SongTile(
                            index: i + 1,
                            song: topSongs.value[i],
                            cs: cs,
                            ref: ref,
                          ),
                        ),
                      ),
                    ],

                    // ── Albums header ─────────────────────────────────────────
                    if (albums.value.isNotEmpty) ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 32, 20, 8),
                        sliver: SliverToBoxAdapter(
                          child: _SectionHeader(
                            icon: Icons.album_rounded,
                            label: 'Albums',
                            cs: cs,
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 180,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.75,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => _AlbumCard(
                              album: albums.value[i],
                              cs: cs,
                              ref: ref,
                              artistName: artistName,
                            ),
                            childCount: albums.value.length,
                          ),
                        ),
                      ),
                    ],

                    // ── Bottom padding ────────────────────────────────────────
                    const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
                  ],
                ),
    );
  }

  /// Pick the best available artwork URL from any song or album result.
  static String? _bestArtistArt(
    List<Map<String, dynamic>> songs,
    List<Map<String, dynamic>> albums,
  ) {
    for (final a in albums) {
      final url = a['artworkUrl100'] as String?;
      if (url != null && url.isNotEmpty) {
        return url.replaceAll('100x100bb', '600x600bb');
      }
    }
    for (final s in songs) {
      final url = s['artworkUrl100'] as String?;
      if (url != null && url.isNotEmpty) {
        return url.replaceAll('100x100bb', '600x600bb');
      }
    }
    return null;
  }
}

// ── Hero ──────────────────────────────────────────────────────────────────────
class _ArtistHero extends ConsumerWidget {
  const _ArtistHero({
    required this.artworkUrl,
    required this.artistName,
    required this.genre,
    required this.cs,
    required this.isDark,
  });

  final String? artworkUrl;
  final String artistName;
  final String? genre;
  final ColorScheme cs;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(localStoreProvider);
    final isFollowing = library.artists
        .any((a) => a.name.toLowerCase() == artistName.toLowerCase());

    return Stack(
      fit: StackFit.expand,
      children: [
        // Background image (blurred)
        if (artworkUrl != null)
          CachedNetworkImage(
            imageUrl: artworkUrl!,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => _gradientBg(cs),
          )
        else
          _gradientBg(cs),

        // Dark overlay + blur
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.2),
                    Colors.black.withValues(alpha: 0.75),
                    const Color(0xFF0D0D10),
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
            ),
          ),
        ),

        // Center: circular avatar + name
        Positioned(
          bottom: 24,
          left: 24,
          right: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (artworkUrl != null)
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: artworkUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Icon(Icons.person_rounded,
                          size: 40, color: cs.primary),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      artistName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      if (isFollowing) {
                        final a = library.artists.firstWhere((a) =>
                            a.name.toLowerCase() == artistName.toLowerCase());
                        await ref
                            .read(localStoreProvider.notifier)
                            .deleteArtist(a.artistId);
                      } else {
                        // Resolve real artist data + artwork before saving —
                        // avoids the thumbnail-less optimistic save.
                        String finalId = artistName;
                        String finalName = artistName;
                        // Prefer already-loaded artwork (computed at build time)
                        String? artwork = artworkUrl;

                        try {
                          final data = await const FireballApi()
                              .itunesFindArtist(artistName);
                          if (data != null) {
                            finalId =
                                data['artistId']?.toString() ?? artistName;
                            finalName =
                                data['artistName']?.toString() ?? artistName;

                            // If artwork still null, fetch from first album
                            if (artwork == null) {
                              final id = data['artistId'] as int?;
                              if (id != null) {
                                final albumResults = await const FireballApi()
                                    .itunesArtistAlbums(id, limit: 1);
                                if (albumResults.isNotEmpty) {
                                  final url = albumResults
                                      .first['artworkUrl100'] as String?;
                                  if (url != null && url.isNotEmpty) {
                                    artwork = url.replaceAll(
                                        '100x100bb', '600x600bb');
                                  }
                                }
                              }
                            }
                          }
                        } catch (_) {
                          // Network failure – save with whatever is available
                        }

                        if (context.mounted) {
                          await ref
                              .read(localStoreProvider.notifier)
                              .addArtist(Artist(
                                artistId: finalId,
                                name: finalName,
                                artwork: artwork,
                              ));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Following $finalName'),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                        }
                      }
                    },
                    icon: Icon(
                      isFollowing
                          ? Icons.check_rounded
                          : Icons.person_add_rounded,
                      size: 16,
                      color: isFollowing ? cs.primary : Colors.white,
                    ),
                    label: Text(
                      isFollowing ? 'Following' : 'Follow',
                      style: TextStyle(
                        color: isFollowing ? cs.primary : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: isFollowing
                            ? cs.primary
                            : Colors.white.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 0),
                    ),
                  ),
                ],
              ),
              if (genre != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: cs.primary.withValues(alpha: 0.4), width: 0.5),
                  ),
                  child: Text(
                    genre!,
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _gradientBg(ColorScheme cs) => Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.4,
            colors: [
              cs.primary.withValues(alpha: 0.35),
              const Color(0xFF0D0D10),
            ],
          ),
        ),
      );
}

// ── Section header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.icon, required this.label, required this.cs});
  final IconData icon;
  final String label;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

// ── Song tile ─────────────────────────────────────────────────────────────────
class _SongTile extends StatelessWidget {
  const _SongTile({
    required this.index,
    required this.song,
    required this.cs,
    required this.ref,
  });
  final int index;
  final Map<String, dynamic> song;
  final ColorScheme cs;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final title = song['trackName'] as String? ?? '—';
    final artist = song['artistName'] as String? ?? '—';
    final album = song['collectionName'] as String? ?? '';
    final artUrl = (song['artworkUrl100'] as String? ?? '')
        .replaceAll('100x100bb', '300x300bb');
    final previewUrl = song['previewUrl'] as String?;
    final trackId = song['trackId']?.toString() ?? '';
    final yearStr = (song['releaseDate'] as String? ?? '').split('-').first;
    final year = yearStr.length == 4 ? yearStr : null;

    // Build a playable track from the iTunes data
    Track toTrack() => Track(
          id: trackId,
          title: title,
          artist: artist,
          album: album.isNotEmpty ? album : null,
          artwork: artUrl.isNotEmpty ? artUrl : null,
          url: previewUrl ?? '',
          year: year,
        );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          final t = toTrack();
          ref.read(playerProvider.notifier).playTrackNow(t);
          ref.read(localStoreProvider.notifier).addHistory(t);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              // Index
              SizedBox(
                width: 28,
                child: Text(
                  '$index',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: artUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: artUrl,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _placeholder(cs),
                      )
                    : _placeholder(cs),
              ),
              const SizedBox(width: 12),
              // Title + album
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (album.isNotEmpty || year != null)
                      Text(
                        '$album${album.isNotEmpty && year != null ? " • " : ""}${year ?? ""}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              // Add to queue
              IconButton(
                icon: Icon(Icons.add_rounded,
                    size: 22, color: Colors.white.withValues(alpha: 0.5)),
                onPressed: () {
                  ref.read(playerProvider.notifier).addToQueue(toTrack());
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Added "$title" to queue'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) => Container(
        width: 44,
        height: 44,
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.music_note_rounded,
            color: cs.primary.withValues(alpha: 0.5), size: 22),
      );
}

// ── Album card ────────────────────────────────────────────────────────────────
class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    required this.album,
    required this.cs,
    required this.ref,
    required this.artistName,
  });
  final Map<String, dynamic> album;
  final ColorScheme cs;
  final WidgetRef ref;
  final String artistName;

  @override
  Widget build(BuildContext context) {
    final name = album['collectionName'] as String? ?? '—';
    final year = _year(album['releaseDate'] as String?);
    final artUrl = (album['artworkUrl100'] as String? ?? '')
        .replaceAll('100x100bb', '400x400bb');
    final trackCount = album['trackCount'] as int? ?? 0;

    return GestureDetector(
      onTap: () {
        // Navigate to album detail — for now show a snack with the info
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name ($year) • $trackCount tracks'),
            duration: const Duration(seconds: 3),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover art
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: artUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: artUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorWidget: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            year ?? '$trackCount tracks',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.album_rounded,
            color: cs.primary.withValues(alpha: 0.4), size: 36),
      );

  static String? _year(String? date) {
    if (date == null || date.length < 4) return null;
    return date.substring(0, 4);
  }
}

// ── Error state ───────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.artistName});
  final String message;
  final String artistName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D10),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(artistName),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: Colors.white38),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
