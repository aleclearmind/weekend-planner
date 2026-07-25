import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import 'models.dart';
import 'platform/platform_services.dart';

class FeedRefreshResult {
  const FeedRefreshResult({
    required this.added,
    required this.checked,
    required this.errors,
  });

  final int added;
  final int checked;
  final List<String> errors;
}

class _FetchedFeed {
  const _FetchedFeed({
    required this.body,
    required this.url,
    this.discoveredTitle,
  });

  final String body;
  final String url;
  final String? discoveredTitle;
}

class PlannerStore extends ChangeNotifier {
  PlannerStore._(this._preferences);

  /// Do not increment this until an explicit schema bump is requested.
  static const currentSchemaVersion = 1;
  static const _storageKey = 'weekend_planner_state_v1';
  static const _maxLogEntries = 250;
  static const _browserUserAgent =
      'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/138.0.0.0 Mobile Safari/537.36';

  final SharedPreferences _preferences;

  List<ActivityIdea> activities = [];
  Map<String, SlotAssignment> assignments = {};
  List<String> cachedPeople = [];
  List<RssFeed> feeds = [];
  List<RssInboxItem> inbox = [];
  List<DiagnosticLogEntry> eventLog = [];
  bool calendarEnabled = false;
  bool isRefreshingFeeds = false;
  bool isRefreshingCalendar = false;
  final Map<String, String> _calendarSlotTitles = {};

  static Future<PlannerStore> load() async {
    final preferences = await SharedPreferences.getInstance();
    final store = PlannerStore._(preferences);
    final encoded = preferences.getString(_storageKey);
    if (encoded == null) {
      await store._persist();
      return store;
    }

    try {
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final migrated = _migrateDatabase(decoded);
      store._restore(migrated);
      final samplesRemoved = store._removeLegacySampleData();
      if (samplesRemoved || !decoded.containsKey('schemaVersion')) {
        await store._persist();
      }
    } on Object catch (error, stackTrace) {
      store._appendLog(
        level: 'error',
        category: 'database',
        message: 'Stored database could not be loaded; started empty.',
        details: '$error\n$stackTrace',
      );
      await store._persist();
    }
    return store;
  }

  /// Every future version must be added here as a one-step migration.
  static Map<String, dynamic> _migrateDatabase(Map<String, dynamic> source) {
    final database = Map<String, dynamic>.from(source);
    var version = (database['schemaVersion'] as num?)?.toInt() ?? 1;
    if (version > currentSchemaVersion) {
      throw FormatException(
        'Database schema $version is newer than supported schema '
        '$currentSchemaVersion.',
      );
    }
    while (version < currentSchemaVersion) {
      // Add migrations as explicit steps:
      // case 1: database = _migrateV1ToV2(database); version = 2;
      throw StateError('No migration registered for database schema $version.');
    }
    database['schemaVersion'] = currentSchemaVersion;
    return database;
  }

  ActivityIdea? activityById(String id) {
    for (final activity in activities) {
      if (activity.id == id) return activity;
    }
    return null;
  }

  SlotAssignment? assignmentAt(DateTime friday, int slotIndex) =>
      assignments[_slotKey(friday, slotIndex)];

