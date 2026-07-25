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
    required this.kind,
    this.discoveredTitle,
  });

  final String body;
  final String url;
  final FeedKind kind;
  final String? discoveredTitle;
}

class PlannerStore extends ChangeNotifier {
  PlannerStore._(this._preferences, this._httpClient);

  static const currentSchemaVersion = 3;
  static const _storageKey = 'weekend_planner_state_v3';
  static const _legacyStorageKeyV2 = 'weekend_planner_state_v2';
  static const _legacyStorageKeyV1 = 'weekend_planner_state_v1';
  static const _maxLogEntries = 250;
  static const feedRefreshInterval = Duration(minutes: 30);
  static const _browserUserAgent =
      'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/138.0.0.0 Mobile Safari/537.36';

  final SharedPreferences _preferences;
  final http.Client? _httpClient;
  Timer? _feedRefreshTimer;

  List<ActivityIdea> activities = [];
  Map<String, SlotAssignment> assignments = {};
  List<String> cachedPeople = [];
  List<RssFeed> feeds = [];
  List<RssInboxItem> inbox = [];
  List<DiagnosticLogEntry> eventLog = [];
  List<PlannerSlot> enabledSlots = List.from(PlannerSlot.defaults);
  bool calendarEnabled = false;
  bool calendarSelectionInitialized = false;
  Set<String> includedCalendarIds = {};
  List<DeviceCalendar> availableCalendars = [];
  bool isRefreshingFeeds = false;
  bool isRefreshingCalendar = false;
  final Map<String, String> _calendarSlotTitles = {};

