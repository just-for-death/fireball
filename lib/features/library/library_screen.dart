import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/models/track.dart';
import '../../core/store/providers.dart';
import '../../core/ui/shell_content_insets.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/glass_widgets.dart';
import '../../core/widgets/track_options_sheet.dart';
import '../../core/audio/download_manager.dart';

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
            ? _buildTabletLayout(
                context, ref, library, cs, isDark, playerState, tab)
            : _buildPhoneLayout(
                context, ref, library, cs, isDark, playerState, tab),
      ),
    );
  }

  // ── Phone layout: header + horizontal pills + content ───────────────────────
  Widget _buildPhoneLayout(
    BuildContext context,
    WidgetRef ref,
    LibraryData library,
    ColorScheme cs,
    bool isDark,
    PlayerState playerState,
    ValueNotifier<_LibTab> tab,
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
    BuildContext context,
    WidgetRef ref,
    LibraryData library,
    ColorScheme cs,
    bool isDark,
    PlayerState playerState,
    ValueNotifier<_LibTab> tab,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
            ref.read(playerProvider.notifier).setQueue(library.favorites);
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
          onLongPress: (track) => showTrackOptions(context, ref, track),
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
            void openDetail() => _openPlaylistDetail(context, ref, pl, cs);
            void openMenu() => _showPlaylistMenu(context, ref, pl);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassCard(
                opacity: 0.05,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: openDetail,
                  onLongPress: openMenu,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2),
                    child: ListTile(
                      leading: _PlaylistArt(playlist: pl, size: 50, cs: cs),
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
                        '${pl.videos.length} track${pl.videos.length == 1 ? '' : 's'}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5)),
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.more_vert_rounded,
                            color: Colors.white.withValues(alpha: 0.6),
                            size: 22),
                        onPressed: openMenu,
                        tooltip: 'More options',
                      ),
                    ),
                  ),
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
            return GestureDetector(
              onTap: () {
                context.push('/artist?name=${Uri.encodeComponent(artist.name)}');
              },
              child: Column(
                children: [
                  ClipOval(
                    child: artist.artwork != null
                        ? CachedNetworkImage(
                            imageUrl: artist.artwork!,
                            width: 110,
                            height: 110,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _circularPlaceholder(cs),
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
              ),
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
                  ref.read(playerProvider.notifier).setQueue(album.tracks!);
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
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
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

  // ── Playlist: 3-dot / long-press menu ───────────────────────────────────────
  void _showPlaylistMenu(BuildContext context, WidgetRef ref, Playlist pl) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08), width: 0.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Playlist name
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      Icon(Icons.queue_music_rounded,
                          color: cs.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          pl.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white12),
                // Actions
                if (pl.videos.isNotEmpty) ...[
                  _menuItem(
                    ctx,
                    icon: Icons.play_arrow_rounded,
                    label: 'Play all',
                    onTap: () {
                      Navigator.pop(ctx);
                      ref
                          .read(playerProvider.notifier)
                          .setQueue(pl.videos);
                      ref.read(playerProvider.notifier).playIndex(0);
                    },
                  ),
                  _menuItem(
                    ctx,
                    icon: Icons.playlist_add_rounded,
                    label: 'Add all to queue',
                    onTap: () {
                      Navigator.pop(ctx);
                      for (final t in pl.videos) {
                        ref.read(playerProvider.notifier).addToQueue(t);
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Added ${pl.videos.length} tracks to queue'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  _menuItem(
                    ctx,
                    icon: Icons.skip_next_rounded,
                    label: 'Play next',
                    onTap: () {
                      Navigator.pop(ctx);
                      // Insert all tracks right after current position
                      final reversed = pl.videos.reversed.toList();
                      for (final t in reversed) {
                        ref.read(playerProvider.notifier).playNext(t);
                      }
                    },
                  ),
                ],
                _menuItem(
                  ctx,
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete playlist',
                  color: Colors.redAccent,
                  onTap: () async {
                    Navigator.pop(ctx);
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
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _menuItem(
    BuildContext ctx, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final c = color ?? Colors.white;
    return ListTile(
      leading: Icon(icon, color: c, size: 22),
      title: Text(label,
          style: TextStyle(
              color: c, fontWeight: FontWeight.w500, fontSize: 14)),
      onTap: onTap,
    );
  }

  // ── Playlist detail sheet ───────────────────────────────────────────────────
  void _openPlaylistDetail(
      BuildContext context, WidgetRef ref, Playlist pl, ColorScheme cs) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PlaylistDetailSheet(pl: pl, ref: ref, cs: cs),
    );
  }
}

class _TrackList extends ConsumerWidget {
  const _TrackList({
    required this.tracks,
    required this.cs,
    required this.isDark,
    required this.emptyMessage,
    required this.emptyIcon,
    required this.onTap,
    required this.trailing,
    this.onLongPress,
  });
  final List<Track> tracks;
  final ColorScheme cs;
  final bool isDark;
  final String emptyMessage;
  final IconData emptyIcon;
  final void Function(int) onTap;
  final Widget Function(Track) trailing;
  final void Function(Track)? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadedIds = ref.watch(downloadManagerProvider).downloadedIds;
    
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
          title: Row(
            children: [
              Expanded(
                child: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isDark ? Colors.white : cs.onSurface,
                  ),
                ),
              ),
              if (downloadedIds.contains(track.effectiveId))
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.offline_pin_rounded,
                      size: 14, color: cs.primary),
                ),
            ],
          ),
          subtitle: Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          trailing: trailing(track),
          onTap: () => onTap(i),
          onLongPress: onLongPress != null ? () => onLongPress!(track) : null,
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

// ── Playlist Artwork ──────────────────────────────────────────────────────────
class _PlaylistArt extends StatelessWidget {
  const _PlaylistArt({
    required this.playlist,
    required this.size,
    required this.cs,
  });
  final Playlist playlist;
  final double size;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    // Extract unique artworks from tracks (limit search to first 50 to avoid perf hits on massive playlists)
    final uniqueArts = <String>[];
    final searchLimit = playlist.videos.length > 50 ? 50 : playlist.videos.length;
    for (int i = 0; i < searchLimit; i++) {
      final track = playlist.videos[i];
      if (track.artwork != null && track.artwork!.isNotEmpty && !uniqueArts.contains(track.artwork)) {
        uniqueArts.add(track.artwork!);
        if (uniqueArts.length >= 4) break;
      }
    }

    if (uniqueArts.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.queue_music_rounded, color: cs.primary, size: size * 0.5),
      );
    }

    if (uniqueArts.length < 4) {
      // Just show the first one
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: uniqueArts.first,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _fallback(),
        ),
      );
    }

    // 2x2 grid
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _img(uniqueArts[0])),
                  Expanded(child: _img(uniqueArts[1])),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _img(uniqueArts[2])),
                  Expanded(child: _img(uniqueArts[3])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _img(String url) => CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _fallback(),
      );

  Widget _fallback() => Container(
        color: cs.primary.withValues(alpha: 0.15),
        child: Icon(Icons.music_note_rounded, color: cs.primary, size: size * 0.4),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Playlist detail sheet — shows all tracks, tap to play, long press for options
// ─────────────────────────────────────────────────────────────────────────────
class _PlaylistDetailSheet extends StatelessWidget {
  const _PlaylistDetailSheet({
    required this.pl,
    required this.ref,
    required this.cs,
  });
  final Playlist pl;
  final WidgetRef ref;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141416) : const Color(0xFFF2F2F7),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.07),
              width: 0.5,
            ),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
                child: Row(
                  children: [
                    Icon(Icons.queue_music_rounded,
                        color: cs.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        pl.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    // Play all
                    if (pl.videos.isNotEmpty)
                      IconButton(
                        tooltip: 'Play all',
                        icon: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 22),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          ref
                              .read(playerProvider.notifier)
                              .setQueue(pl.videos);
                          ref.read(playerProvider.notifier).playIndex(0);
                        },
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
                child: Row(
                  children: [
                    Text(
                      '${pl.videos.length} track${pl.videos.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              // Track list
              Expanded(
                child: pl.videos.isEmpty
                    ? Center(
                        child: Text(
                          'No tracks yet.\nAdd songs from Search or Home.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.only(top: 4, bottom: 80),
                        itemCount: pl.videos.length,
                        itemBuilder: (context, i) {
                          final t = pl.videos[i];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 2),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: t.artwork != null
                                  ? CachedNetworkImage(
                                      imageUrl: t.artwork!,
                                      width: 46,
                                      height: 46,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) =>
                                          _trackPlaceholder(cs),
                                    )
                                  : _trackPlaceholder(cs),
                            ),
                            title: Text(
                              t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isDark ? Colors.white : cs.onSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              t.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 12),
                            ),
                            trailing: IconButton(
                              icon: Icon(Icons.more_vert_rounded,
                                  color: Colors.white.withValues(alpha: 0.45),
                                  size: 20),
                              onPressed: () =>
                                  showTrackOptions(context, ref, t),
                              tooltip: 'More options',
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              ref
                                  .read(playerProvider.notifier)
                                  .setQueue(pl.videos);
                              ref
                                  .read(playerProvider.notifier)
                                  .playIndex(i);
                            },
                            onLongPress: () =>
                                showTrackOptions(context, ref, t),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _trackPlaceholder(ColorScheme cs) => Container(
        width: 46,
        height: 46,
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.music_note_rounded,
            color: cs.primary.withValues(alpha: 0.4), size: 22),
      );
}