  List<ActivityPlacement> placementsForActivity(String activityId) {
    final placements = <ActivityPlacement>[];
    for (final entry in assignments.entries) {
      if (entry.value.activityId != activityId || entry.value.part != 1) {
        continue;
      }
      final separator = entry.key.lastIndexOf('#');
      if (separator <= 0) continue;
      final friday = DateTime.tryParse(entry.key.substring(0, separator));
      final slotIndex = int.tryParse(entry.key.substring(separator + 1));
      if (friday == null ||
          slotIndex == null ||
          slotIndex < 0 ||
          slotIndex >= WeekendSlot.all.length) {
        continue;
      }
      placements.add(
        ActivityPlacement(
          friday: dateOnly(friday),
          slotIndex: slotIndex,
          slotLength: entry.value.total,
        ),
      );
    }
    placements.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.slotIndex.compareTo(a.slotIndex);
    });
    return placements;
  }

  String? frequencyWarning(ActivityIdea activity) {
    final frequency = activity.desiredFrequencyWeeks;
    if (!activity.isRecurring || frequency == null) return null;
    final placements = placementsForActivity(activity.id);
    final currentFriday = firstRelevantFriday(DateTime.now());
    if (placements.any(
      (placement) => !placement.friday.isBefore(currentFriday),
    )) {
      return null;
    }
    if (placements.isEmpty) {
      return 'Not done yet · goal: ${activity.frequencyLabel!.toLowerCase()}';
    }
    final latest = placements.first.friday;
    final weekendsSince = currentFriday.difference(latest).inDays ~/ 7;
    if (weekendsSince < frequency) return null;
    return '$weekendsSince weekends since last time · '
        'goal: ${activity.frequencyLabel!.toLowerCase()}';
  }

  String? fitProblem(ActivityIdea activity, DateTime friday, int slotIndex) {
    final selectedSlot = WeekendSlot.all[slotIndex];
    if (activity.startPart != null && activity.startPart != selectedSlot.part) {
      return 'Starts a ${activity.startPart!.name}, not a '
          '${selectedSlot.part.name}.';
    }
    if (slotIndex + activity.slotLength > WeekendSlot.all.length) {
      return 'Needs ${activity.slotLength} slots, but the weekend ends first.';
    }
    if (!activity.isAvailableAt(slotDate(friday, slotIndex))) {
      return 'Outside its date range.';
    }
    for (
      var index = slotIndex;
      index < slotIndex + activity.slotLength;
      index++
    ) {
      if (assignmentAt(friday, index) != null) {
        return 'Needs ${activity.slotLength} free '
            '${activity.slotLength == 1 ? 'slot' : 'slots'} from here.';
      }
    }
    return null;
  }

  void assign(ActivityIdea activity, DateTime friday, int slotIndex) {
    for (var offset = 0; offset < activity.slotLength; offset++) {
      assignments[_slotKey(friday, slotIndex + offset)] = SlotAssignment(
        activityId: activity.id,
        part: offset + 1,
        total: activity.slotLength,
      );
    }
    _changed();
  }

  void clearAssignment(DateTime friday, int slotIndex) {
    final current = assignmentAt(friday, slotIndex);
    if (current == null) return;
    final firstIndex = slotIndex - current.part + 1;
    for (var offset = 0; offset < current.total; offset++) {
      assignments.remove(_slotKey(friday, firstIndex + offset));
    }
    _changed();
  }

  void saveActivity(ActivityIdea activity) {
    final index = activities.indexWhere((item) => item.id == activity.id);
    if (index == -1) {
      activities.add(activity);
    } else {
      activities[index] = activity;
    }
    for (final person in activity.people) {
      _cachePerson(person.name);
    }
    _changed();
  }

  void deleteActivity(String id) {
    activities.removeWhere((activity) => activity.id == id);
    assignments.removeWhere((_, assignment) => assignment.activityId == id);
    _changed();
  }

  void renamePerson(String oldName, String newName) {
    final normalized = newName.trim();
    if (normalized.isEmpty) return;
    cachedPeople.removeWhere(
      (name) => name.toLowerCase() == oldName.toLowerCase(),
    );
    _cachePerson(normalized);
    for (var index = 0; index < activities.length; index++) {
      final merged = <String, Participant>{};
      for (final participant in activities[index].people) {
        final renamed = participant.name.toLowerCase() == oldName.toLowerCase()
            ? participant.copyWith(name: normalized)
            : participant;
        final key = renamed.name.toLowerCase();
        final existing = merged[key];
        if (existing == null ||
            InterestStatus.values.indexOf(renamed.status) >
                InterestStatus.values.indexOf(existing.status)) {
          merged[key] = renamed;
        }
      }
      activities[index] = activities[index].copyWith(
        people: merged.values.toList(),
      );
    }
    _changed();
  }

  void removePerson(String name) {
    cachedPeople.removeWhere(
      (person) => person.toLowerCase() == name.toLowerCase(),
    );
    for (var index = 0; index < activities.length; index++) {
      activities[index] = activities[index].copyWith(
        people: activities[index].people
            .where(
              (participant) =>
                  participant.name.toLowerCase() != name.toLowerCase(),
            )
            .toList(),
      );
    }
    _changed();
  }

  Future<RssFeed> addFeed(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const FormatException('Enter a complete http:// or https:// URL.');
    }
    if (feeds.any((feed) => feed.url == uri.toString())) {
      throw const FormatException('That feed is already in your list.');
    }
    final name = uri.host.replaceFirst(RegExp(r'^www\.'), '');
    final feed = RssFeed(id: _newId('feed'), name: name, url: uri.toString());
    feeds.add(feed);
    _changed();
    return feed;
  }

  void renameFeed(String id, String name) {
    final index = feeds.indexWhere((feed) => feed.id == id);
    if (index == -1 || name.trim().isEmpty) return;
    feeds[index] = feeds[index].copyWith(name: name.trim());
    _changed();
  }

  void removeFeed(String id) {
    feeds.removeWhere((feed) => feed.id == id);
    inbox.removeWhere((item) => item.feedId == id);
    _changed();
  }

  Future<FeedRefreshResult> refreshFeeds({String? onlyFeedId}) async {
    if (isRefreshingFeeds) {
      return const FeedRefreshResult(added: 0, checked: 0, errors: []);
    }
    final selected = onlyFeedId == null
        ? List<RssFeed>.from(feeds)
        : feeds.where((feed) => feed.id == onlyFeedId).toList();
    if (selected.isEmpty) {
      return const FeedRefreshResult(added: 0, checked: 0, errors: []);
    }

    isRefreshingFeeds = true;
    notifyListeners();
    var added = 0;
    var checked = 0;
    final errors = <String>[];
    try {
      for (final feed in selected) {
        try {
          final fetched = await _fetchFeed(feed.url);
          final refreshedFeed = feed.copyWith(
            url: fetched.url,
            name: fetched.discoveredTitle,
            lastChecked: DateTime.now(),
          );
          final parsed = _parseFeed(refreshedFeed, fetched.body);
          final knownIds = inbox.map((item) => item.id).toSet();
          for (final item in parsed) {
            if (knownIds.add(item.id)) {
              inbox.add(item);
              added++;
            }
          }
          final index = feeds.indexWhere((item) => item.id == feed.id);
          if (index != -1) feeds[index] = refreshedFeed;
          checked++;
          _appendLog(
            category: 'rss',
            message: 'Parsed ${parsed.length} entries from ${feed.name}.',
            details: 'Effective feed URL: ${fetched.url}',
          );
        } on Object catch (error, stackTrace) {
          final friendly = _friendlyFeedError(error);
          errors.add('${feed.name}: $friendly');
          _appendLog(
            level: 'error',
            category: 'rss',
            message: 'Feed refresh failed for ${feed.name}: $friendly',
            details:
                'URL: ${feed.url}\n'
                'Exception: ${error.runtimeType}: $error\n$stackTrace',
          );
        }
      }
      inbox.sort((a, b) => a.eventDate.compareTo(b.eventDate));
    } finally {
      isRefreshingFeeds = false;
      _changed();
    }
    return FeedRefreshResult(added: added, checked: checked, errors: errors);
  }

  ActivityIdea importInboxItem(RssInboxItem item) {
    final activity = ActivityIdea(
      id: _newId('activity'),
      name: normalizeAllCapsTitle(item.title),
      rangeKind: DateRangeKind.exact,
      firstDate: dateOnly(item.eventDate),
      startPart: item.startPart,
      slotLength: item.slotLength,
      needsBooking: true,
      people: const [],
      url: item.link.trim().isEmpty ? null : item.link.trim(),
      createdAt: DateTime.now(),
    );
    activities.add(activity);
    final index = inbox.indexWhere((candidate) => candidate.id == item.id);
    if (index != -1) inbox[index] = item.copyWith(imported: true);
    _changed();
    return activity;
  }

  void dismissInboxItem(String id) {
    inbox.removeWhere((item) => item.id == id);
    _changed();
  }

  String? calendarEventAt(DateTime friday, int slotIndex) =>
      _calendarSlotTitles[_slotKey(friday, slotIndex)];

  Future<bool> setCalendarEnabled(bool enabled) async {
    if (!enabled) {
      calendarEnabled = false;
      _calendarSlotTitles.clear();
      _appendLog(
        category: 'calendar',
        message: 'Android calendar overlay disabled.',
      );
      _changed();
      return true;
    }
    if (!PlatformServices.calendarSupported) return false;
    try {
      final granted = await PlatformServices.requestCalendarAccess();
      calendarEnabled = granted;
      _appendLog(
        level: granted ? 'info' : 'warning',
        category: 'calendar',
        message: granted
            ? 'Android calendar permission granted.'
            : 'Android calendar permission was denied.',
      );
      _changed();
      if (granted) await refreshCalendarForWeekends();
      return granted;
    } on Object catch (error, stackTrace) {
      _appendLog(
        level: 'error',
        category: 'calendar',
        message: 'Could not request Android calendar access.',
        details: '$error\n$stackTrace',
      );
      _changed();
      return false;
    }
  }

  Future<void> refreshCalendarForWeekends({int weeks = 8}) async {
    if (!calendarEnabled ||
        !PlatformServices.calendarSupported ||
        isRefreshingCalendar) {
      return;
    }
    isRefreshingCalendar = true;
    notifyListeners();
    try {
      final granted = await PlatformServices.hasCalendarAccess();
      if (!granted) {
        calendarEnabled = false;
        _calendarSlotTitles.clear();
        _appendLog(
          level: 'warning',
          category: 'calendar',
          message: 'Calendar permission is no longer available.',
        );
        return;
      }
      final firstFriday = firstRelevantFriday(DateTime.now());
      final events = await PlatformServices.queryCalendarEvents(
        start: slotStart(firstFriday, 0),
        end: addDays(firstFriday, weeks * 7 + 3),
      );
      events.sort((a, b) => a.start.compareTo(b.start));
      _calendarSlotTitles.clear();
      for (var week = 0; week < weeks; week++) {
        final friday = addDays(firstFriday, week * 7);
        for (
          var slotIndex = 0;
          slotIndex < WeekendSlot.all.length;
          slotIndex++
        ) {
          final start = slotStart(friday, slotIndex);
          final end = slotEnd(friday, slotIndex);
          for (final event in events) {
            if (event.end.isAfter(start) && event.start.isBefore(end)) {
              _calendarSlotTitles[_slotKey(friday, slotIndex)] = event.title;
              break;
            }
          }
        }
      }
      _appendLog(
        category: 'calendar',
        message: 'Read ${events.length} Android calendar events.',
        details: 'Window: ${firstFriday.toIso8601String()} · $weeks weekends',
      );
    } on Object catch (error, stackTrace) {
      _appendLog(
        level: 'error',
        category: 'calendar',
        message: 'Android calendar query failed.',
        details: '$error\n$stackTrace',
      );
    } finally {
      isRefreshingCalendar = false;
      _changed();
    }
  }

  Future<void> exportDatabase() async {
    _appendLog(
      category: 'database',
      message: 'Database export requested.',
      details: 'Schema version: $currentSchemaVersion',
    );
    await _persist();
    final filename =
        'weekend-planner-${isoDate(DateTime.now())}-v$currentSchemaVersion.json';
    await PlatformServices.exportDatabase(databaseJson(pretty: true), filename);
    notifyListeners();
  }

  String databaseJson({bool pretty = false}) {
    final state = _stateJson();
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(state)
        : jsonEncode(state);
  }

  void clearEventLog() {
    eventLog.clear();
    _changed();
  }

  void _cachePerson(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) return;
    final exists = cachedPeople.any(
      (person) => person.toLowerCase() == normalized.toLowerCase(),
    );
    if (!exists) {
      cachedPeople.add(normalized);
      cachedPeople.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
  }

  void _appendLog({
    String level = 'info',
    required String category,
    required String message,
    String? details,
  }) {
    eventLog.insert(
      0,
      DiagnosticLogEntry(
        timestamp: DateTime.now(),
        level: level,
        category: category,
        message: message,
        details: details,
      ),
    );
    if (eventLog.length > _maxLogEntries) {
      eventLog.removeRange(_maxLogEntries, eventLog.length);
    }
  }

  void _changed() {
    notifyListeners();
    unawaited(_persist());
  }

  Map<String, dynamic> _stateJson() => {
    'schemaVersion': currentSchemaVersion,
    'activities': activities.map((item) => item.toJson()).toList(),
    'assignments': assignments.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'cachedPeople': cachedPeople,
    'feeds': feeds.map((item) => item.toJson()).toList(),
    'inbox': inbox.map((item) => item.toJson()).toList(),
    'settings': {'calendarEnabled': calendarEnabled},
    'eventLog': eventLog.map((item) => item.toJson()).toList(),
  };

  Future<void> _persist() =>
      _preferences.setString(_storageKey, jsonEncode(_stateJson()));

  void _restore(Map<String, dynamic> json) {
    activities = (json['activities'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ActivityIdea.fromJson)
        .toList();
    assignments = (json['assignments'] as Map<String, dynamic>? ?? const {})
        .map(
          (key, value) => MapEntry(
            key,
            SlotAssignment.fromJson(value as Map<String, dynamic>),
          ),
        );
    cachedPeople = (json['cachedPeople'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList();
    feeds = (json['feeds'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RssFeed.fromJson)
        .toList();
    inbox = (json['inbox'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RssInboxItem.fromJson)
        .toList();
    eventLog = (json['eventLog'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(DiagnosticLogEntry.fromJson)
        .take(_maxLogEntries)
        .toList();
    final settings = json['settings'];
    if (settings is Map<String, dynamic>) {
      calendarEnabled = settings['calendarEnabled'] as bool? ?? false;
    }
  }

  bool _removeLegacySampleData() {
    const sampleIds = {
      'seed-trek',
      'seed-film',
      'seed-bouldering',
      'seed-wine',
      'seed-museum',
    };
    final before = activities.length;
    activities.removeWhere((activity) => sampleIds.contains(activity.id));
    assignments.removeWhere(
      (_, assignment) => sampleIds.contains(assignment.activityId),
    );
    if (before == activities.length) return false;

    const sampleNames = {
      'elena',
      'giovanni',
      'luca',
      'marta',
      'pietro',
      'sara',
    };
    final usedNames = activities
        .expand((activity) => activity.people)
        .map((person) => person.name.toLowerCase())
        .toSet();
    cachedPeople.removeWhere(
      (name) =>
          sampleNames.contains(name.toLowerCase()) &&
          !usedNames.contains(name.toLowerCase()),
    );
    return true;
  }

  List<RssInboxItem> _parseFeed(RssFeed feed, String source) {
    final document = XmlDocument.parse(source);
    final nodes = document.descendants
        .whereType<XmlElement>()
        .where(
          (element) =>
              element.name.local == 'item' || element.name.local == 'entry',
        )
        .take(100);
    return [
      for (final node in nodes)
        if (_textOf(node, 'title').trim().isNotEmpty)
          _inboxItemFromNode(feed, node),
    ];
  }

  Future<_FetchedFeed> _fetchFeed(String sourceUrl) async {
    final original = Uri.parse(sourceUrl);
    final first = await _getFeedUrl(original);
    _ensureSuccess(first);

    final serverDiscovered = first.headers['x-rss-discovered-url'];
    final finalUrl = first.headers['x-rss-final-url'];
    if (serverDiscovered != null && serverDiscovered.isNotEmpty) {
      _appendLog(
        category: 'http',
        message: 'RSS proxy discovered a feed in HTML metadata.',
        details: 'Page: $sourceUrl\nFeed: $serverDiscovered',
      );
      return _FetchedFeed(
        body: _decodeFeedResponse(first),
        url: serverDiscovered,
        discoveredTitle: _decodeHeader(first.headers['x-rss-discovered-title']),
      );
    }
    if (_looksLikeXmlFeed(first)) {
      return _FetchedFeed(
        body: _decodeFeedResponse(first),
        url: finalUrl ?? sourceUrl,
      );
    }

    final document = html_parser.parse(_decodeFeedResponse(first));
    for (final link in document.querySelectorAll('link[href]')) {
      final relationships =
          link.attributes['rel']?.toLowerCase().split(RegExp(r'\s+')).toSet() ??
          const <String>{};
      final type = link.attributes['type']?.toLowerCase() ?? '';
      final isFeed =
          relationships.contains('alternate') &&
          (type.contains('rss') ||
              type.contains('atom') ||
              type.contains('xml'));
      if (!isFeed) continue;
      final href = link.attributes['href'];
      if (href == null || href.trim().isEmpty) continue;
      final discovered = Uri.parse(finalUrl ?? sourceUrl).resolve(href.trim());
      _appendLog(
        category: 'http',
        message: 'Discovered RSS feed in HTML metadata.',
        details: 'Page: $sourceUrl\nFeed: $discovered',
      );
      final response = await _getFeedUrl(discovered);
      _ensureSuccess(response);
      if (!_looksLikeXmlFeed(response)) {
        throw const FormatException(
          'The discovered RSS link did not return a feed.',
        );
      }
      return _FetchedFeed(
        body: _decodeFeedResponse(response),
        url: discovered.toString(),
        discoveredTitle: link.attributes['title']?.trim(),
      );
    }
    throw const FormatException('No RSS or Atom feed was found on that page.');
  }

  Future<http.Response> _getFeedUrl(Uri target) async {
    final requestUri = kIsWeb
        ? Uri(path: '/rss-proxy', queryParameters: {'url': target.toString()})
        : target;
    _appendLog(
      category: 'http',
      message: 'GET $target',
      details: kIsWeb
          ? 'Transport: same-origin /rss-proxy\n'
                'Accept: RSS, Atom, XML, HTML\nTimeout: 18 seconds'
          : 'Transport: direct\nAccept: RSS, Atom, XML, HTML\n'
                'User-Agent: $_browserUserAgent\nTimeout: 18 seconds',
    );
    try {
      final response = await http
          .get(
            requestUri,
            headers: {
              'Accept':
                  'application/rss+xml, application/atom+xml, '
                  'application/xml, text/xml, text/html',
              'Accept-Language': 'it-IT,it;q=0.9,en;q=0.8',
              if (!kIsWeb) 'User-Agent': _browserUserAgent,
            },
          )
          .timeout(const Duration(seconds: 18));
      final headers = [
        'Status: HTTP ${response.statusCode}',
        'Content-Type: ${response.headers['content-type'] ?? '(missing)'}',
        'Bytes: ${response.bodyBytes.length}',
        if (response.headers['x-rss-final-url'] != null)
          'Final URL: ${response.headers['x-rss-final-url']}',
        if (response.headers['x-rss-discovered-url'] != null)
          'Discovered URL: ${response.headers['x-rss-discovered-url']}',
        if (response.statusCode < 200 || response.statusCode >= 300)
          'Response preview: ${_preview(response.body)}',
      ].join('\n');
      _appendLog(
        level: response.statusCode >= 200 && response.statusCode < 300
            ? 'info'
            : 'error',
        category: 'http',
        message: 'GET $target → HTTP ${response.statusCode}',
        details: headers,
      );
      return response;
    } on Object catch (error, stackTrace) {
      _appendLog(
        level: 'error',
        category: 'http',
        message: 'GET $target failed before a response was received.',
        details: '${error.runtimeType}: $error\n$stackTrace',
      );
      rethrow;
    }
  }

  static void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = _preview(response.body);
      throw FormatException(
        detail.isEmpty
            ? 'HTTP ${response.statusCode}'
            : 'HTTP ${response.statusCode}: $detail',
      );
    }
  }

  static bool _looksLikeXmlFeed(http.Response response) {
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.contains('rss') || contentType.contains('atom')) {
      return true;
    }
    final trimmed = _decodeFeedResponse(response).trimLeft();
    final sample = trimmed.substring(0, trimmed.length.clamp(0, 500));
    return RegExp(
      r'<(?:rss|feed|rdf:RDF)\b',
      caseSensitive: false,
    ).hasMatch(sample);
  }

  RssInboxItem _inboxItemFromNode(RssFeed feed, XmlElement node) {
    final rawTitle = _textOf(node, 'title').trim();
    final title = normalizeAllCapsTitle(rawTitle);
    final description = [
      _textOf(node, 'description'),
      _textOf(node, 'summary'),
      _textOf(node, 'content'),
    ].join(' ');
    final dateText = [
      description,
      rawTitle,
      _textOf(node, 'pubDate'),
      _textOf(node, 'published'),
      _textOf(node, 'updated'),
      _textOf(node, 'date'),
    ].join(' ');
    final eventDate = _extractDate(dateText) ?? DateTime.now();
    final guid = _textOf(node, 'guid').trim();
    var link = _textOf(node, 'link').trim();
    if (link.isEmpty) {
      for (final element in node.childElements) {
        if (element.name.local == 'link' &&
            element.getAttribute('href') != null) {
          link = element.getAttribute('href')!;
          break;
        }
      }
    }
    final stable = guid.isNotEmpty ? guid : '$rawTitle|$link';
    return RssInboxItem(
      id: '${feed.id}-${_stableHash(stable)}',
      feedId: feed.id,
      source: feed.name,
      title: title,
      link: link,
      eventDate: eventDate,
      startPart: inferDayPart(eventDate),
      slotLength: 1,
    );
  }

  static String _textOf(XmlElement parent, String localName) {
    for (final element in parent.descendants.whereType<XmlElement>()) {
      if (element.name.local == localName) return element.innerText;
    }
    return '';
  }

  static String _decodeFeedResponse(http.Response response) {
    final bytes = response.bodyBytes;
    if (bytes.isEmpty) return '';
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    final prefix = ascii
        .decode(bytes.take(160).toList(), allowInvalid: true)
        .toLowerCase();
    final declaresLatin1 =
        contentType.contains('charset=iso-8859-1') ||
        contentType.contains('charset=latin1') ||
        prefix.contains('encoding="iso-8859-1"') ||
        prefix.contains("encoding='iso-8859-1'");
    if (declaresLatin1) return latin1.decode(bytes);
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  static String? _decodeHeader(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return Uri.decodeComponent(value);
    } on FormatException {
      return value;
    }
  }

  static DateTime? _extractDate(String text) {
    final iso = RegExp(
      r'\b(20\d\d)-(\d\d)-(\d\d)(?:[T ](\d\d):(\d\d))?',
    ).firstMatch(text);
    if (iso != null) {
      return DateTime(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
        int.tryParse(iso.group(4) ?? '') ?? 15,
        int.tryParse(iso.group(5) ?? '') ?? 0,
      );
    }
    return DateTime.tryParse(text.trim());
  }

  static int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  static String _friendlyFeedError(Object error) {
    if (error is TimeoutException) return 'request timed out';
    if (error is XmlParserException) return 'the response is not valid RSS';
    if (error is FormatException) return error.message.toString();
    return '${error.runtimeType}: $error';
  }

  static String _preview(String value) {
    final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return trimmed.substring(0, trimmed.length.clamp(0, 2000));
  }

  static String _slotKey(DateTime friday, int slotIndex) =>
      '${isoDate(friday)}#$slotIndex';

  static String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}
