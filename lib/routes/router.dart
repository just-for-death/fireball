import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../features/artist/artist_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/player/player_screen.dart';
import '../features/remote/remote_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/lbdl/lbdl_job_screen.dart';
import '../widgets/shell_scaffold.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'rootNav');
final _homeTabNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'homeTabNav');
final _searchTabNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'searchTabNav');
final _libraryTabNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'libraryTabNav');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => ShellScaffold(shell: shell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _homeTabNavigatorKey,
            routes: [
            GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _searchTabNavigatorKey,
            routes: [
            GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _libraryTabNavigatorKey,
            routes: [
            GoRoute(
                path: '/library', builder: (_, __) => const LibraryScreen()),
            ],
          ),
        ],
      ),
      GoRoute(path: '/remote', builder: (_, __) => const RemoteScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(
        path: '/player',
        builder: (_, __) => const PlayerScreen(),
      ),
      GoRoute(
        path: '/artist',
        builder: (_, state) {
          final name = state.uri.queryParameters['name'] ?? '';
          return ArtistScreen(artistName: name);
        },
      ),
      GoRoute(
        path: '/lbdl-job',
        builder: (_, state) {
          final url = state.uri.queryParameters['url'] ?? '';
          return LbdlJobScreen(playlistUrl: url);
        },
      ),
    ],
  );
});
