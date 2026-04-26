import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../core/store/providers.dart';
import '../core/theme/fireball_tokens.dart';
import '../core/ui/messenger_service.dart';
import '../core/widgets/fireball_logo.dart';
import '../sync/webdav_live_sync.dart';
import 'mini_player.dart';

// ── Nav data ─────────────────────────────────────────────────────────────────
class _NavItem {
  final String path;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(this.path, this.icon, this.activeIcon, this.label);
}

const _navItems = [
  _NavItem('/home', Icons.home_outlined, Icons.home_rounded, 'Home'),
  _NavItem('/search', Icons.search_outlined, Icons.search_rounded, 'Search'),
  _NavItem(
      '/library', Icons.library_books_outlined, Icons.library_books_rounded, 'Library'),
];

/// Bottom offset for the floating mini-player: clears nav/tab chrome (~72–80)
/// plus the device home-indicator / gesture inset (iOS + Android).
double _miniPlayerBottomOffset(BuildContext context) {
  return FireballTokens.navHeight + 8 + MediaQuery.viewPaddingOf(context).bottom;
}

/// Fades the mini-player in/out so Remote / overlay toggles don’t pop harshly.
Widget _shellMiniPlayerOverlay(
    {required bool hideMini, required double bottom}) {
  return Positioned(
    left: 0,
    right: 0,
    bottom: bottom,
    child: AnimatedSwitcher(
      duration: FireballTokens.motionBase,
      switchInCurve: FireballTokens.motionCurve,
      switchOutCurve: FireballTokens.motionInCurve,
      child: hideMini
          ? const SizedBox.shrink(key: ValueKey<Object>('mini-hidden'))
          : const MiniPlayer(key: ValueKey<Object>('mini-visible')),
    ),
  );
}

Future<void> _showCreateSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.playlist_add_rounded),
            title: const Text('Create playlist'),
            onTap: () async {
              Navigator.pop(ctx);
              final ctrl = TextEditingController();
              try {
                final title = await showDialog<String>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Create playlist'),
                    content: TextField(
                      controller: ctrl,
                      autofocus: true,
                      decoration:
                          const InputDecoration(
                              hintText: 'Give your playlist a name'),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(d),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(d, ctrl.text.trim()),
                        child: const Text('Create'),
                      ),
                    ],
                  ),
                );
                if (title != null && title.isNotEmpty) {
                  await ref.read(localStoreProvider.notifier).createPlaylist(title);
                }
              } finally {
                ctrl.dispose();
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.cast_rounded),
            title: const Text('Connect to a device'),
            onTap: () {
              Navigator.pop(ctx);
              context.push('/remote');
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_rounded),
            title: const Text('Settings'),
            onTap: () {
              Navigator.pop(ctx);
              context.push('/settings');
            },
          ),
        ],
      ),
    ),
  );
}

// ── Shell scaffold — platform-aware, inspired by Catalyst ────────────────────
class ShellScaffold extends HookConsumerWidget {
  const ShellScaffold({super.key, required this.shell});
  final StatefulNavigationShell shell;

