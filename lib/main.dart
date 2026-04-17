import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';

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
    if (Platform.isLinux) {
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
  // Required before any media_kit Player is created (PlayerNotifier ctor).
  MediaKit.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  // Show UI immediately. Do not await AudioService / AudioSession here — on iOS those
  // calls can stall; blocking main() before runApp() leaves the native splash forever.
  runApp(const ProviderScope(child: FireballApp()));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_bootstrapAudioAfterFirstFrame());
  });
}

Future<void> _bootstrapAudioAfterFirstFrame() async {
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
