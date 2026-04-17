import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import 'package:audio_service/audio_service.dart';
import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'package:audio_session/audio_session.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'core/audio/fireball_audio_handler.dart';
import 'core/audio/media_session_bridge.dart';
import 'routes/router.dart';

Future<void> _initAudioSession() async {
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  } catch (e, st) {
    debugPrint('AudioSession.configure failed: $e $st');
  }
}

/// Linux: DBus MPRIS so GNOME/KDE media keys and taskbar controls work.
void _registerLinuxMpris() {
  try {
    if (defaultTargetPlatform == TargetPlatform.linux) {
      AudioServiceMpris.registerWith();
    }
  } catch (e, st) {
    debugPrint('AudioServiceMpris.registerWith failed: $e $st');
  }
}

Future<void> _initMediaService() async {
  try {
    _registerLinuxMpris();
    MediaSessionBridge.handler = await AudioService.init<FireballAudioHandler>(
      builder: FireballAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.fireball.fireball.playback',
        androidNotificationChannelName: 'Playback',
        androidNotificationChannelDescription: 'Now playing controls',
        androidNotificationIcon: 'mipmap/launcher_icon',
        notificationColor: Color(0xFF4A378B),
        androidStopForegroundOnPause: true,
        androidNotificationOngoing: false,
        preloadArtwork: true,
      ),
    );
  } catch (e, st) {
    debugPrint('AudioService.init failed: $e $st');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  // Show UI immediately. Do not run native media init before runApp():
  // MediaKit.ensureInitialized(), media_kit Player(), AudioService.init, and
  // AudioSession can block the UI isolate on iOS — the native splash stays up
  // until the first frame is fully rendered.
  runApp(const ProviderScope(child: FireballApp()));

  _scheduleIosFriendlyMediaBootstrap();
}

/// After the first frame, load native media (libmpv, audio_service). On iOS we
/// wait an extra tick so the launch snapshot is dismissed before heavy native work.
void _scheduleIosFriendlyMediaBootstrap() {
  void start() => unawaited(_bootstrapAudioAfterFirstFrame());

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (kIsWeb) {
      start();
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      // Second microtask turn after paint — avoids contending with Impeller/surface setup.
      Future<void>(() async {
        await Future<void>.delayed(Duration.zero);
        start();
      });
    } else {
      start();
    }
  });
}

Future<void> _bootstrapAudioAfterFirstFrame() async {
  // Must run before any Player() — see PlayerNotifier._ensurePlayer.
  MediaKit.ensureInitialized();
  await _initMediaService();
  await _initAudioSession();
  MediaSessionBridge.sync();
}

class FireballApp extends ConsumerWidget {
  const FireballApp({super.key});

  ThemeData _withDynamic(ThemeData base, ColorScheme? dynamic, bool isDark) {
    if (dynamic == null) return base;
    final harmonized = ColorScheme.fromSeed(
      seedColor: dynamic.primary,
      brightness: isDark ? Brightness.dark : Brightness.light,
    );
    return base.copyWith(
      colorScheme: harmonized,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF050505) : harmonized.surface,
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: harmonized.secondaryContainer,
        backgroundColor: harmonized.surfaceContainer,
        elevation: 0,
        height: 72,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    final baseLight = FlexThemeData.light(
      scheme: FlexScheme.deepPurple,
      useMaterial3: true,
      useMaterial3ErrorColors: true,
    ).copyWith(
      tabBarTheme: const TabBarThemeData(tabAlignment: TabAlignment.center),
    );

    final baseDark = FlexThemeData.dark(
      scheme: FlexScheme.deepPurple,
      useMaterial3: true,
      useMaterial3ErrorColors: true,
      darkIsTrueBlack: true,
    ).copyWith(
      tabBarTheme: const TabBarThemeData(tabAlignment: TabAlignment.center),
    );

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final lightTheme = _withDynamic(baseLight, lightDynamic, false);
        final darkTheme = _withDynamic(baseDark, darkDynamic, true);

        return MaterialApp.router(
          title: 'Fireball',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: ThemeMode.system,
          routerConfig: router,
          scrollBehavior: _FireballScrollBehavior(),
        );
      },
    );
  }
}

class _FireballScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}
