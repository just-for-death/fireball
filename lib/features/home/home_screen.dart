import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import 'package:go_router/go_router.dart';

import '../../core/adapters/fireball_backend_bridge.dart';
import '../../core/api/fireball_api.dart';
import '../../core/countries.dart';
import '../../core/models/track.dart';
import '../../core/store/providers.dart';
import '../../core/theme/fireball_tokens.dart';
import '../../core/ui/shell_content_insets.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/fireball_logo.dart';
import '../../core/widgets/glass_widgets.dart';
import '../../core/widgets/track_options_sheet.dart';

const _lbRanges = [
  ('week', 'Week'),
  ('month', 'Month'),
  ('year', 'Year'),
  ('all_time', 'All time'),
];
const _cloneHomeTabs = ['News', 'Videos', 'Artist', 'Podcasts'];

class HomeScreen extends HookConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final currentTrack = ref.watch(playerProvider.select((p) => p.currentTrack));
    final bridge = useMemoized(() => FireballBackendBridge());
    const api = FireballApi();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ── Core state ─────────────────────────────────────────────────────────
    final country = useState('us');
    final trending = useState<List<Map<String, dynamic>>>([]);
    final lbRecent = useState<List<dynamic>>([]);
    final lbTop = useState<List<dynamic>>([]);
    final lbRange = useState('month');
    final loading = useState(true);
    final lbTopLoading = useState(false);
    final selectedCloneTab = useState(_cloneHomeTabs.first);

    // ── Visible countries (filtered by settings, fallback to defaults) ──────
    final savedCodes = settings.homeCountries;
    final visibleCountries = savedCodes.isEmpty
        ? kAllCountries
            .where((c) => kDefaultHomeCountries.contains(c.$1))
            .toList()
        : kAllCountries.where((c) => savedCodes.contains(c.$1)).toList();

    // ── LB availability ────────────────────────────────────────────────────
    final lbEnabled = settings.listenBrainzEnabled &&
        settings.listenBrainzUsername.isNotEmpty &&
        settings.listenBrainzToken.isNotEmpty;
    final lbUsername = settings.listenBrainzUsername;
    final lbToken = settings.listenBrainzToken;

    // Library rows come from the store (watched) so they appear after async disk
    // load — a one-shot read inside load() can race and stay empty forever.
    final library = ref.watch(localStoreProvider);
    final historyRows = library.history.take(10).toList();
    final favoritesRows = library.favorites.take(12).toList();

    // ── Main load ─────────────────────────────────────────────────────────
    Future<void> load() async {
      loading.value = true;
      try {
        trending.value = await bridge
            .fetchTopSongs(countryCode: country.value, limit: 20)
            .catchError((_) => <Map<String, dynamic>>[]);

        if (lbEnabled) {
          lbRecent.value = await api
              .getLBRecentListens(lbUsername, lbToken)
              .catchError((_) => <dynamic>[]);
        }
      } finally {
        loading.value = false;
      }
    }

    Future<void> loadLbTop() async {
      if (!lbEnabled) return;
      lbTopLoading.value = true;
      try {
        lbTop.value = await api
            .getLBTopRecordings(lbUsername, lbToken, lbRange.value)
            .catchError((_) => <dynamic>[]);
      } finally {
        lbTopLoading.value = false;
      }
    }

    useEffect(() {
      load();
      // Run the Gotify release check silently in the background
      Future.microtask(
          () => ref.read(localStoreProvider.notifier).checkGotifyNewReleases());
      return null;
    }, [country.value, lbEnabled, lbUsername, lbToken]);

    useEffect(() {
      loadLbTop();
      return null;
    }, [lbRange.value, lbEnabled, lbUsername, lbToken]);

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isTablet = screenWidth >= 600;
    final hPad = isTablet ? (screenWidth * 0.045).clamp(20.0, 56.0) : 20.0;

    final trendingTracks = trending.value
        .map((t) => Track(
              id: t['id'] ?? '',
              title: t['title'] ?? '—',
              artist: t['artist'] ?? '—',
              artwork: t['artwork'],
              url: t['url'] ?? '',
            ))
        .toList();
    final cloneTabTracks = _tracksForCloneTab(
      selectedTab: selectedCloneTab.value,
      trendingTracks: trendingTracks,
      historyRows: historyRows,
      favoritesRows: favoritesRows,
    );

    return PremiumBackground(
      child: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([load(), loadLbTop()]);
        },
        color: cs.primary,
        backgroundColor: Colors.white,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Header ──────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: AnimatedContainer(
                duration: FireballTokens.motionBase,
                curve: FireballTokens.motionCurve,
                decoration: BoxDecoration(
                  gradient: currentTrack == null
                      ? null
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            cs.primary.withValues(alpha: 0.18),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 1.0],
                        ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      hPad,
                      FireballTokens.gapXl + FireballTokens.gapSm,
                      hPad,
                      FireballTokens.gapMd,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ShaderMask(
                                shaderCallback: (bounds) => LinearGradient(
                                  colors: [
                                    Colors.white,
                                    Colors.white.withValues(alpha: 0.7),
                                  ],
                                ).createShader(bounds),
                                child: Text(
                                  'Fireball',
                                  style: TextStyle(
                                    fontSize: isTablet ? 42 : 38,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: -1.4,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
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
                        const SizedBox(height: 4),
                        Text(
                          'Good evening',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.4),
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Top chips ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: isTablet
                  ? Padding(
                      padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: visibleCountries.map((c) {
                          final (cc, label) = c;
                          return _HomeHeaderChip(
                            label: label,
                            selected: country.value == cc,
                            onTap: () => country.value = cc,
                          );
                        }).toList(),
                      ),
                    )
                  : Container(
                      height: 52,
                      margin: const EdgeInsets.only(top: 8),
                      alignment: Alignment.center,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: visibleCountries.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final (cc, label) = visibleCountries[i];
                          return _HomeHeaderChip(
                            label: label,
                            selected: country.value == cc,
                            onTap: () => country.value = cc,
                          );
                        },
                      ),
                    ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            if (trendingTracks.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  child: _CloneInspiredHeroCard(
                    featured: trendingTracks.first,
                    onPlay: () {
                      ref.read(playerProvider.notifier).setQueue(trendingTracks);
                      ref.read(playerProvider.notifier).playIndex(0);
                      ref.read(localStoreProvider.notifier).addHistory(
                            trendingTracks.first,
                          );
                    },
                  ),
                ),
              ),
            if (trendingTracks.isNotEmpty)
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad),
                child: _CloneInspiredTabs(
                  tabs: _cloneHomeTabs,
                  selected: selectedCloneTab.value,
                  onSelect: (value) => selectedCloneTab.value = value,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 10)),
            if (cloneTabTracks.isNotEmpty)
              SliverToBoxAdapter(
                child: _RecommendationShelf(
                  title: 'From ${selectedCloneTab.value}',
                  tracks: cloneTabTracks.take(8).toList(),
                  onTap: (idx, tracks) {
                    ref.read(playerProvider.notifier).setQueue(tracks);
                    ref.read(playerProvider.notifier).playIndex(idx);
                    ref.read(localStoreProvider.notifier).addHistory(tracks[idx]);
                  },
                  cs: cs,
                ),
              ),
            if (cloneTabTracks.isNotEmpty)
              const SliverToBoxAdapter(child: SizedBox(height: 20)),

            if (historyRows.isNotEmpty || favoritesRows.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  child: _QuickPicksGrid(
                    tracks: _buildRecommendationTracks(
                      historyRows: historyRows,
                      favoritesRows: favoritesRows,
                      trendingTracks: trendingTracks,
                    ).take(8).toList(),
                    onTap: (idx, tracks) {
                      ref.read(playerProvider.notifier).setQueue(tracks);
                      ref.read(playerProvider.notifier).playIndex(idx);
                      ref.read(localStoreProvider.notifier).addHistory(tracks[idx]);
                    },
                    cs: cs,
                  ),
                ),
              ),
            if (historyRows.isNotEmpty || favoritesRows.isNotEmpty)
              const SliverToBoxAdapter(child: SizedBox(height: 18)),

            // ── Trending Now ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad),
                child: Row(
                  children: [
                    const Text(
                      'Top Charts',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.trending_up_rounded,
                        color: cs.primary.withValues(alpha: 0.92), size: 18),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 10)),
            if (loading.value)
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    _TrendingShimmer(isDark: isDark),
                    const SizedBox(height: 8),
                    Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (trending.value.isEmpty)
              const SliverToBoxAdapter(
                child: FireballEmptyState(
                  onDarkGlass: true,
                  title: 'Could not load trending',
                  subtitle: 'Check your connection and pull to refresh.',
                  icon: Icons.wifi_off_rounded,
                ),
              )
            else if (isTablet)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: hPad),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: screenWidth >= 1100 ? 176 : 166,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: screenWidth >= 1100 ? 170 : 162,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final item = trending.value[i];
                      return GestureDetector(
                        onTap: () {
                          ref
                              .read(playerProvider.notifier)
                              .setQueue(trendingTracks);
                          ref.read(playerProvider.notifier).playIndex(i);
                          ref
                              .read(localStoreProvider.notifier)
                              .addHistory(trendingTracks[i]);
                        },
                        child: GlassCard(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                          opacity: 0.1,
                          borderRadius: BorderRadius.circular(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: item['artwork'] != null
                                      ? CachedNetworkImage(
                                          imageUrl: item['artwork']!,
                                          width: double.infinity,
                                          height: double.infinity,
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) =>
                                              _TrendingGridPlaceholder(cs: cs),
                                        )
                                      : _TrendingGridPlaceholder(cs: cs),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item['title'] ?? '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                item['artist'] ?? '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: trending.value.length,
                  ),
                ),
              )
            else
              SliverToBoxAdapter(
                child: _TrendingRow(
                  items: trending.value,
                  cs: cs,
                  isDark: isDark,
                  onTap: (idx) {
                    ref.read(playerProvider.notifier).setQueue(trendingTracks);
                    ref.read(playerProvider.notifier).playIndex(idx);
                    ref
                        .read(localStoreProvider.notifier)
                        .addHistory(trendingTracks[idx]);
                  },
                  onLongPress: (track) => showTrackOptions(context, ref, track),
                ),
              ),

            // ── Personalized sections ─────────────────────────────────────
            if (historyRows.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  child: Row(
                    children: [
                      Text(
                        'Made for You',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.auto_awesome_rounded,
                          color: cs.primary.withValues(alpha: 0.92), size: 18),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 10)),
              SliverToBoxAdapter(
                child: _RecommendationShelf(
                  title: 'Inspired by your recent listening',
                  tracks: _buildRecommendationTracks(
                    historyRows: historyRows,
                    favoritesRows: favoritesRows,
                    trendingTracks: trendingTracks,
                  ),
                  onTap: (idx, tracks) {
                    ref.read(playerProvider.notifier).setQueue(tracks);
                    ref.read(playerProvider.notifier).playIndex(idx);
                    ref.read(localStoreProvider.notifier).addHistory(tracks[idx]);
                  },
                  cs: cs,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  child: Text(
                    'Jump Back In',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 10)),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final track = historyRows[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 4),
                      child: GlassCard(
                        padding: EdgeInsets.zero,
                        borderRadius: BorderRadius.circular(16),
                        opacity: 0.04,
                        child: _HistoryTile(
                          track: track,
                          cs: cs,
                          isDark: isDark,
                          onTap: () {
                            ref
                                .read(playerProvider.notifier)
                                .setQueue(historyRows.sublist(index));
                            ref.read(playerProvider.notifier).playIndex(0);
                          },
                          onLongPress: () =>
                              showTrackOptions(context, ref, track),
                        ),
                      ),
                    );
                  },
                  childCount: historyRows.length,
                ),
              ),
            ],

            // ── Recent Favorites ──────────────────────────────────────────
            if (favoritesRows.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  child: Row(
                    children: [
                      Text(
                        'Recently Liked',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.favorite_rounded,
                          color: cs.primary.withValues(alpha: 0.92), size: 18),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 10)),
              SliverToBoxAdapter(
                child: _FavoritesRow(
                  favorites: favoritesRows,
                  cs: cs,
                  isDark: isDark,
                  onTap: (idx) {
                    ref
                        .read(playerProvider.notifier)
                        .setQueue(favoritesRows.sublist(idx));
                    ref.read(playerProvider.notifier).playIndex(0);
                  },
                  onLongPress: (track) => showTrackOptions(context, ref, track),
                ),
              ),
            ],

            // ── Recently Listened (ListenBrainz) ──────────────────────────
            if (lbEnabled && lbRecent.value.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  child: Row(
                    children: [
                      Text(
                        'Recently Played',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Spacer(),
                      const _LbLogo(),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final rawListen = lbRecent.value[index];
                    if (rawListen is! Map) return const SizedBox.shrink();
                    final listen = rawListen;
                    final rawMeta = listen['track_metadata'];
                    final meta =
                        rawMeta is Map ? rawMeta : const <String, dynamic>{};
                    final mbidMapping = meta['mbid_mapping'] as Map?;
                    final caaMbid = mbidMapping?['caa_release_mbid'] as String?;
                    final listenedAt = listen['listened_at'] as int?;
                    final date = listenedAt != null
                        ? _fmtDate(DateTime.fromMillisecondsSinceEpoch(
                            listenedAt * 1000))
                        : null;

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 4),
                      child: GlassCard(
                        padding: EdgeInsets.zero,
                        borderRadius: BorderRadius.circular(16),
                        opacity: 0.04,
                        child: _LBTrackTile(
                          title: meta['track_name']?.toString() ?? '—',
                          artist: meta['artist_name']?.toString() ?? '—',
                          caaMbid: caaMbid,
                          album: meta['release_name']?.toString(),
                          cs: cs,
                          isDark: isDark,
                          right: date != null
                              ? Text(
                                  date,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withValues(alpha: 0.4),
                                  ),
                                )
                              : null,
                          onTap: () {
                            final t = Track(
                              id: meta['track_name']?.toString() ?? '',
                              title: meta['track_name']?.toString() ?? '—',
                              artist: meta['artist_name']?.toString() ?? '—',
                              album: meta['release_name']?.toString(),
                            );
                            ref.read(playerProvider.notifier).playTrackNow(t);
                          },
                          onLongPress: () {
                            final t = Track(
                              id: meta['track_name']?.toString() ?? '',
                              title: meta['track_name']?.toString() ?? '—',
                              artist: meta['artist_name']?.toString() ?? '—',
                              album: meta['release_name']?.toString(),
                            );
                            showTrackOptions(context, ref, t);
                          },
                        ),
                      ),
                    );
                  },
                  childCount: lbRecent.value.length,
                ),
              ),
            ],

            // ── My Top Tracks (ListenBrainz) ──────────────────────────────
            if (lbEnabled) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 36)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  child: Row(
                    children: [
                      Text(
                        'My Top Tracks',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Spacer(),
                      const _LbLogo(),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 10)),
              SliverToBoxAdapter(
                child: _RangePills(
                  current: lbRange.value,
                  onChanged: (r) => lbRange.value = r,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 10)),
              if (lbTopLoading.value)
                SliverToBoxAdapter(child: _LBListShimmer(isDark: isDark))
              else if (lbTop.value.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 24),
                    child: Text(
                      'No stats yet for this period.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final rec = lbTop.value[index] as Map;
                      final listenCount =
                          (rec['listen_count'] as num?)?.toInt() ?? 0;
                      final caaMbid = rec['caa_release_mbid'] as String?;

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 4),
                        child: GlassCard(
                          padding: EdgeInsets.zero,
                          borderRadius: BorderRadius.circular(16),
                          opacity: 0.04,
                          child: _LBTrackTile(
                            title: rec['track_name']?.toString() ?? '—',
                            artist: rec['artist_name']?.toString() ?? '—',
                            caaMbid: caaMbid,
                            album: rec['release_name']?.toString(),
                            cs: cs,
                            isDark: isDark,
                            rank: index + 1,
                            right: _PlayCountBadge(count: listenCount, cs: cs),
                            onTap: () {
                              final t = Track(
                                id: rec['track_name']?.toString() ?? '',
                                title: rec['track_name']?.toString() ?? '—',
                                artist: rec['artist_name']?.toString() ?? '—',
                                album: rec['release_name']?.toString(),
                              );
                              ref.read(playerProvider.notifier).playTrackNow(t);
                            },
                            onLongPress: () {
                              final t = Track(
                                id: rec['track_name']?.toString() ?? '',
                                title: rec['track_name']?.toString() ?? '—',
                                artist: rec['artist_name']?.toString() ?? '—',
                                album: rec['release_name']?.toString(),
                              );
                              showTrackOptions(context, ref, t);
                            },
                          ),
                        ),
                      );
                    },
                    childCount: lbTop.value.length,
                  ),
                ),
            ],

            SliverToBoxAdapter(
              child: SizedBox(height: shellScrollBottomPadding(context)),
            ),
          ],
        ),
      ),
    );
  }
}

