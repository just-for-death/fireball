import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/models/track.dart';
import '../../core/store/providers.dart';
import '../../core/ui/shell_content_insets.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/glass_widgets.dart';

enum _LibTab { favorites, playlists, artists, albums }

class LibraryScreen extends HookConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(localStoreProvider);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final playerState = ref.watch(playerProvider);

    final tab = useState(_LibTab.favorites);

    // Keep player favorites in sync with local store.
    // Deferred via Future.microtask to avoid modifying a provider during build.
    useEffect(() {
      Future.microtask(() {
        if (ref.context.mounted) {
          ref.read(playerProvider.notifier).setFavorites(library.favorites);
        }
      });
      return null;
    }, [library.favorites]);

    final isTablet = MediaQuery.sizeOf(context).width >= 600;

    return PremiumBackground(
      child: SafeArea(
        bottom: false,
        child: isTablet
            ? _buildTabletLayout(context, ref, library, cs, isDark,
                playerState, tab)
            : _buildPhoneLayout(context, ref, library, cs, isDark,
                playerState, tab),
      ),
    );
  }

  // ── Phone layout: header + horizontal pills + content ───────────────────────
  Widget _buildPhoneLayout(
    BuildContext context, WidgetRef ref,
    LibraryData library, ColorScheme cs, bool isDark,
    PlayerState playerState, ValueNotifier<_LibTab> tab,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Your Library',
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
              ),
              if (tab.value == _LibTab.playlists)
                GlassCard(
                  padding: EdgeInsets.zero,
                  borderRadius: BorderRadius.circular(12),
                  child: IconButton(
                    icon: Icon(Icons.add_rounded, color: cs.primary),
                    onPressed: () => _createPlaylistDialog(context, ref),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            children: _LibTab.values
                .map((t) => Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GlassPill(
                        label: _tabLabel(t),
                        selected: tab.value == t,
                        onTap: () => tab.value = t,
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _buildTabContent(
              context, ref, tab.value, library, cs, isDark, playerState),
        ),
      ],
    );
  }

  // ── Tablet layout: sidebar + content ─────────────────────────────────────────
  Widget _buildTabletLayout(
    BuildContext context, WidgetRef ref,
    LibraryData library, ColorScheme cs, bool isDark,
    PlayerState playerState, ValueNotifier<_LibTab> tab,
  ) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        // Sidebar
        SizedBox(
          width: 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                child: Text(
                  'Your Library',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  children: _LibTab.values.map((t) {
                    final selected = tab.value == t;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => tab.value = t,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: selected
                              ? cs.primary.withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _tabIcon(t),
                              size: 20,
                              color: selected
                                  ? cs.primary
                                  : (isDarkMode
                                      ? Colors.white.withValues(alpha: 0.55)
                                      : Colors.black.withValues(alpha: 0.45)),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _tabLabelShort(t),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected
                                    ? cs.primary
                                    : (isDarkMode
                                        ? Colors.white.withValues(alpha: 0.75)
                                        : Colors.black.withValues(alpha: 0.65)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              if (tab.value == _LibTab.playlists)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                  child: GlassCard(
                    padding: EdgeInsets.zero,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      leading: Icon(Icons.add_rounded, color: cs.primary),
                      title: Text('New Playlist',
                          style: TextStyle(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      onTap: () => _createPlaylistDialog(context, ref),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Divider
        VerticalDivider(
          width: 1,
          thickness: 0.5,
          color: Colors.white.withValues(alpha: 0.10),
        ),
        // Content
        Expanded(
          child: _buildTabContent(
              context, ref, tab.value, library, cs, isDark, playerState),
        ),
      ],
    );
  }

  String _tabLabel(_LibTab t) {
    switch (t) {
      case _LibTab.favorites:
        return '♥ Favorites';
      case _LibTab.playlists:
        return '≡ Playlists';
      case _LibTab.artists:
        return '👤 Artists';
      case _LibTab.albums:
        return '💿 Albums';
    }
  }

  String _tabLabelShort(_LibTab t) {
    switch (t) {
      case _LibTab.favorites:
        return 'Favorites';
      case _LibTab.playlists:
        return 'Playlists';
      case _LibTab.artists:
        return 'Artists';
      case _LibTab.albums:
        return 'Albums';
    }
  }

  IconData _tabIcon(_LibTab t) {
    switch (t) {
      case _LibTab.favorites:
        return Icons.favorite_rounded;
      case _LibTab.playlists:
        return Icons.queue_music_rounded;
      case _LibTab.artists:
        return Icons.person_rounded;
      case _LibTab.albums:
        return Icons.album_rounded;
    }
  }

  Widget _buildTabContent(
    BuildContext context,
    WidgetRef ref,
    _LibTab tab,
    LibraryData library,
    ColorScheme cs,
    bool isDark,
    PlayerState playerState,
  ) {
    switch (tab) {
      case _LibTab.favorites:
        return _TrackList(
          tracks: library.favorites,
          cs: cs,
          isDark: isDark,
          emptyMessage: 'No favorites yet.\nHeart a track while it plays.',
          emptyIcon: Icons.favorite_border_rounded,
          onTap: (index) {
            ref
                .read(playerProvider.notifier)
                .setQueue(library.favorites);
            ref.read(playerProvider.notifier).playIndex(index);
          },
          trailing: (track) => IconButton(
            icon: const Icon(Icons.favorite_rounded,
                color: Colors.redAccent, size: 22),
            onPressed: () async {
              await ref
                  .read(localStoreProvider.notifier)
                  .deleteFavorite(track.effectiveId);
              ref
                  .read(playerProvider.notifier)
                  .removeFavorite(track.effectiveId);
            },
          ),
        );

      case _LibTab.playlists:
        if (library.playlists.isEmpty) {
          return const FireballEmptyState(
            onDarkGlass: true,
            title: 'No playlists yet',
            subtitle: 'Tap + to create one.',
            icon: Icons.queue_music_rounded,
          );
        }
        return ListView.builder(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            shellScrollBottomPadding(context),
          ),
          itemCount: library.playlists.length,
          itemBuilder: (context, i) {
            final pl = library.playlists[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassCard(
                opacity: 0.05,
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  leading: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.queue_music_rounded,
                        color: cs.primary),
                  ),
                  title: Text(
                    pl.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: Text(
                    '${pl.videos.length} tracks',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline_rounded,
                        color: Colors.redAccent.withValues(alpha: 0.7),
                        size: 20),
                    onPressed: () async {
                      // Clear queue first if we're currently playing from this playlist
                      final player = ref.read(playerProvider);
                      final currentId = player.currentTrack?.effectiveId;
                      if (pl.videos.any((t) => t.effectiveId == currentId)) {
                        ref.read(playerProvider.notifier).setQueue([]);
                      }
                      await ref
                          .read(localStoreProvider.notifier)
                          .deletePlaylist(pl.id);
                    },
                  ),
                  onTap: () {
                    if (pl.videos.isNotEmpty) {
                      ref
                          .read(playerProvider.notifier)
                          .setQueue(pl.videos);
                      ref.read(playerProvider.notifier).playIndex(0);
                    }
                  },
                ),
              ),
            );
          },
        );

      case _LibTab.artists:
        if (library.artists.isEmpty) {
          return const FireballEmptyState(
            onDarkGlass: true,
            title: 'No artists saved yet',
            icon: Icons.person_outline_rounded,
          );
        }
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            shellScrollBottomPadding(context),
          ),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 160,
            childAspectRatio: 0.9,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: library.artists.length,
          itemBuilder: (context, i) {
            final artist = library.artists[i];
            return Column(
              children: [
                ClipOval(
                  child: artist.artwork != null
                      ? CachedNetworkImage(
                          imageUrl: artist.artwork!,
                          width: 110,
                          height: 110,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              _circularPlaceholder(cs),
                        )
                      : _circularPlaceholder(cs),
                ),
                const SizedBox(height: 8),
                Text(
                  artist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : cs.onSurface,
                  ),
                ),
              ],
            );
          },
        );

      case _LibTab.albums:
        if (library.albums.isEmpty) {
          return const FireballEmptyState(
            onDarkGlass: true,
            title: 'No albums saved yet',
            icon: Icons.album_rounded,
          );
        }
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            shellScrollBottomPadding(context),
          ),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            childAspectRatio: 0.75,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: library.albums.length,
          itemBuilder: (context, i) {
            final album = library.albums[i];
            return GestureDetector(
              onTap: () {
                if (album.tracks != null && album.tracks!.isNotEmpty) {
                  ref
                      .read(playerProvider.notifier)
                      .setQueue(album.tracks!);
                  ref.read(playerProvider.notifier).playIndex(0);
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: album.artwork != null
                        ? CachedNetworkImage(
                            imageUrl: album.artwork!,
                            width: double.infinity,
                            height: 130,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _rectPlaceholder(cs),
                          )
                        : _rectPlaceholder(cs),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isDark ? Colors.white : cs.onSurface,
                    ),
                  ),
                  Text(
                    album.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            );
          },
        );
    }
  }

  Future<void> _createPlaylistDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final ctrl = TextEditingController();
    try {
      final title = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('New Playlist'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Playlist name'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                child: const Text('Create')),
          ],
        ),
      );
      if (title != null && title.trim().isNotEmpty) {
        await ref
            .read(localStoreProvider.notifier)
            .createPlaylist(title.trim());
      }
    } finally {
      ctrl.dispose();
    }
  }

  Widget _circularPlaceholder(ColorScheme cs) => Container(
        width: 110,
        height: 110,
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.person_rounded,
            color: cs.primary.withValues(alpha: 0.4), size: 40),
      );

  Widget _rectPlaceholder(ColorScheme cs) => Container(
        width: double.infinity,
        height: 130,
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.album_rounded,
            color: cs.primary.withValues(alpha: 0.4), size: 40),
      );
}