  void _go(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Show a SnackBar whenever playback fails
    ref.listen<String?>(
      playerProvider.select((s) => s.playbackError),
      (_, error) {
        if (error == null) return;
        if (!context.mounted) return;
        MessengerService.instance.showError('Playback error: $error');
        // Clear the error so the same message doesn't re-fire on the next
        // state rebuild that happens to pass the same non-null value through.
        ref.read(playerProvider.notifier).clearPlaybackError();
      },
    );

    final settings = ref.watch(settingsProvider);
    final store = ref.read(localStoreProvider.notifier);
    final player = ref.read(playerProvider.notifier);

    // Sync player-state fields that are derived from persisted settings
    // (e.g. videoMode) on first frame, so the player doesn't start with stale
    // defaults.  Deferred via Future() so it runs after the widget tree has
    // finished building — calling state= synchronously inside useEffect's
    // initHook fires Riverpod's _debugCanModifyProviders assertion.
    useEffect(() {
      Future(() => player.fetchSettings());
      return null;
    }, const []);

    // WebDAV live sync: pull/push on app resume.
    // Read fresh settings via ref.read inside the callback so that credential
    // changes (password, username) are picked up without restarting the listener.
    useEffect(() {
      if (!settings.webDavLiveSync || settings.webDavUrl.isEmpty) return null;
      final listener = AppLifecycleListener(
        onResume: () => WebDavLiveSync.syncIfNeeded(
          ref.read(localStoreProvider).settings,
          store,
        ),
      );
      return listener.dispose;
    }, [settings.webDavLiveSync, settings.webDavUrl]);

    // Periodic WebDAV sync while the app runs (two-device library convergence).
    useEffect(() {
      if (!settings.webDavLiveSync || settings.webDavUrl.isEmpty) return null;
      final t = Timer.periodic(const Duration(minutes: 4), (_) {
        WebDavLiveSync.syncIfNeeded(
          ref.read(localStoreProvider).settings,
          store,
        );
      });
      return t.cancel;
    }, [settings.webDavLiveSync, settings.webDavUrl]);

    // Remote server: start/stop based on settings toggle
    useEffect(() {
      if (settings.remoteServerEnabled) {
        player.startRemoteServer();
      } else {
        player.stopRemoteServer();
      }
      return null;
    }, [settings.remoteServerEnabled]);

    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final width = MediaQuery.sizeOf(context).width;
    final isTablet = width >= 600;
    final isDesktopPlatform = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final isDesktop = isDesktopPlatform && width >= 1100;

    if (isDesktop) {
      return _DesktopShell(shell: shell, onTap: _go);
    }

    if (isIOS) {
      return isTablet
          ? _IPadShell(
              shell: shell,
              onTap: _go,
              sidebarCollapsed: settings.ipadSidebarCollapsed,
            )
          : _IPhoneShell(shell: shell, onTap: _go);
    }

    return isTablet
        ? _AndroidTabletShell(shell: shell, onTap: _go, width: width)
        : _AndroidShell(shell: shell, onTap: _go);
  }
}