  static Future<PlannerStore> load({http.Client? httpClient}) async {
    final preferences = await SharedPreferences.getInstance();
    final store = PlannerStore._(preferences, httpClient);
    final currentEncoded = preferences.getString(_storageKey);
    final encoded =
        currentEncoded ??
        preferences.getString(_legacyStorageKeyV2) ??
        preferences.getString(_legacyStorageKeyV1);
    if (encoded == null) {
      await store._persist();
      return store;
    }

    try {
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final sourceVersion = (decoded['schemaVersion'] as num?)?.toInt() ?? 1;
      final migrated = _migrateDatabase(decoded);
      store._restore(migrated);
      final samplesRemoved = store._removeLegacySampleData();
      if (currentEncoded == null ||
          sourceVersion != currentSchemaVersion ||
          samplesRemoved) {
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
    var database = Map<String, dynamic>.from(source);
    var version = (database['schemaVersion'] as num?)?.toInt() ?? 1;
    if (version > currentSchemaVersion) {
      throw FormatException(
        'Database schema $version is newer than supported schema '
        '$currentSchemaVersion.',
      );
    }
    while (version < currentSchemaVersion) {
      switch (version) {
        case 1:
          database = _migrateV1ToV2(database);
          version = 2;
        case 2:
          database = _migrateV2ToV3(database);
          version = 3;
        default:
          throw StateError(
            'No migration registered for database schema $version.',
          );
      }
    }
    database['schemaVersion'] = currentSchemaVersion;
    return database;
  }

  static Map<String, dynamic> _migrateV1ToV2(Map<String, dynamic> source) {
    final database = Map<String, dynamic>.from(source);
    final activities = source['activities'];
    if (activities is List<dynamic>) {
      database['activities'] = activities.map((rawActivity) {
        if (rawActivity is! Map<String, dynamic>) return rawActivity;
        final activity = Map<String, dynamic>.from(rawActivity);
        activity['startDay'] = null;
        activity['frequencyCounterResetAt'] = null;
        return activity;
      }).toList();
    }
    database['schemaVersion'] = 2;
    return database;
  }

  static Map<String, dynamic> _migrateV2ToV3(Map<String, dynamic> source) {
    final database = Map<String, dynamic>.from(source);
    const oldSlots = <({int dayOffset, String part})>[
      (dayOffset: 0, part: 'night'),
      (dayOffset: 1, part: 'morning'),
      (dayOffset: 1, part: 'afternoon'),
      (dayOffset: 1, part: 'night'),
      (dayOffset: 2, part: 'morning'),
      (dayOffset: 2, part: 'afternoon'),
      (dayOffset: 2, part: 'night'),
    ];
    final migratedAssignments = <String, dynamic>{};
    final rawAssignments = source['assignments'];
    if (rawAssignments is Map<String, dynamic>) {
      for (final entry in rawAssignments.entries) {
        final separator = entry.key.lastIndexOf('#');
        final friday = separator <= 0
            ? null
            : DateTime.tryParse(entry.key.substring(0, separator));
        final oldIndex = separator <= 0
            ? null
            : int.tryParse(entry.key.substring(separator + 1));
        if (friday == null ||
            oldIndex == null ||
            oldIndex < 0 ||
            oldIndex >= oldSlots.length) {
          continue;
        }
        final oldSlot = oldSlots[oldIndex];
        final date = addDays(dateOnly(friday), oldSlot.dayOffset);
        final key = '${isoDate(date)}#${oldSlot.part}';
        final assignment = entry.value is Map<String, dynamic>
            ? Map<String, dynamic>.from(entry.value as Map<String, dynamic>)
            : <String, dynamic>{};
        final part = (assignment['part'] as num?)?.toInt() ?? 1;
        final startIndex = oldIndex - part + 1;
        if (startIndex >= 0 && startIndex < oldSlots.length) {
          final startSlot = oldSlots[startIndex];
          final startDate = addDays(dateOnly(friday), startSlot.dayOffset);
          assignment['startKey'] = '${isoDate(startDate)}#${startSlot.part}';
        } else {
          assignment['startKey'] = key;
        }
        migratedAssignments[key] = assignment;
      }
    }
    database['assignments'] = migratedAssignments;

    final feeds = source['feeds'];
    if (feeds is List<dynamic>) {
      database['feeds'] = feeds.map((rawFeed) {
        if (rawFeed is! Map<String, dynamic>) return rawFeed;
        return Map<String, dynamic>.from(rawFeed)..['kind'] = FeedKind.rss.name;
      }).toList();
    }
    final inbox = source['inbox'];
    if (inbox is List<dynamic>) {
      database['inbox'] = inbox.map((rawItem) {
        if (rawItem is! Map<String, dynamic>) return rawItem;
        return Map<String, dynamic>.from(rawItem)..['locationName'] = null;
      }).toList();
    }

    final oldSettings = source['settings'];
    final settings = oldSettings is Map<String, dynamic>
        ? Map<String, dynamic>.from(oldSettings)
        : <String, dynamic>{};
    settings['enabledSlots'] = PlannerSlot.defaults
        .map((slot) => slot.id)
        .toList();
    settings['calendarSelectionInitialized'] = false;
    settings['includedCalendarIds'] = <String>[];
    database['settings'] = settings;
    database['schemaVersion'] = 3;
    return database;
  }

  ActivityIdea? activityById(String id) {
    for (final activity in activities) {
      if (activity.id == id) return activity;
    }
    return null;
  }

  SlotAssignment? assignmentAt(DateTime weekStart, int slotIndex) =>
      assignments[_slotKey(weekStart, enabledSlots[slotIndex])];

  List<ActivityPlacement> placementsForActivity(String activityId) {
    final placements = <ActivityPlacement>[];
    for (final entry in assignments.entries) {
      if (entry.value.activityId != activityId ||
          (entry.value.startKey != null && entry.value.startKey != entry.key) ||
          (entry.value.startKey == null && entry.value.part != 1)) {
        continue;
      }
      final separator = entry.key.lastIndexOf('#');
      if (separator <= 0) continue;
      final date = DateTime.tryParse(entry.key.substring(0, separator));
      final partName = entry.key.substring(separator + 1);
      if (date == null) continue;
      final part = DayPart.values
          .where((candidate) => candidate.name == partName)
          .firstOrNull;
      if (part == null) continue;
      placements.add(
        ActivityPlacement(
          date: dateOnly(date),
          slot: PlannerSlot(inferWeekDay(date), part),
          slotLength: entry.value.total,
        ),
      );
    }
    placements.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0
          ? byDate
          : b.slot.part.index.compareTo(a.slot.part.index);
    });
    return placements;
  }

