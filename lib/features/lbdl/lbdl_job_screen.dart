import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../core/api/fireball_api.dart';
import '../../core/store/providers.dart';
import '../../core/widgets/platform_widgets.dart';

class LbdlJobScreen extends HookConsumerWidget {
  final String playlistUrl;

  const LbdlJobScreen({super.key, required this.playlistUrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    const api = FireballApi();
    final cs = Theme.of(context).colorScheme;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.black : Colors.white;

    final jobId = useState<String?>(null);
    final jobStatus = useState<String>('Starting job...');
    final progress = useState<double>(0.0);
    final error = useState<String?>(null);
    final isDone = useState(false);
    final trackStatuses = useState<List<Map<String, dynamic>>>([]);

    useEffect(() {
      Timer? timer;

      Future<void> pollJob() async {
        if (jobId.value == null || isDone.value) return;
        try {
          final res = await api.lbdlGetJob(
            settings.lbdlUrl,
            settings.lbdlUsername,
            settings.lbdlPassword,
            jobId.value!,
          );

          final status = res['status']?.toString() ?? 'unknown';
          final tracks = (res['tracks'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();

          if (status != 'error') {
            error.value = null; // Clear any previous polling errors
          }

          trackStatuses.value = tracks;

          // Compute progress from how many tracks are done
          if (tracks.isNotEmpty) {
            final done = tracks
                .where((t) => t['status'] == 'done' || t['status'] == 'exists')
                .length;
            final failed = tracks.where((t) => t['status'] == 'error').length;
            progress.value = done / tracks.length;
            jobStatus.value =
                'Downloading: $done/${tracks.length} tracks${failed > 0 ? ' ($failed failed)' : ''}';
          }

          if (status == 'done') {
            jobStatus.value = 'Download Complete! (${tracks.length} tracks)';
            isDone.value = true;
            timer?.cancel();
          } else if (status == 'error') {
            final logs = res['logs'] as List?;
            error.value = logs?.isNotEmpty == true
                ? logs!.last.toString()
                : 'Job failed with unknown error';
            jobStatus.value = 'Job Failed';
            isDone.value = true;
            timer?.cancel();
          } else if (status == 'queued') {
            jobStatus.value = 'Queued — waiting to start...';
          } else if (status == 'running' && tracks.isEmpty) {
            jobStatus.value = 'Fetching playlist info...';
          }
        } catch (e) {
          error.value = 'Polling failed: $e';
        }
      }

      Future<void> startJob() async {
        try {
          final id = await api.lbdlStartJob(
            settings.lbdlUrl,
            settings.lbdlUsername,
            settings.lbdlPassword,
            playlistUrl,
            settings.invidiousInstance,
          );
          if (id.isEmpty) {
            error.value = 'Server did not return a job ID';
            jobStatus.value = 'Error';
            return;
          }
          jobId.value = id;
          jobStatus.value = 'Job queued. Fetching playlist...';
          timer = Timer.periodic(const Duration(seconds: 3), (_) => pollJob());
        } catch (e) {
          error.value = 'Failed to start job: $e';
          jobStatus.value = 'Error';
        }
      }

      startJob();

      return () => timer?.cancel();
    }, const []);

    return PlatformScaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('lbdl Server Download'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 24),
            Icon(
              error.value != null
                  ? Icons.error_outline_rounded
                  : isDone.value
                      ? Icons.check_circle_outline_rounded
                      : Icons.cloud_download_outlined,
              size: 64,
              color: error.value != null
                  ? Colors.red
                  : isDone.value
                      ? Colors.green
                      : cs.primary,
            ),
            const SizedBox(height: 24),
            Text(
              jobStatus.value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            if (error.value != null) ...[
              const SizedBox(height: 12),
              Text(
                error.value!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            if (!isDone.value && error.value == null)
              LinearProgressIndicator(
                value: progress.value > 0 ? progress.value : null,
                backgroundColor: cs.primary.withValues(alpha: 0.2),
                color: cs.primary,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
            const SizedBox(height: 24),
            // Per-track list
            if (trackStatuses.value.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: trackStatuses.value.length,
                  itemBuilder: (ctx, i) {
                    final t = trackStatuses.value[i];
                    final tStatus = t['status']?.toString() ?? '';
                    final isDoneTrack =
                        tStatus == 'done' || tStatus == 'exists';
                    final isError = tStatus == 'error';
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isDoneTrack
                            ? Icons.check_circle_rounded
                            : isError
                                ? Icons.error_rounded
                                : Icons.hourglass_top_rounded,
                        size: 18,
                        color: isDoneTrack
                            ? Colors.green
                            : isError
                                ? Colors.red
                                : cs.primary,
                      ),
                      title: Text(
                        '${t['title'] ?? ''} — ${t['artist'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: isError && t['error'] != null
                          ? Text(
                              t['error'].toString(),
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 11),
                            )
                          : null,
                    );
                  },
                ),
              ),
            if (isDone.value || error.value != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
