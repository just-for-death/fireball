import 'dart:ui';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'routes/router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  runApp(const ProviderScope(child: FireballApp()));
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