  String? frequencyWarning(ActivityIdea activity, {DateTime? now}) {
    final frequency = activity.desiredFrequencyWeeks;
    if (!activity.isRecurring || frequency == null) return null;
    final placements = placementsForActivity(activity.id);
    final currentFriday = firstRelevantFriday(now ?? DateTime.now());
    final latestPlacement = placements.isEmpty
        ? null
        : firstRelevantFriday(placements.first.date);
    final counterReset = activity.frequencyCounterResetAt;
    final resetFriday = counterReset == null
        ? null
        : firstRelevantFriday(counterReset);
    final resetIsLatest =
        resetFriday != null &&
        (latestPlacement == null || resetFriday.isAfter(latestPlacement));
    final reference = resetIsLatest ? resetFriday : latestPlacement;
    if (reference != null && !reference.isBefore(currentFriday)) {
      return null;
    }
    if (reference == null) {
      return 'Not done yet · goal: ${activity.frequencyLabel!.toLowerCase()}';
    }
    final weekendsSince = currentFriday.difference(reference).inDays ~/ 7;
    if (weekendsSince < frequency) return null;
    final referenceLabel = resetIsLatest ? 'counter reset' : 'last time';
    return '$weekendsSince weekends since $referenceLabel · '
        'goal: ${activity.frequencyLabel!.toLowerCase()}';
  }

  String? fitProblem(ActivityIdea activity, DateTime weekStart, int slotIndex) {
    final selectedSlot = enabledSlots[slotIndex];
    if (activity.startDay != null &&
        activity.startDay != selectedSlot.weekDay) {
      return 'Starts on ${weekDayLabel(activity.startDay!)}, not '
          '${selectedSlot.day}.';
    }
    if (activity.startPart != null && activity.startPart != selectedSlot.part) {
      return 'Starts a ${activity.startPart!.name}, not a '
          '${selectedSlot.part.name}.';
    }
    if (slotIndex + activity.slotLength > enabledSlots.length) {
      return 'Needs ${activity.slotLength} slots, but the week ends first.';
    }
    if (!activity.isAvailableAt(slotDate(weekStart, slotIndex, enabledSlots))) {
      return 'Outside its date range.';
    }
    for (
      var index = slotIndex;
      index < slotIndex + activity.slotLength;
      index++
    ) {
      if (assignmentAt(weekStart, index) != null) {
        return 'Needs ${activity.slotLength} free '
            '${activity.slotLength == 1 ? 'slot' : 'slots'} from here.';
      }
    }
    return null;
  }

  void assign(ActivityIdea activity, DateTime weekStart, int slotIndex) {
    final startKey = _slotKey(weekStart, enabledSlots[slotIndex]);
    for (var offset = 0; offset < activity.slotLength; offset++) {
      assignments[_slotKey(
        weekStart,
        enabledSlots[slotIndex + offset],
      )] = SlotAssignment(
        activityId: activity.id,
        part: offset + 1,
        total: activity.slotLength,
        startKey: startKey,
      );
    }
    _changed();
  }

  void clearAssignment(DateTime weekStart, int slotIndex) {
    final current = assignmentAt(weekStart, slotIndex);
    if (current == null) return;
    final selectedKey = _slotKey(weekStart, enabledSlots[slotIndex]);
    final startKey = current.startKey ?? selectedKey;
    assignments.removeWhere(
      (key, assignment) =>
          (assignment.startKey ?? key) == startKey &&
          assignment.activityId == current.activityId,
    );
    _changed();
  }

