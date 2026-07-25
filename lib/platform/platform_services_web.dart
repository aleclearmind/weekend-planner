// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

import '../models.dart';

abstract final class PlatformServices {
  static bool get calendarSupported => false;

  static Future<void> exportDatabase(String content, String filename) async {
    final bytes = utf8.encode(content);
    final blob = html.Blob([bytes], 'application/json;charset=utf-8');
    final objectUrl = html.Url.createObjectUrlFromBlob(blob);
    try {
      html.AnchorElement(href: objectUrl)
        ..download = filename
        ..click();
    } finally {
      html.Url.revokeObjectUrl(objectUrl);
    }
  }

  static Future<bool> openUrl(String url) async {
    html.window.open(url, '_blank');
    return true;
  }

  static Future<bool> openOsmAnd({
    required double latitude,
    required double longitude,
    required String label,
  }) => openUrl(
    Uri.https('osmand.net', '/map', {
      'pin': '$latitude,$longitude',
      'name': label,
    }).toString(),
  );

  static Future<bool> requestCalendarAccess() async => false;

  static Future<bool> hasCalendarAccess() async => false;

  static Future<List<DeviceCalendar>> queryCalendars() async => const [];

  static Future<List<CalendarBusyEvent>> queryCalendarEvents({
    required DateTime start,
    required DateTime end,
    required List<String> calendarIds,
  }) async => const [];
}