// ── Android phone — Material You NavigationBar ────────────────────────────────
class _AndroidShell extends ConsumerWidget {
  const _AndroidShell({required this.shell, required this.onTap});
  final StatefulNavigationShell shell;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideMini = ref.watch(remoteScreenCoversShellProvider);
    return Scaffold(
      body: Stack(
        children: [
          shell,
          _shellMiniPlayerOverlay(
            hideMini: hideMini,
            bottom: 12.0, // Floating just above the NavigationBar
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: FireballTokens.black,
          border: Border(top: BorderSide(color: Color(0xFF222222), width: 0.6)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: onTap,
          backgroundColor: Colors.transparent,
          indicatorColor: Colors.transparent,
          elevation: 0,
          height: FireballTokens.navHeight,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.6),
            );
          }),
          destinations: _navItems
              .map((item) => NavigationDestination(
                    icon: Icon(item.icon,
                        size: 24, color: Colors.white.withValues(alpha: 0.62)),
                    selectedIcon: Icon(item.activeIcon,
                        size: 24, color: Colors.white),
                    label: item.label,
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _DesktopShell extends HookConsumerWidget {
  const _DesktopShell({required this.shell, required this.onTap});
  final StatefulNavigationShell shell;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(localStoreProvider);
    final player = ref.watch(playerProvider);
    final hideMini = ref.watch(remoteScreenCoversShellProvider);
    final selectedFilter = useState<String>('Playlists');
    final libraryQuery = useTextEditingController();
    useListenable(libraryQuery);

    final recentLibraryItems = <({String title, String subtitle, String? artwork})>[
      ...library.playlists.take(5).map((p) => (
            title: p.title,
            subtitle: 'Playlist',
            artwork: p.videos.isNotEmpty ? p.videos.first.artwork : null,
          )),
      ...library.history.take(6).map((t) => (
            title: t.title,
            subtitle: t.artist,
            artwork: t.artwork,
          )),
    ];
    final filteredLibraryItems = recentLibraryItems.where((item) {
      final q = libraryQuery.text.trim().toLowerCase();
      final isPlaylist = item.subtitle == 'Playlist';
      if (selectedFilter.value == 'Playlists' && !isPlaylist) return false;
      if (selectedFilter.value == 'Artists' && isPlaylist) return false;
      if (selectedFilter.value == 'Albums' && isPlaylist) return false;
      if (q.isEmpty) return true;
      return item.title.toLowerCase().contains(q) ||
          item.subtitle.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Row(
              children: [
                SizedBox(
                  width: 292,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(8, 8, 4, 6),
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                    decoration: BoxDecoration(
                      color: FireballTokens.black,
                      borderRadius: BorderRadius.circular(FireballTokens.radiusSm),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(8, 8, 8, 12),
                          child: FireballLogo(size: 36),
                        ),
                        const SizedBox(height: 4),
                        ...List.generate(_navItems.length, (i) {
                          final item = _navItems[i];
                          final selected = shell.currentIndex == i;
                          return _DesktopNavItem(
                            icon: selected ? item.activeIcon : item.icon,
                            label: item.label,
                            selected: selected,
                            onTap: () => onTap(i),
                          );
                        }),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            children: [
                              const Text(
                                'Your Library',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.add_rounded,
                                size: 18,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 18,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _DesktopFilterChip(
                                label: 'Playlists',
                                selected: selectedFilter.value == 'Playlists',
                                onTap: () => selectedFilter.value = 'Playlists',
                              ),
                              _DesktopFilterChip(
                                label: 'Artists',
                                selected: selectedFilter.value == 'Artists',
                                onTap: () => selectedFilter.value = 'Artists',
                              ),
                              _DesktopFilterChip(
                                label: 'Albums',
                                selected: selectedFilter.value == 'Albums',
                                onTap: () => selectedFilter.value = 'Albums',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            children: [
                              Icon(Icons.search_rounded,
                                  size: 17, color: Colors.white.withValues(alpha: 0.62)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: libraryQuery,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    hintText: 'Search in Your Library',
                                    hintStyle: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.42),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              Icon(Icons.grid_view_rounded,
                                  size: 16, color: Colors.white.withValues(alpha: 0.62)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: ListView.builder(
                            itemCount: filteredLibraryItems.length,
                            itemBuilder: (_, i) => _DesktopLibraryItem(
                              title: filteredLibraryItems[i].title,
                              subtitle: filteredLibraryItems[i].subtitle,
                              artwork: filteredLibraryItems[i].artwork,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                    decoration: BoxDecoration(
                      color: FireballTokens.black,
                      borderRadius: BorderRadius.circular(FireballTokens.radiusSm),
                    ),
                    child: Column(
                      children: [
                        const _DesktopTopBar(),
                        Expanded(child: shell),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 332,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(4, 8, 8, 8),
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: FireballTokens.black,
                      borderRadius: BorderRadius.circular(FireballTokens.radiusSm),
                    ),
                    child: _NowPlayingSidePanel(player: player),
                  ),
                ),
              ],
            ),
            ),
            if (!hideMini)
              const Padding(
                padding: EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: MiniPlayer(desktopDock: true),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Android tablet — NavigationRail ──────────────────────────────────────────
class _AndroidTabletShell extends ConsumerWidget {
  const _AndroidTabletShell(
      {required this.shell, required this.onTap, required this.width});
  final StatefulNavigationShell shell;
  final void Function(int) onTap;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final player = ref.watch(playerProvider);
    final settings = ref.watch(settingsProvider);
    final isManuallyCollapsed = settings.ipadSidebarCollapsed;
    final extended = (width >= 1240) && !isManuallyCollapsed;
    final hideMini = ref.watch(remoteScreenCoversShellProvider);
    final showRightPanel = width >= 1200;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: onTap,
            extended: extended,
            useIndicator: true,
            indicatorShape: const StadiumBorder(),
            indicatorColor: cs.primary.withValues(alpha: 0.16),
            backgroundColor: cs.surfaceContainer,
            minWidth: 74,
            minExtendedWidth: 188,
            leading: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: extended ? 'Collapse sidebar' : 'Expand sidebar',
                  onPressed: () {
                    ref.read(localStoreProvider.notifier).updateSettings({
                      'ipadSidebarCollapsed': !isManuallyCollapsed,
                    });
                  },
                  icon: Icon(
                    extended ? Icons.menu_open_rounded : Icons.menu_rounded,
                    color: cs.primary,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, top: 8),
                  child: FireballLogo(size: extended ? 44 : 36),
                ),
                if (extended)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: const [
                        _DesktopFilterChip(label: 'Playlists', selected: true),
                        _DesktopFilterChip(label: 'Artists'),
                      ],
                    ),
                  ),
              ],
            ),
            // Keep the narrow rail icon-only to avoid clipped/truncated labels
            // on smaller tablet widths and high text scale factors.
            labelType: NavigationRailLabelType.none,
            destinations: _navItems
                .map((item) => NavigationRailDestination(
                      icon: Icon(item.icon, size: 20),
                      selectedIcon: Icon(item.activeIcon, size: 20),
                      label: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ))
                .toList(),
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: cs.outlineVariant.withValues(alpha: 0.4),
          ),
          Expanded(
            child: Stack(
              children: [
                shell,
                _shellMiniPlayerOverlay(
                  hideMini: hideMini,
                  bottom: 8 + MediaQuery.viewPaddingOf(context).bottom,
                ),
              ],
            ),
          ),
          if (showRightPanel) ...[
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: cs.outlineVariant.withValues(alpha: 0.3),
            ),
            SizedBox(
              width: 292,
              child: Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFF121212),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _NowPlayingSidePanel(player: player),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── iOS phone — glass frosted tab bar ────────────────────────────────────────
class _IPhoneShell extends ConsumerWidget {
  const _IPhoneShell({required this.shell, required this.onTap});
  final StatefulNavigationShell shell;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideMini = ref.watch(remoteScreenCoversShellProvider);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        children: [
          shell,
          _shellMiniPlayerOverlay(
            hideMini: hideMini,
            bottom: _miniPlayerBottomOffset(context),
          ),
          Positioned(
            right: 18,
            bottom: _miniPlayerBottomOffset(context) + 76,
            child: FloatingActionButton(
              heroTag: 'create-fab-ios',
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              onPressed: () => _showCreateSheet(context, ref),
              child: const Icon(Icons.add_rounded, size: 28),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _GlassTabBar(
        selectedIndex: shell.currentIndex,
        onTap: onTap,
      ),
    );
  }
}

// ── iPadOS — glass sidebar ────────────────────────────────────────────────────
class _IPadShell extends ConsumerWidget {
  const _IPadShell({
    required this.shell,
    required this.onTap,
    required this.sidebarCollapsed,
  });
  final StatefulNavigationShell shell;
  final void Function(int) onTap;
  final bool sidebarCollapsed;

  static const double _widthExpanded = 214;
  static const double _widthCollapsed = 70;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final player = ref.watch(playerProvider);
    final width = MediaQuery.sizeOf(context).width;
    final showRightPanel = width >= 1000;
    final sidebarWidth = sidebarCollapsed ? _widthCollapsed : _widthExpanded;
    final hideMini = ref.watch(remoteScreenCoversShellProvider);

    Future<void> toggleCollapsed() async {
      await ref.read(localStoreProvider.notifier).updateSettings({
        'ipadSidebarCollapsed': !sidebarCollapsed,
      });
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Row(
        children: [
          AnimatedContainer(
                duration: FireballTokens.motionBase,
                curve: FireballTokens.motionCurve,
                width: sidebarWidth,
                decoration: BoxDecoration(
                  color: isDark ? FireballTokens.black : Colors.white,
                  border: Border(
                    right: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.10)
                          : Colors.black.withValues(alpha: 0.07),
                      width: 0.5,
                    ),
                  ),
                ),
            child: SafeArea(
                  child: Column(
                    crossAxisAlignment: sidebarCollapsed
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: sidebarCollapsed ? 8 : 24),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: sidebarCollapsed ? 4 : 20,
                          vertical: 8,
                        ),
                        child: sidebarCollapsed
                            ? Column(
                                children: [
                                  IconButton(
                                    tooltip: 'Expand sidebar',
                                    onPressed: toggleCollapsed,
                                    icon: Icon(
                                      Icons.menu_open_rounded,
                                      color: cs.primary,
                                    ),
                                  ),
                                  const FireballLogo(size: 36),
                                ],
                              )
                            : Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Collapse sidebar',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 40,
                                      minHeight: 40,
                                    ),
                                    onPressed: toggleCollapsed,
                                    icon: Icon(
                                      Icons.menu_rounded,
                                      color: cs.primary,
                                    ),
                                  ),
                                  const FireballLogo(size: 40),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Fireball',
                                      maxLines: 1,
                                      overflow: TextOverflow.fade,
                                      softWrap: false,
                                      style: TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.symmetric(
                            horizontal: sidebarCollapsed ? 6 : 12,
                            vertical: sidebarCollapsed ? 8 : 4,
                          ),
                          itemCount: _navItems.length,
                          itemBuilder: (context, i) {
                            final item = _navItems[i];
                            final selected = i == shell.currentIndex;
                            return _SidebarItem(
                              item: item,
                              selected: selected,
                              isDark: isDark,
                              collapsed: sidebarCollapsed,
                              onTap: () => onTap(i),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          sidebarCollapsed ? 6 : 12,
                          6,
                          sidebarCollapsed ? 6 : 12,
                          14,
                        ),
                        child: AnimatedSwitcher(
                          duration: FireballTokens.motionBase,
                          switchInCurve: FireballTokens.motionCurve,
                          switchOutCurve: FireballTokens.motionInCurve,
                          child: hideMini
                              ? const SizedBox.shrink(
                                  key: ValueKey<Object>('ipad-mini-off'),
                                )
                              : _SidebarMiniPlayer(
                                  key: const ValueKey<Object>('ipad-mini-on'),
                                  sidebarCollapsed: sidebarCollapsed,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          Expanded(child: shell),
          if (showRightPanel)
            SizedBox(
              width: sidebarCollapsed ? 242 : 270,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 8, 7),
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF121212)
                        : Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _NowPlayingSidePanel(player: player),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.item,
    required this.selected,
    required this.isDark,
    required this.collapsed,
    required this.onTap,
  });
  final _NavItem item;
  final bool selected;
  final bool isDark;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedColor = Colors.white;
    final unselectedColor = isDark
        ? Colors.white.withValues(alpha: 0.62)
        : Colors.black.withValues(alpha: 0.58);
    final pad = collapsed
        ? const EdgeInsets.symmetric(horizontal: 6, vertical: 7)
        : const EdgeInsets.symmetric(horizontal: 11, vertical: 9);

    return Tooltip(
      message: item.label,
      child: Semantics(
        button: true,
        label: item.label,
        selected: selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: FireballTokens.motionBase,
            curve: FireballTokens.motionCurve,
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: pad,
            decoration: BoxDecoration(
              color: (selected && !collapsed)
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: collapsed
                ? Center(
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: AnimatedScale(
                        scale: selected ? 1.08 : 1.0,
                        duration: FireballTokens.motionFast,
                        curve: FireballTokens.motionCurve,
                        child: Icon(
                          selected ? item.activeIcon : item.icon,
                          size: 20,
                          color: selected ? selectedColor : unselectedColor,
                        ),
                      ),
                    ),
                  )
                : Row(
                    children: [
                      AnimatedScale(
                        scale: selected ? 1.1 : 1.0,
                        duration: FireballTokens.motionFast,
                        curve: FireballTokens.motionCurve,
                        child: Icon(
                          selected ? item.activeIcon : item.icon,
                          size: 20,
                          color: selected ? selectedColor : unselectedColor,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: AnimatedDefaultTextStyle(
                          duration: FireballTokens.motionFast,
                          curve: FireballTokens.motionCurve,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? selectedColor : unselectedColor,
                          ),
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _DesktopNavItem extends StatelessWidget {
  const _DesktopNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      hoverColor: Colors.white.withValues(alpha: 0.08),
      splashColor: Colors.white.withValues(alpha: 0.10),
      highlightColor: Colors.white.withValues(alpha: 0.06),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withValues(alpha: 0.16) : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.58),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.62),
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopFilterChip extends StatelessWidget {
  const _DesktopFilterChip({
    required this.label,
    this.selected = false,
    this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      hoverColor: Colors.white.withValues(alpha: 0.08),
      splashColor: Colors.white.withValues(alpha: 0.10),
      highlightColor: Colors.white.withValues(alpha: 0.06),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.06),
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
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          const Spacer(),
          const SizedBox(width: 2),
        ],
      ),
    );
  }
}

class _DesktopLibraryItem extends StatelessWidget {
  const _DesktopLibraryItem({
    required this.title,
    required this.subtitle,
    this.artwork,
  });
  final String title;
  final String subtitle;
  final String? artwork;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          hoverColor: Colors.white.withValues(alpha: 0.08),
          splashColor: Colors.white.withValues(alpha: 0.10),
          highlightColor: Colors.white.withValues(alpha: 0.06),
          onTap: () => context.go('/library'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: artwork != null && artwork!.isNotEmpty
                      ? Image.network(
                          artwork!,
                          width: 39,
                          height: 39,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                ),
                const SizedBox(width: 9),
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
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.58),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 39,
        height: 39,
        color: Colors.white.withValues(alpha: 0.08),
        child: Icon(
          Icons.music_note_rounded,
          size: 17,
          color: Colors.white.withValues(alpha: 0.65),
        ),
      );
}

enum _RightPanelMode { nowPlaying, queue, devices }

class _NowPlayingSidePanel extends HookConsumerWidget {
  const _NowPlayingSidePanel({required this.player});
  final PlayerState player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = player.currentTrack;
    final queue = player.queue;
    final mode = useState(_RightPanelMode.nowPlaying);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _DesktopFilterChip(
              label: 'Now Playing',
              selected: mode.value == _RightPanelMode.nowPlaying,
              onTap: () => mode.value = _RightPanelMode.nowPlaying,
            ),
            _DesktopFilterChip(
              label: 'Queue',
              selected: mode.value == _RightPanelMode.queue,
              onTap: () => mode.value = _RightPanelMode.queue,
            ),
            _DesktopFilterChip(
              label: 'Devices',
              selected: mode.value == _RightPanelMode.devices,
              onTap: () => mode.value = _RightPanelMode.devices,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (mode.value == _RightPanelMode.devices)
          Expanded(
            child: ListView(
              children: [
                _deviceTile(
                  icon: Icons.computer_rounded,
                  label: 'This Computer',
                  selected: true,
                ),
                _deviceTile(
                  icon: Icons.cast_rounded,
                  label: 'Fireball Remote',
                  selected: false,
                ),
                _deviceTile(
                  icon: Icons.smartphone_rounded,
                  label: 'Mobile App',
                  selected: false,
                ),
                const SizedBox(height: 10),
                Text(
                  'Select a playback device to control this session.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          )
        else if (mode.value == _RightPanelMode.queue)
          Expanded(
            child: queue.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.queue_music_rounded,
                              size: 18, color: Colors.white.withValues(alpha: 0.35)),
                          const SizedBox(height: 8),
                          Text(
                            'Queue is empty',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: queue.length > 25 ? 25 : queue.length,
                    itemBuilder: (_, i) {
                      final t = queue[i];
                      final current = i == player.currentIndex;
                      return InkWell(
                        borderRadius: BorderRadius.circular(6),
                        hoverColor: Colors.white.withValues(alpha: 0.06),
                        splashColor: Colors.white.withValues(alpha: 0.09),
                        highlightColor: Colors.white.withValues(alpha: 0.05),
                        onTap: () => ref.read(playerProvider.notifier).playIndex(i),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 1),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: current
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.white
                                    .withValues(alpha: current ? 0.12 : 0.06),
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 12,
                                child: Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: t.artwork != null && t.artwork!.isNotEmpty
                                    ? Image.network(
                                        t.artwork!,
                                        width: 26,
                                        height: 26,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _queueArtPlaceholder(),
                                      )
                                    : _queueArtPlaceholder(),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${t.title} • ${t.artist}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: current
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.7),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          )
        else ...[
          Row(
            children: [
              const Text(
                'Now Playing',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.favorite_border_rounded,
                size: 16,
                color: Colors.white.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Open player',
                onPressed: () => context.push('/player'),
                icon: Icon(
                  Icons.open_in_new_rounded,
                  color: Colors.white.withValues(alpha: 0.7),
                  size: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (track != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: track.artwork != null && track.artwork!.isNotEmpty
                  ? Image.network(
                      track.artwork!,
                      width: double.infinity,
                      height: 220,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _artworkPlaceholder(),
                    )
                  : _artworkPlaceholder(),
            ),
            const SizedBox(height: 12),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About the artist',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${track.artist} • Popular tracks and recommendations.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.66),
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ] else
            _artworkPlaceholder(),
          const SizedBox(height: 12),
          Text(
            'Up Next',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              itemCount: queue.length > 10 ? 10 : queue.length,
              itemBuilder: (_, i) {
                final t = queue[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      hoverColor: Colors.white.withValues(alpha: 0.06),
                      splashColor: Colors.white.withValues(alpha: 0.09),
                      highlightColor: Colors.white.withValues(alpha: 0.05),
                      onTap: () => ref.read(playerProvider.notifier).playIndex(i),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.white.withValues(alpha: 0.06),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: t.artwork != null && t.artwork!.isNotEmpty
                                  ? Image.network(
                                      t.artwork!,
                                      width: 26,
                                      height: 26,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _queueArtPlaceholder(),
                                    )
                                  : _queueArtPlaceholder(),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${t.title} • ${t.artist}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.68),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _deviceTile({
    required IconData icon,
    required String label,
    required bool selected,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.72)),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.74),
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      );

  Widget _artworkPlaceholder() => Container(
        width: double.infinity,
        height: 220,
        color: const Color(0xFF242424),
        child: Icon(
          Icons.music_note_rounded,
          size: 44,
          color: Colors.white.withValues(alpha: 0.42),
        ),
      );

  Widget _queueArtPlaceholder() => Container(
        width: 26,
        height: 26,
        color: Colors.white.withValues(alpha: 0.08),
        child: Icon(
          Icons.music_note_rounded,
          size: 14,
          color: Colors.white.withValues(alpha: 0.56),
        ),
      );
}

// Compact now-playing strip at the bottom of the iPad sidebar
class _SidebarMiniPlayer extends StatelessWidget {
  const _SidebarMiniPlayer({super.key, required this.sidebarCollapsed});

  final bool sidebarCollapsed;

  @override
  Widget build(BuildContext context) {
    return MiniPlayer(
      compact: true,
      sidebarIconOnly: sidebarCollapsed,
    );
  }
}

// ── Glass tab bar (iOS phone) ─────────────────────────────────────────────────
class _GlassTabBar extends StatelessWidget {
  const _GlassTabBar({required this.selectedIndex, required this.onTap});
  final int selectedIndex;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? FireballTokens.black : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: List.generate(_navItems.length, (i) {
              final item = _navItems[i];
              final selected = i == selectedIndex;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedScale(
                        scale: selected ? 1.12 : 1.0,
                        duration: FireballTokens.motionFast,
                        curve: FireballTokens.motionCurve,
                        child: Icon(
                          selected ? item.activeIcon : item.icon,
                          size: 22,
                          color: selected
                              ? cs.primary
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : Colors.black.withValues(alpha: 0.4)),
                        ),
                      ),
                      const SizedBox(height: 3),
                      AnimatedDefaultTextStyle(
                        duration: FireballTokens.motionFast,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected
                              ? cs.primary
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : Colors.black.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