  void setSlotEnabled(PlannerSlot slot, bool enabled) {
    final updated = enabledSlots.where((item) => item.id != slot.id).toList();
    if (enabled) updated.add(slot);
    updated.sort(_compareSlots);
    if (updated.isEmpty) return;
    enabledSlots = updated;
    _calendarSlotTitles.clear();
    _changed();
    unawaited(refreshCalendarForWeeks());
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

  void resetFrequencyCounter(String activityId, {DateTime? now}) {
    final index = activities.indexWhere((item) => item.id == activityId);
    if (index == -1) return;
    final activity = activities[index];
    if (!activity.isRecurring || activity.desiredFrequencyWeeks == null) {
      return;
    }
    activities[index] = activity.copyWith(
      frequencyCounterResetAt: firstRelevantFriday(now ?? DateTime.now()),
    );
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

  bool addPerson(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty ||
        cachedPeople.any(
          (person) => person.toLowerCase() == normalized.toLowerCase(),
        )) {
      return false;
    }
    _cachePerson(normalized);
    _changed();
    return true;
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
    final path = uri.path.toLowerCase();
    final feed = RssFeed(
      id: _newId('feed'),
      name: name,
      url: uri.toString(),
      kind: path.endsWith('.ics') ? FeedKind.ics : FeedKind.rss,
    );
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

  Future<FeedRefreshResult> refreshFeeds({
    String? onlyFeedId,
    String reason = 'manual',
  }) async {
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
            kind: fetched.kind,
            name: fetched.discoveredTitle,
            lastChecked: DateTime.now(),
          );
          final parsed = switch (fetched.kind) {
            FeedKind.rss => _parseXmlFeed(refreshedFeed, fetched.body),
            FeedKind.ics => _parseIcsFeed(refreshedFeed, fetched.body),
          };
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
            category: 'feed',
            message:
                'Parsed ${parsed.length} ${fetched.kind.name.toUpperCase()} '
                'entries from ${feed.name}.',
            details:
                'Effective feed URL: ${fetched.url}\n'
                'Refresh reason: $reason',
          );
        } on Object catch (error, stackTrace) {
          final friendly = _friendlyFeedError(error);
          errors.add('${feed.name}: $friendly');
          _appendLog(
            level: 'error',
            category: 'feed',
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
      startDay: inferWeekDay(item.eventDate),
      startPart: item.startPart,
      slotLength: item.slotLength,
      needsBooking: true,
      people: const [],
      location: item.locationName == null
          ? null
          : ActivityLocation(name: item.locationName!),
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

  void startPeriodicFeedRefresh({Duration interval = feedRefreshInterval}) {
    _feedRefreshTimer?.cancel();
    unawaited(refreshFeedsIfDue(maxAge: interval));
    _feedRefreshTimer = Timer.periodic(
      interval,
      (_) => unawaited(refreshFeedsIfDue(maxAge: interval)),
    );
  }

  void stopPeriodicFeedRefresh() {
    _feedRefreshTimer?.cancel();
    _feedRefreshTimer = null;
  }

  Future<FeedRefreshResult> refreshFeedsIfDue({
    Duration maxAge = feedRefreshInterval,
  }) async {
    if (feeds.isEmpty || isRefreshingFeeds) {
      return const FeedRefreshResult(added: 0, checked: 0, errors: []);
    }
    final cutoff = DateTime.now().subtract(maxAge);
    final due = feeds
        .where(
          (feed) =>
              feed.lastChecked == null || feed.lastChecked!.isBefore(cutoff),
        )
        .map((feed) => feed.id)
        .toList();
    if (due.isEmpty) {
      return const FeedRefreshResult(added: 0, checked: 0, errors: []);
    }
    var added = 0;
    var checked = 0;
    final errors = <String>[];
    for (final id in due) {
      final result = await refreshFeeds(
        onlyFeedId: id,
        reason: 'periodic; older than ${maxAge.inMinutes} minutes',
      );
      added += result.added;
      checked += result.checked;
      errors.addAll(result.errors);
    }
    return FeedRefreshResult(added: added, checked: checked, errors: errors);
  }

  String? calendarEventAt(DateTime weekStart, int slotIndex) =>
      _calendarSlotTitles[_slotKey(weekStart, enabledSlots[slotIndex])];

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
      if (granted) {
        await loadDeviceCalendars();
        await refreshCalendarForWeeks();
      }
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

  Future<void> loadDeviceCalendars() async {
    if (!calendarEnabled || !PlatformServices.calendarSupported) return;
    try {
      final calendars = await PlatformServices.queryCalendars();
      calendars.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      availableCalendars = calendars;
      if (!calendarSelectionInitialized) {
        includedCalendarIds = calendars.map((calendar) => calendar.id).toSet();
        calendarSelectionInitialized = true;
      } else {
        final availableIds = calendars.map((calendar) => calendar.id).toSet();
        includedCalendarIds = includedCalendarIds.intersection(availableIds);
      }
      _appendLog(
        category: 'calendar',
        message: 'Found ${calendars.length} Android calendars.',
        details:
            'Included: ${includedCalendarIds.length}\n'
            '${calendars.map((calendar) => '${calendar.id}: ${calendar.name}').join('\n')}',
      );
      _changed();
    } on Object catch (error, stackTrace) {
      _appendLog(
        level: 'error',
        category: 'calendar',
        message: 'Could not list Android calendars.',
        details: '$error\n$stackTrace',
      );
      _changed();
    }
  }

  void setCalendarIncluded(String id, bool included) {
    calendarSelectionInitialized = true;
    if (included) {
      includedCalendarIds.add(id);
    } else {
      includedCalendarIds.remove(id);
    }
    _calendarSlotTitles.clear();
    _changed();
    unawaited(refreshCalendarForWeeks());
  }

  Future<void> refreshCalendarForWeeks({int weeks = 8}) async {
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
      if (availableCalendars.isEmpty) await loadDeviceCalendars();
      if (includedCalendarIds.isEmpty) {
        _calendarSlotTitles.clear();
        _appendLog(
          category: 'calendar',
          message: 'Calendar overlay refreshed with no calendars included.',
        );
        return;
      }
      final firstWeek = firstRelevantWeekStart(DateTime.now(), enabledSlots);
      final events = await PlatformServices.queryCalendarEvents(
        start: slotStart(firstWeek, 0, enabledSlots),
        end: addDays(firstWeek, weeks * 7 + 1),
        calendarIds: includedCalendarIds.toList(),
      );
      events.sort((a, b) => a.start.compareTo(b.start));
      _calendarSlotTitles.clear();
      for (var week = 0; week < weeks; week++) {
        final weekStart = addDays(firstWeek, week * 7);
        for (var slotIndex = 0; slotIndex < enabledSlots.length; slotIndex++) {
          final start = slotStart(weekStart, slotIndex, enabledSlots);
          final end = slotEnd(weekStart, slotIndex, enabledSlots);
          for (final event in events) {
            if (event.end.isAfter(start) && event.start.isBefore(end)) {
              _calendarSlotTitles[_slotKey(
                    weekStart,
                    enabledSlots[slotIndex],
                  )] =
                  event.title;
              break;
            }
          }
        }
      }
      _appendLog(
        category: 'calendar',
        message: 'Read ${events.length} Android calendar events.',
        details:
            'Window: ${firstWeek.toIso8601String()} · $weeks weeks\n'
            'Included calendars: ${includedCalendarIds.join(', ')}',
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

  Future<void> refreshCalendarForWeekends({int weeks = 8}) =>
      refreshCalendarForWeeks(weeks: weeks);

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
    'settings': {
      'calendarEnabled': calendarEnabled,
      'enabledSlots': enabledSlots.map((slot) => slot.id).toList(),
      'calendarSelectionInitialized': calendarSelectionInitialized,
      'includedCalendarIds': includedCalendarIds.toList()..sort(),
    },
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
      final restoredSlots =
          (settings['enabledSlots'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .map(PlannerSlot.fromId)
              .whereType<PlannerSlot>()
              .toList()
            ..sort(_compareSlots);
      if (restoredSlots.isNotEmpty) enabledSlots = restoredSlots;
      calendarSelectionInitialized =
          settings['calendarSelectionInitialized'] as bool? ?? false;
      includedCalendarIds =
          (settings['includedCalendarIds'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toSet();
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

  List<RssInboxItem> _parseXmlFeed(RssFeed feed, String source) {
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

  List<RssInboxItem> _parseIcsFeed(RssFeed feed, String source) {
    final unfolded = <String>[];
    for (final line
        in source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
      if ((line.startsWith(' ') || line.startsWith('\t')) &&
          unfolded.isNotEmpty) {
        unfolded[unfolded.length - 1] += line.substring(1);
      } else {
        unfolded.add(line);
      }
    }

    final items = <RssInboxItem>[];
    Map<String, String>? event;
    for (final line in unfolded) {
      final normalized = line.trim();
      if (normalized.toUpperCase() == 'BEGIN:VEVENT') {
        event = <String, String>{};
        continue;
      }
      if (normalized.toUpperCase() == 'END:VEVENT') {
        final values = event;
        event = null;
        if (values == null) continue;
        final rawTitle = _unescapeIcs(values['SUMMARY'] ?? '').trim();
        final eventDate = _parseIcsDate(values['DTSTART'] ?? '');
        if (rawTitle.isEmpty || eventDate == null) continue;
        final uid = values['UID']?.trim();
        final rawUrl =
            values['URL']?.trim() ??
            _firstHttpUrl(values['DESCRIPTION'] ?? '') ??
            '';
        final location = _nonEmptyIcs(values['LOCATION']);
        final stable = uid == null || uid.isEmpty
            ? '$rawTitle|${eventDate.toIso8601String()}|$rawUrl'
            : uid;
        items.add(
          RssInboxItem(
            id: '${feed.id}-${_stableHash(stable)}',
            feedId: feed.id,
            source: feed.name,
            title: normalizeAllCapsTitle(rawTitle),
            link: _unescapeIcs(rawUrl),
            eventDate: eventDate,
            startPart: inferDayPart(eventDate),
            slotLength: 1,
            locationName: location,
          ),
        );
        continue;
      }
      if (event == null) continue;
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final name = line.substring(0, separator).split(';').first.toUpperCase();
      event.putIfAbsent(name, () => line.substring(separator + 1));
    }
    return items.take(500).toList();
  }

  Future<_FetchedFeed> _fetchFeed(String sourceUrl) async {
    final original = Uri.parse(sourceUrl);
    final first = await _getFeedUrl(original);
    _ensureSuccess(first);

    final serverDiscovered =
        first.headers['x-feed-discovered-url'] ??
        first.headers['x-rss-discovered-url'];
    final finalUrl =
        first.headers['x-feed-final-url'] ?? first.headers['x-rss-final-url'];
    if (serverDiscovered != null && serverDiscovered.isNotEmpty) {
      final body = _decodeFeedResponse(first);
      final kind = _looksLikeIcs(first) ? FeedKind.ics : FeedKind.rss;
      _appendLog(
        category: 'http',
        message: 'Feed proxy discovered a source in HTML metadata.',
        details: 'Page: $sourceUrl\nFeed: $serverDiscovered',
      );
      return _FetchedFeed(
        body: body,
        url: serverDiscovered,
        kind: kind,
        discoveredTitle:
            _decodeHeader(
              first.headers['x-feed-discovered-title'] ??
                  first.headers['x-rss-discovered-title'],
            ) ??
            (kind == FeedKind.ics ? _icsCalendarName(body) : null),
      );
    }
    if (_looksLikeIcs(first)) {
      final body = _decodeFeedResponse(first);
      return _FetchedFeed(
        body: body,
        url: finalUrl ?? sourceUrl,
        kind: FeedKind.ics,
        discoveredTitle: _icsCalendarName(body),
      );
    }
    if (_looksLikeXmlFeed(first)) {
      return _FetchedFeed(
        body: _decodeFeedResponse(first),
        url: finalUrl ?? sourceUrl,
        kind: FeedKind.rss,
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
              type.contains('xml') ||
              type.contains('calendar'));
      if (!isFeed) continue;
      final href = link.attributes['href'];
      if (href == null || href.trim().isEmpty) continue;
      final discovered = Uri.parse(finalUrl ?? sourceUrl).resolve(href.trim());
      _appendLog(
        category: 'http',
        message: 'Discovered a feed in HTML metadata.',
        details: 'Page: $sourceUrl\nFeed: $discovered',
      );
      final response = await _getFeedUrl(discovered);
      _ensureSuccess(response);
      final kind = _looksLikeIcs(response) ? FeedKind.ics : FeedKind.rss;
      if (kind == FeedKind.rss && !_looksLikeXmlFeed(response)) {
        throw const FormatException('The discovered link is not a feed.');
      }
      final body = _decodeFeedResponse(response);
      return _FetchedFeed(
        body: body,
        url: discovered.toString(),
        kind: kind,
        discoveredTitle:
            link.attributes['title']?.trim() ??
            (kind == FeedKind.ics ? _icsCalendarName(body) : null),
      );
    }
    throw const FormatException(
      'No RSS, Atom, or iCalendar feed was found on that page.',
    );
  }

  Future<http.Response> _getFeedUrl(Uri target) async {
    final requestUri = kIsWeb
        ? Uri(path: '/feed-proxy', queryParameters: {'url': target.toString()})
        : target;
    _appendLog(
      category: 'http',
      message: 'GET $target',
      details: kIsWeb
          ? 'Transport: same-origin /feed-proxy\n'
                'Accept: RSS, Atom, iCalendar, XML, HTML\nTimeout: 18 seconds'
          : 'Transport: direct\nAccept: RSS, Atom, iCalendar, XML, HTML\n'
                'User-Agent: $_browserUserAgent\nTimeout: 18 seconds',
    );
    try {
      final response =
          await (_httpClient == null
                  ? http.get(
                      requestUri,
                      headers: {
                        'Accept':
                            'application/rss+xml, application/atom+xml, '
                            'text/calendar, application/ics, '
                            'application/xml, text/xml, text/html',
                        'Accept-Language': 'it-IT,it;q=0.9,en;q=0.8',
                        if (!kIsWeb) 'User-Agent': _browserUserAgent,
                      },
                    )
                  : _httpClient.get(
                      requestUri,
                      headers: {
                        'Accept':
                            'application/rss+xml, application/atom+xml, '
                            'text/calendar, application/ics, '
                            'application/xml, text/xml, text/html',
                        'Accept-Language': 'it-IT,it;q=0.9,en;q=0.8',
                        if (!kIsWeb) 'User-Agent': _browserUserAgent,
                      },
                    ))
              .timeout(const Duration(seconds: 18));
      final headers = [
        'Status: HTTP ${response.statusCode}',
        'Content-Type: ${response.headers['content-type'] ?? '(missing)'}',
        'Bytes: ${response.bodyBytes.length}',
        if (response.headers['x-feed-final-url'] != null)
          'Final URL: ${response.headers['x-feed-final-url']}',
        if (response.headers['x-feed-discovered-url'] != null)
          'Discovered URL: ${response.headers['x-feed-discovered-url']}',
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

  static bool _looksLikeIcs(http.Response response) {
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.contains('text/calendar') ||
        contentType.contains('application/ics') ||
        contentType.contains('application/icalendar')) {
      return true;
    }
    final source = _decodeFeedResponse(response).trimLeft();
    final sample = source.substring(0, source.length.clamp(0, 500));
    return RegExp(
      r'^BEGIN:VCALENDAR(?:\r?\n|$)',
      caseSensitive: false,
    ).hasMatch(sample);
  }

  static String? _icsCalendarName(String source) {
    final match = RegExp(
      r'^(?:X-WR-CALNAME|NAME)(?:;[^:]*)?:(.+)$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(source.replaceAll('\r\n ', ''));
    return _nonEmptyIcs(match?.group(1));
  }

  static DateTime? _parseIcsDate(String input) {
    final value = input.trim();
    final date = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(value);
    if (date != null) {
      return DateTime(
        int.parse(date.group(1)!),
        int.parse(date.group(2)!),
        int.parse(date.group(3)!),
        15,
      );
    }
    final dateTime = RegExp(
      r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z)?$',
    ).firstMatch(value);
    if (dateTime == null) return null;
    final values = [
      for (var group = 1; group <= 6; group++)
        int.tryParse(dateTime.group(group) ?? '') ?? 0,
    ];
    if (dateTime.group(7) == 'Z') {
      return DateTime.utc(
        values[0],
        values[1],
        values[2],
        values[3],
        values[4],
        values[5],
      ).toLocal();
    }
    return DateTime(
      values[0],
      values[1],
      values[2],
      values[3],
      values[4],
      values[5],
    );
  }

  static String _unescapeIcs(String value) => value
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\N', '\n')
      .replaceAll(r'\,', ',')
      .replaceAll(r'\;', ';')
      .replaceAll('\\\\', '\\');

  static String? _nonEmptyIcs(String? value) {
    final normalized = value == null ? null : _unescapeIcs(value).trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String? _firstHttpUrl(String value) => RegExp(
    r'https?://[^\s\\]+',
    caseSensitive: false,
  ).firstMatch(value)?.group(0);

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
    if (error is XmlParserException) return 'the response is not valid XML';
    if (error is FormatException) return error.message.toString();
    return '${error.runtimeType}: $error';
  }

  static String _preview(String value) {
    final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return trimmed.substring(0, trimmed.length.clamp(0, 2000));
  }

  static String _slotKey(DateTime weekStart, PlannerSlot slot) =>
      '${isoDate(slotDateFor(weekStart, slot))}#${slot.part.name}';

  static int _compareSlots(PlannerSlot a, PlannerSlot b) {
    final byDay = a.weekDay.index.compareTo(b.weekDay.index);
    return byDay != 0 ? byDay : a.part.index.compareTo(b.part.index);
  }

  static String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}