List<Track> _tracksForCloneTab({
  required String selectedTab,
  required List<Track> trendingTracks,
  required List<Track> historyRows,
  required List<Track> favoritesRows,
}) {
  switch (selectedTab) {
    case 'Videos':
      return historyRows.isNotEmpty ? historyRows : trendingTracks;
    case 'Artist':
      return favoritesRows.isNotEmpty ? favoritesRows : trendingTracks;
    case 'Podcasts':
      return trendingTracks.reversed.toList();
    case 'News':
    default:
      return trendingTracks;
  }
}

class _CloneInspiredHeroCard extends StatelessWidget {
  const _CloneInspiredHeroCard({
    required this.featured,
    required this.onPlay,
  });

  final Track featured;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onPlay,
      borderRadius: BorderRadius.circular(20),
      hoverColor: Colors.white.withValues(alpha: 0.06),
      splashColor: Colors.white.withValues(alpha: 0.09),
      highlightColor: Colors.white.withValues(alpha: 0.05),
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withValues(alpha: 0.8),
              cs.primary.withValues(alpha: 0.35),
              const Color(0xFF1A1A1A),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'New Album',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      featured.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      featured.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: FireballPlayerArtwork(
                    networkUrl: featured.artwork,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloneInspiredTabs extends StatelessWidget {
  const _CloneInspiredTabs({
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final List<String> tabs;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final tab = tabs[i];
          final isSelected = selected == tab;
          return InkWell(
            onTap: () => onSelect(tab),
            borderRadius: BorderRadius.circular(999),
            hoverColor: Colors.white.withValues(alpha: 0.08),
            splashColor: Colors.white.withValues(alpha: 0.10),
            highlightColor: Colors.white.withValues(alpha: 0.06),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.14)
                    : FireballTokens.blackElevated,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.12),
                  width: 0.8,
                ),
              ),
              child: Text(
                tab,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: isSelected ? 0.95 : 0.78),
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

List<Track> _buildRecommendationTracks({
  required List<Track> historyRows,
  required List<Track> favoritesRows,
  required List<Track> trendingTracks,
}) {
  final seen = <String>{};
  final ordered = <Track>[];
  void pushAll(List<Track> source) {
    for (final t in source) {
      if (t.title.trim().isEmpty || t.artist.trim().isEmpty) continue;
      final key = '${t.title}::${t.artist}'.toLowerCase();
      if (seen.add(key)) ordered.add(t);
      if (ordered.length >= 30) return;
    }
  }

  pushAll(historyRows);
  pushAll(favoritesRows);
  pushAll(trendingTracks);
  return ordered.take(20).toList();
}

class _RecommendationShelf extends StatelessWidget {
  const _RecommendationShelf({
    required this.title,
    required this.tracks,
    required this.onTap,
    required this.cs,
  });
  final String title;
  final List<Track> tracks;
  final void Function(int index, List<Track> tracks) onTap;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 252,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: tracks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final t = tracks[i];
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onTap(i, tracks),
            child: GlassCard(
              padding: const EdgeInsets.all(10),
              opacity: 0.08,
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: 164,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: t.artwork != null
                          ? CachedNetworkImage(
                              imageUrl: t.artwork!,
                              width: 164,
                              height: 164,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  _TrendingGridPlaceholder(cs: cs),
                            )
                          : _TrendingGridPlaceholder(cs: cs),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$title · ${t.artist}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _QuickPicksGrid extends StatelessWidget {
  const _QuickPicksGrid({
    required this.tracks,
    required this.onTap,
    required this.cs,
  });
  final List<Track> tracks;
  final void Function(int index, List<Track> tracks) onTap;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 1300
        ? 4
        : width >= 980
            ? 3
            : 2;
    return GridView.builder(
      itemCount: tracks.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        mainAxisExtent: 64,
      ),
      itemBuilder: (context, i) {
        final t = tracks[i];
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onTap(i, tracks),
          child: Container(
            decoration: BoxDecoration(
              color: FireballTokens.blackElevatedHigh,
              borderRadius: BorderRadius.circular(FireballTokens.radiusSm),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomLeft: Radius.circular(8),
                  ),
                  child: t.artwork != null
                      ? CachedNetworkImage(
                          imageUrl: t.artwork!,
                          width: 66,
                          height: double.infinity,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _TrendingGridPlaceholder(cs: cs),
                        )
                      : SizedBox(
                          width: 66,
                          child: _TrendingGridPlaceholder(cs: cs),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HomeHeaderChip extends StatelessWidget {
  const _HomeHeaderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      hoverColor: Colors.white.withValues(alpha: 0.08),
      splashColor: Colors.white.withValues(alpha: 0.10),
      highlightColor: Colors.white.withValues(alpha: 0.06),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: selected ? 0.95 : 0.78),
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _fmtDate(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inDays == 0) return 'Today';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dt.day}/${dt.month}';
}

String? _caaUrl(String? mbid) => mbid != null && mbid.isNotEmpty
    ? 'https://coverartarchive.org/release/$mbid/front-250'
    : null;

class _LbLogo extends StatelessWidget {
  const _LbLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEB743B).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFEB743B).withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: const Text(
        'ListenBrainz',
        style: TextStyle(
          color: Color(0xFFEB743B),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _RangePills extends StatelessWidget {
  const _RangePills({required this.current, required this.onChanged});
  final String current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      alignment: Alignment.center,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: _lbRanges.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final (value, label) = _lbRanges[i];
          return GlassPill(
            label: label,
            selected: current == value,
            onTap: () => onChanged(value),
          );
        },
      ),
    );
  }
}

class _CaaArtwork extends StatelessWidget {
  const _CaaArtwork({
    required this.mbid,
    required this.cs,
    required this.size,
  });
  final String? mbid;
  final ColorScheme cs;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = _caaUrl(mbid);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.18),
      child: url != null
          ? CachedNetworkImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _placeholder(),
            )
          : _placeholder(),
    );
  }

  Widget _placeholder() => Container(
        width: size,
        height: size,
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.music_note_rounded,
            color: cs.primary.withValues(alpha: 0.4), size: size * 0.44),
      );
}

