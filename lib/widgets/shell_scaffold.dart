import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../core/store/providers.dart';
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

/// Index of the **Remote** tab (full-screen pairing; hide mini-player overlay).
const int kRemoteShellTabIndex = 3;

const _navItems = [
  _NavItem('/home', Icons.home_outlined, Icons.home_rounded, 'Home'),
  _NavItem('/search', Icons.search_outlined, Icons.search_rounded, 'Search'),
  _NavItem('/library', Icons.library_music_outlined,
      Icons.library_music_rounded, 'Library'),
  _NavItem('/remote', Icons.cast_outlined, Icons.cast_rounded, 'Remote'),
  _NavItem(
      '/settings', Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
];

/// Bottom offset for the floating mini-player: clears nav/tab chrome (~72–80)
/// plus the device home-indicator / gesture inset (iOS + Android).
double _miniPlayerBottomOffset(BuildContext context) {
  return 80 + MediaQuery.viewPaddingOf(context).bottom;
}

/// Fades the mini-player in/out so Remote / overlay toggles don’t pop harshly.
Widget _shellMiniPlayerOverlay(
    {required bool hideMini, required double bottom}) {
  return Positioned(
    left: 0,
    right: 0,
    bottom: bottom,
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: hideMini
          ? const SizedBox.shrink(key: ValueKey<Object>('mini-hidden'))
          : const MiniPlayer(key: ValueKey<Object>('mini-visible')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playback error: $error'),
            duration: const Duration(seconds: 4),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
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
    final cs = Theme.of(context).colorScheme;
    final hideMini = ref.watch(remoteScreenCoversShellProvider) ||
        shell.currentIndex == kRemoteShellTabIndex;
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: onTap,
        backgroundColor: cs.surfaceContainer,
        elevation: 0,
        height: 72,
        destinations: _navItems
            .map((item) => NavigationDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.activeIcon),
                  label: item.label,
                ))
            .toList(),
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
    final settings = ref.watch(settingsProvider);
    final isManuallyCollapsed = settings.ipadSidebarCollapsed;
    final extended = (width >= 1000) && !isManuallyCollapsed;
    final hideMini = ref.watch(remoteScreenCoversShellProvider) ||
        shell.currentIndex == kRemoteShellTabIndex;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: onTap,
            extended: extended,
            backgroundColor: cs.surfaceContainer,
            minWidth: 72,
            minExtendedWidth: 180,
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
              ],
            ),
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.selected,
            destinations: _navItems
                .map((item) => NavigationRailDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.activeIcon),
                      label: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                  bottom: 16 + MediaQuery.viewPaddingOf(context).bottom,
                ),
              ],
            ),
          ),
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
    final hideMini = ref.watch(remoteScreenCoversShellProvider) ||
        shell.currentIndex == kRemoteShellTabIndex;
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

  static const double _widthExpanded = 220;
  static const double _widthCollapsed = 72;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final sidebarWidth = sidebarCollapsed ? _widthCollapsed : _widthExpanded;
    final hideMini = ref.watch(remoteScreenCoversShellProvider) ||
        shell.currentIndex == kRemoteShellTabIndex;

    Future<void> toggleCollapsed() async {
      await ref.read(localStoreProvider.notifier).updateSettings({
        'ipadSidebarCollapsed': !sidebarCollapsed,
      });
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Row(
        children: [
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                width: sidebarWidth,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.75),
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
                                        fontSize: 22,
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
                            vertical: 4,
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
                          8,
                          sidebarCollapsed ? 6 : 12,
                          16,
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
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
            ),
          ),
          Expanded(child: shell),
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
    final cs = Theme.of(context).colorScheme;
    final pad = collapsed
        ? const EdgeInsets.symmetric(horizontal: 6, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 11);

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
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: pad,
            decoration: BoxDecoration(
              color: selected
                  ? cs.primary.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: collapsed
                ? Center(
                    child: AnimatedScale(
                      scale: selected ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        selected ? item.activeIcon : item.icon,
                        size: 22,
                        color: selected
                            ? cs.primary
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.55)
                                : Colors.black.withValues(alpha: 0.45)),
                      ),
                    ),
                  )
                : Row(
                    children: [
                      AnimatedScale(
                        scale: selected ? 1.1 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          selected ? item.activeIcon : item.icon,
                          size: 22,
                          color: selected
                              ? cs.primary
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.55)
                                  : Colors.black.withValues(alpha: 0.45)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected
                                ? cs.primary
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.75)
                                    : Colors.black.withValues(alpha: 0.65)),
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

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.72),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 54,
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
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
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
                            duration: const Duration(milliseconds: 200),
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
        ),
      ),
    );
  }
}
