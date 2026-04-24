import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../api/fireball_api.dart';
import '../models/models.dart';
import '../models/track.dart';
import '../store/providers.dart';
import '../audio/download_manager.dart';

/// Shows the track context-action bottom sheet.
///
/// Place `onLongPress: () => showTrackOptions(context, ref, track)` on any
/// track tile across the app.
Future<void> showTrackOptions(
  BuildContext context,
  WidgetRef ref,
  Track track,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (ctx) => _TrackOptionsSheet(track: track, ref: ref),
  );
}

class _TrackOptionsSheet extends ConsumerWidget {
  const _TrackOptionsSheet({required this.track, required this.ref});
  final Track track;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef watchRef) {
    final cs = Theme.of(context).colorScheme;
    final player = watchRef.watch(playerProvider);
    final library = watchRef.watch(localStoreProvider);
    final downloadState = watchRef.watch(downloadManagerProvider);
    final isFav = player.isFavorite(track.effectiveId);
    final isFollowingArtist = library.artists
        .any((a) => a.name.toLowerCase() == track.artist.toLowerCase());
    final isDownloaded =
        downloadState.downloadedIds.contains(track.effectiveId);
    final isDownloading =
        downloadState.activeDownloads.contains(track.effectiveId);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Track info header ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  if (track.artwork != null && track.artwork!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        track.artwork!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _ArtworkPlaceholder(cs: cs),
                      ),
                    )
                  else
                    _ArtworkPlaceholder(cs: cs),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Divider(
              color: Colors.white.withValues(alpha: 0.07),
              height: 20,
              indent: 16,
              endIndent: 16,
            ),

            // ── Actions ────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionTile(
                      icon: Icons.play_arrow_rounded,
                      label: 'Play Now',
                      cs: cs,
                      onTap: () {
                        Navigator.pop(context);
                        watchRef
                            .read(playerProvider.notifier)
                            .playTrackNow(track);
                        watchRef
                            .read(localStoreProvider.notifier)
                            .addHistory(track);
                      },
                    ),
                    _ActionTile(
                      icon: Icons.skip_next_rounded,
                      label: 'Play Next',
                      cs: cs,
                      onTap: () {
                        Navigator.pop(context);
                        watchRef.read(playerProvider.notifier).playNext(track);
                      },
                    ),
                    _ActionTile(
                      icon: Icons.add_rounded,
                      label: 'Add to Queue',
                      cs: cs,
                      onTap: () {
                        Navigator.pop(context);
                        watchRef
                            .read(playerProvider.notifier)
                            .addToQueue(track);
                      },
                    ),
                    _ActionTile(
                      icon: isFav
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      label:
                          isFav ? 'Remove from Favorites' : 'Add to Favorites',
                      iconColor: isFav ? Colors.redAccent : null,
                      cs: cs,
                      onTap: () async {
                        Navigator.pop(context);
                        if (isFav) {
                          await watchRef
                              .read(localStoreProvider.notifier)
                              .deleteFavorite(track.effectiveId);
                          watchRef
                              .read(playerProvider.notifier)
                              .removeFavorite(track.effectiveId);
                        } else {
                          await watchRef
                              .read(localStoreProvider.notifier)
                              .addFavorite(track);
                          watchRef
                              .read(playerProvider.notifier)
                              .addFavorite(track);
                        }
                      },
                    ),
                    _ActionTile(
                      icon: isFollowingArtist
                          ? Icons.person_remove_rounded
                          : Icons.person_add_rounded,
                      label: isFollowingArtist
                          ? 'Unfollow Artist'
                          : 'Follow Artist',
                      cs: cs,
                      onTap: () async {
                        Navigator.pop(context);
                        if (isFollowingArtist) {
                          final a = library.artists.firstWhere((a) =>
                              a.name.toLowerCase() ==
                              track.artist.toLowerCase());
                          await watchRef
                              .read(localStoreProvider.notifier)
                              .deleteArtist(a.artistId);
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Following ${track.artist}...'),
                                  duration: const Duration(seconds: 1)),
                            );
                          }
                          final data = await const FireballApi()
                              .itunesFindArtist(track.artist);
                          if (data != null) {
                            final newArtist = Artist(
                              artistId:
                                  data['artistId']?.toString() ?? track.artist,
                              name: data['artistName']?.toString() ??
                                  track.artist,
                              artwork: track.artwork,
                            );
                            await watchRef
                                .read(localStoreProvider.notifier)
                                .addArtist(newArtist);
                          } else {
                            await watchRef
                                .read(localStoreProvider.notifier)
                                .addArtist(Artist(
                                  artistId: track.artist,
                                  name: track.artist,
                                  artwork: track.artwork,
                                ));
                          }
                        }
                      },
                    ),
                    _ActionTile(
                      icon: Icons.playlist_add_rounded,
                      label: 'Add to Playlist…',
                      cs: cs,
                      onTap: () {
                        Navigator.pop(context);
                        _showAddToPlaylist(
                            context, ref, track, library.playlists);
                      },
                    ),
                    _ActionTile(
                      icon: Icons.share_rounded,
                      label: 'Share',
                      cs: cs,
                      onTap: () {
                        Navigator.pop(context);
                        Share.share(
                          '${track.title} — ${track.artist}',
                          subject: track.title,
                        );
                      },
                    ),
                    if (isDownloading)
                      _ActionTile(
                        icon: Icons.downloading_rounded,
                        label: 'Downloading...',
                        cs: cs,
                        onTap: () {},
                        iconColor: cs.primary,
                      )
                    else if (isDownloaded)
                      _ActionTile(
                        icon: Icons.offline_pin_rounded,
                        label: 'Remove Download',
                        cs: cs,
                        onTap: () async {
                          Navigator.pop(context);
                          await watchRef
                              .read(downloadManagerProvider.notifier)
                              .removeDownload(track.effectiveId);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Removed from downloads'),
                                  duration: const Duration(seconds: 1)),
                            );
                          }
                        },
                        iconColor: Colors.redAccent,
                      )
                    else
                      _ActionTile(
                        icon: Icons.download_rounded,
                        label: 'Download',
                        cs: cs,
                        onTap: () async {
                          Navigator.pop(context);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Downloading...'),
                                  duration: const Duration(seconds: 1)),
                            );
                          }
                          try {
                            await watchRef
                                .read(downloadManagerProvider.notifier)
                                .downloadTrack(
                                  track,
                                  const FireballApi(),
                                  library.settings,
                                );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Downloaded successfully'),
                                    duration: const Duration(seconds: 2)),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Download failed'),
                                    duration: const Duration(seconds: 2)),
                              );
                            }
                          }
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Shows a second sheet to pick a playlist.
void _showAddToPlaylist(
  BuildContext context,
  WidgetRef ref,
  Track track,
  List<Playlist> playlists,
) {
  if (playlists.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('No playlists yet. Create one in Your Library.')),
    );
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  'Add to Playlist',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              Divider(
                color: Colors.white.withValues(alpha: 0.07),
                height: 20,
                indent: 16,
                endIndent: 16,
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.4,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (_, i) {
                    final pl = playlists[i];
                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.queue_music_rounded,
                            color: cs.primary, size: 20),
                      ),
                      title: Text(
                        pl.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        '${pl.videos.length} tracks',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                        ),
                      ),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await ref
                            .read(localStoreProvider.notifier)
                            .addTrackToPlaylist(pl.id, track);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('Added to "${pl.title}"'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.cs,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final ColorScheme cs;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        size: 22,
        color: iconColor ?? Colors.white.withValues(alpha: 0.8),
      ),
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      onTap: onTap,
      dense: true,
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.music_note_rounded,
          color: cs.primary.withValues(alpha: 0.4), size: 22),
    );
  }
}