class _LBTrackTile extends StatelessWidget {
  const _LBTrackTile({
    required this.title,
    required this.artist,
    required this.cs,
    required this.isDark,
    required this.onTap,
    this.onLongPress,
    this.caaMbid,
    this.album,
    this.rank,
    this.right,
  });

  final String title;
  final String artist;
  final String? album;
  final String? caaMbid;
  final int? rank;
  final Widget? right;
  final ColorScheme cs;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            if (rank != null)
              SizedBox(
                width: 24,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
            if (rank != null) const SizedBox(width: 8),
            _CaaArtwork(mbid: caaMbid, cs: cs, size: 50),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: isDark ? Colors.white : cs.onSurface,
                    ),
                  ),
                  Text(
                    '$artist${caaMbid != null ? "" : (album != null ? " • $album" : "")}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.5)
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (right != null) ...[const SizedBox(width: 8), right!],
          ],
        ),
      ),
    );
  }
}

class _PlayCountBadge extends StatelessWidget {
  const _PlayCountBadge({required this.count, required this.cs});
  final int count;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count plays',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: cs.primary.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

class _FavoritesRow extends StatelessWidget {
  const _FavoritesRow({
    required this.favorites,
    required this.cs,
    required this.isDark,
    required this.onTap,
    this.onLongPress,
  });
  final List<Track> favorites;
  final ColorScheme cs;
  final bool isDark;
  final void Function(int) onTap;
  final void Function(Track)? onLongPress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: favorites.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final track = favorites[i];
          return GestureDetector(
            onTap: () => onTap(i),
            onLongPress: onLongPress != null ? () => onLongPress!(track) : null,
            child: GlassCard(
              padding: const EdgeInsets.all(10),
              opacity: 0.08,
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: 130,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: track.artwork != null
                          ? CachedNetworkImage(
                              imageUrl: track.artwork!,
                              width: 130,
                              height: 130,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  _placeholder(130, cs),
                            )
                          : _placeholder(130, cs),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.favorite_rounded,
                            size: 10, color: cs.primary.withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${track.artist}${track.album != null ? " • ${track.album}" : ""}${track.year != null ? " (${track.year})" : ""}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _placeholder(double size, ColorScheme cs) => Container(
        width: size,
        height: size,
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.favorite_rounded,
            color: cs.primary.withValues(alpha: 0.3), size: size * 0.35),
      );
}

class _TrendingRow extends StatelessWidget {
  const _TrendingRow({
    required this.items,
    required this.cs,
    required this.isDark,
    required this.onTap,
    this.onLongPress,
  });
  final List<Map<String, dynamic>> items;
  final ColorScheme cs;
  final bool isDark;
  final void Function(int) onTap;
  final void Function(Track)? onLongPress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 230,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, i) {
          final item = items[i];
          final track = Track(
            id: item['id'] ?? '',
            title: item['title'] ?? '—',
            artist: item['artist'] ?? '—',
            artwork: item['artwork'],
            url: item['url'] ?? '',
          );
          return GestureDetector(
            onTap: () => onTap(i),
            onLongPress: onLongPress != null ? () => onLongPress!(track) : null,
            child: GlassCard(
              padding: const EdgeInsets.all(10),
              opacity: 0.1,
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: item['artwork'] != null
                          ? CachedNetworkImage(
                              imageUrl: item['artwork']!,
                              width: 150,
                              height: 150,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _artPlaceholder(cs),
                            )
                          : _artPlaceholder(cs),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item['title'] ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item['artist'] ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _artPlaceholder(ColorScheme cs) => Container(
        width: 140,
        height: 140,
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.music_note_rounded,
            color: cs.primary.withValues(alpha: 0.4), size: 40),
      );
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.track,
    required this.cs,
    required this.isDark,
    required this.onTap,
    this.onLongPress,
  });
  final Track track;
  final ColorScheme cs;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      hoverColor: Colors.white.withValues(alpha: 0.06),
      splashColor: Colors.white.withValues(alpha: 0.09),
      highlightColor: Colors.white.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Row(
          children: [
            ClipRRect(
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: isDark ? Colors.white : cs.onSurface,
                    ),
                  ),
                  Text(
                    '${track.artist}${track.album != null ? " • ${track.album}" : ""}${track.year != null ? " (${track.year})" : ""}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.5)
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.play_circle_fill_rounded,
                size: 28, color: cs.primary),
          ],
        ),
      ),
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

class _TrendingShimmer extends StatelessWidget {
  const _TrendingShimmer({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => Shimmer.fromColors(
          baseColor: isDark ? const Color(0xFF191919) : const Color(0xFFE0E0E0),
          highlightColor:
              isDark ? const Color(0xFF242424) : const Color(0xFFEEEEEE),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              const SizedBox(height: 8),
              Container(width: 120, height: 12, color: Colors.white),
              const SizedBox(height: 4),
              Container(width: 80, height: 10, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _LBListShimmer extends StatelessWidget {
  const _LBListShimmer({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: List.generate(
          5,
          (_) => Shimmer.fromColors(
            baseColor:
                isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE0E0E0),
            highlightColor:
                isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEEEEEE),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 160, height: 12, color: Colors.white),
                      const SizedBox(height: 6),
                      Container(width: 100, height: 10, color: Colors.white),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Placeholder used in the tablet trending grid (standalone, no parent class)
class _TrendingGridPlaceholder extends StatelessWidget {
  const _TrendingGridPlaceholder({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 120,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.music_note_rounded,
          color: cs.primary.withValues(alpha: 0.4), size: 36),
    );
  }
}
