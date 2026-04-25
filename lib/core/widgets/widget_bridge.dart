import 'package:home_widget/home_widget.dart';
import '../models/track.dart';

class WidgetBridge {
  static const String _androidWidgetName = 'MusicWidgetProvider';
  static const String _iosWidgetName = 'MusicWidget';
  static const String _appGroupId = 'group.com.fireball.music';

  /// Updates the home screen widget with the current track info.
  static Future<void> updateWidget(Track track) async {
    try {
      // Set values for both platforms
      await HomeWidget.saveWidgetData<String>('track_title', track.title);
      await HomeWidget.saveWidgetData<String>('track_artist', track.artist);
      
      // Request update
      await HomeWidget.updateWidget(
        name: _androidWidgetName,
        iOSName: _iosWidgetName,
      );
    } catch (e) {
      // Silently fail or log in debug
    }
  }

  /// Initial setup for App Groups on iOS.
  static Future<void> init() async {
    await HomeWidget.setAppGroupId(_appGroupId);
  }
}