class _TrackList extends StatelessWidget {
  const _TrackList({
    required this.tracks,
    required this.cs,
    required this.isDark,
    required this.emptyMessage,
    required this.emptyIcon,
    required this.onTap,
    required this.trailing,
  });
  final List<Track> tracks;
  final ColorScheme cs;
  final bool isDark;
  final String emptyMessage;
  final IconData emptyIcon;
  final void Function(int) onTap;
  final Widget Function(Track) trailing;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      final parts = emptyMessage.split('\n');
      return FireballEmptyState(
        title: parts.first,
        subtitle: parts.length > 1 ? parts.sublist(1).join('\n') : null,
        icon: emptyIcon,
        onDarkGlass: true,
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(bottom: shellScrollBottomPadding(context)),
      itemCount: tracks.length,
      itemBuilder: (context, i) {
        final track = tracks[i];
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: track.artwork != null
                ? CachedNetworkImage(
                    imageUrl: track.artwork!,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _placeholder(cs),
                  )
                : _placeholder(cs),
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: isDark ? Colors.white : cs.onSurface,
            ),
          ),
          subtitle: Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          trailing: trailing(track),
          onTap: () => onTap(i),
        );
      },
    );
  }

  Widget _placeholder(ColorScheme cs) => Container(
        width: 50,
        height: 50,
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.music_note_rounded,
            color: cs.primary.withValues(alpha: 0.4), size: 22),
      );
}
