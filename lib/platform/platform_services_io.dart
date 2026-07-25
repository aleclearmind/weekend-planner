import 'package:flutter/services.dart';

import '../models.dart';

abstract final class PlatformServices {
  static const _channel = MethodChannel(
    'io.claudietto.weekend_planner/platform',
  );

  static bool get calendarSupported => true;

  static Future<void> exportDatabase(String content, String filename) async {
    await _channel.invokeMethod<void>('exportDatabase', {
      'content': content,
      'filename': filename,
    });
  }

  static Future<bool> openUrl(String url) async =>
      await _channel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;

  static Future<bool> openOsmAnd({
    required double latitude,
    required double longitude,
    required String label,
  }) async =>
      await _channel.invokeMethod<bool>('openOsmAnd', {
        'latitude': latitude,
        'longitude': longitude,
        'label': label,
      }) ??
      false;

  static Future<bool> requestCalendarAccess() async =>
      await _channel.invokeMethod<bool>('requestCalendarAccess') ?? false;

  static Future<bool> hasCalendarAccess() async =>
      await _channel.invokeMethod<bool>('hasCalendarAccess') ?? false;

  static Future<List<CalendarBusyEvent>> queryCalendarEvents({
    required DateTime start,
    required DateTime end,
  }) async {
    final values =
        await _channel.invokeListMethod<Object?>('queryCalendarEvents', {
          'start': start.millisecondsSinceEpoch,
          'end': end.millisecondsSinceEpoch,
        }) ??
        const [];
    return values
        .whereType<Map<Object?, Object?>>()
        .map(CalendarBusyEvent.fromMap)
        .toList();
  }
}
