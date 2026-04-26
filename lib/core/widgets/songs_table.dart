import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/track.dart';
import '../theme/fireball_tokens.dart';

class SongsTable extends StatelessWidget {
  const SongsTable({
    super.key,
    required this.tracks,
    required this.onTrackTap,
    required this.onTrackLongPress,
  });

  final List<Track> tracks;
  final ValueChanged<int> onTrackTap;
  final ValueChanged<Track> onTrackLongPress;

  String _fmtDuration(int? sec) {
    if (sec == null || sec <= 0) return '--:--';
    final m = (sec ~/ 60).toString();
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
          ),
          child: Row(
            children: [
              Text('#',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
              const SizedBox(width: 20),
              SizedBox(
                width: 340,
                child: Text(
                  'Title',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                ),
              ),
              Expanded(
                child: Text(
                  'Album',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                ),
              ),
              SizedBox(
                width: 110,
                child: Icon(Icons.access_time_rounded,
                    size: 14, color: Colors.white.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
        ...List.generate(tracks.length, (i) {
          final t = tracks[i];
          return InkWell(
            onTap: () => onTrackTap(i),
            onLongPress: () => onTrackLongPress(t),
            borderRadius: BorderRadius.circular(4),
            hoverColor: Colors.white.withValues(alpha: 0.08),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(
                  bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.68), fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: t.artwork != null && t.artwork!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: t.artwork!,
                            width: 38,
                            height: 38,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _tinyPlaceholder(),
                          )
                        : _tinyPlaceholder(),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 280,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: FireballTokens.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                        Text(
                          t.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.62),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      t.album ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.64),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _fmtDuration(t.duration),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _tinyPlaceholder() => Container(
        width: 38,
        height: 38,
        color: const Color(0xFF242424),
        child: Icon(Icons.music_note_rounded,
            color: Colors.white.withValues(alpha: 0.45), size: 16),
      );
}
