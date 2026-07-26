import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weekend_planner/location_parser.dart';
import 'package:weekend_planner/main.dart';
import 'package:weekend_planner/models.dart';
import 'package:weekend_planner/planner_store.dart';
import 'package:weekend_planner/screens/activities_page.dart';
import 'package:weekend_planner/screens/activity_detail_page.dart';
import 'package:weekend_planner/screens/activity_form_page.dart';
import 'package:weekend_planner/screens/activity_picker_page.dart';
import 'package:weekend_planner/screens/inbox_page.dart';
import 'package:weekend_planner/screens/people_page.dart';
import 'package:weekend_planner/screens/weekends_page.dart';

void main() {
  testWidgets('shows the upcoming weekend slots', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await PlannerStore.load();

    await tester.pumpWidget(WeekendPlannerApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('Planner'), findsWidgets);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('Saturday'), findsWidgets);
    expect(find.text('Sunday'), findsWidgets);
  });

  testWidgets('hides past days from the current weekend', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await PlannerStore.load();
    final saturday = DateTime(2026, 7, 25, 9);
    final friday = firstRelevantFriday(saturday);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekendsPage(store: store, now: saturday),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('weekend-day-${isoDate(friday)}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('weekend-day-${isoDate(addDays(friday, 1))}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('weekend-day-${isoDate(addDays(friday, 2))}')),
      findsOneWidget,
    );
  });

  testWidgets('activity editor fits a phone viewport', (tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = await PlannerStore.load();

    await tester.pumpWidget(MaterialApp(home: ActivityFormPage(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('Available at any date.'), findsOneWidget);
    expect(find.text('Day of week'), findsOneWidget);
    expect(find.text('Any time'), findsOneWidget);
    expect(find.text('1w'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity tags autocomplete from existing activities', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = await PlannerStore.load();
    store.activities.add(
      ActivityIdea(
        id: 'hike',
        name: 'Mountain hike',
        rangeKind: DateRangeKind.anytime,
        firstDate: DateTime(2026, 7, 26),
        startPart: DayPart.morning,
        slotLength: 2,
        people: const [],
        tags: const ['Outdoors'],
      ),
    );

    await tester.pumpWidget(MaterialApp(home: ActivityFormPage(store: store)));
    await tester.pumpAndSettle();

    final tagField = find.ancestor(
      of: find.byIcon(Icons.tag_rounded).first,
      matching: find.byType(TextField),
    );
    await tester.enterText(tagField, 'out');
    await tester.pumpAndSettle();

    expect(find.text('Outdoors'), findsOneWidget);
    await tester.tap(find.text('Outdoors'));
    await tester.pumpAndSettle();
    expect(find.text('#Outdoors'), findsOneWidget);
  });

  testWidgets('activity picker assigns by tapping the whole entry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = await PlannerStore.load();
    final weekStart = firstRelevantWeekStart(
      DateTime.now(),
      store.enabledSlots,
    );
    store.activities.add(
      ActivityIdea(
        id: 'walk',
        name: 'Long walk',
        rangeKind: DateRangeKind.anytime,
        firstDate: dateOnly(DateTime.now()),
        startPart: null,
        slotLength: 1,
        people: const [],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ActivityPickerPage(
          store: store,
          weekStart: weekStart,
          slotIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Assign here'), findsNothing);
    await tester.tap(find.text('Long walk'));
    await tester.pump();

    expect(store.assignmentAt(weekStart, 0)?.activityId, 'walk');
  });

  testWidgets('activity picker filters ideas by tag', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await PlannerStore.load();
    final weekStart = firstRelevantWeekStart(
      DateTime.now(),
      store.enabledSlots,
    );
    store.activities.addAll([
      ActivityIdea(
        id: 'walk',
        name: 'Long walk',
        rangeKind: DateRangeKind.anytime,
        firstDate: dateOnly(DateTime.now()),
        startPart: null,
        slotLength: 1,
        people: const [],
        tags: const ['Outdoors'],
      ),
      ActivityIdea(
        id: 'concert',
        name: 'Live concert',
        rangeKind: DateRangeKind.anytime,
        firstDate: dateOnly(DateTime.now()),
        startPart: null,
        slotLength: 1,
        people: const [],
        tags: const ['Music'],
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: ActivityPickerPage(
          store: store,
          weekStart: weekStart,
          slotIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('#Music').first);
    await tester.pumpAndSettle();

    expect(find.text('Live concert'), findsOneWidget);
    expect(find.text('Long walk'), findsNothing);
  });

  testWidgets('RSS inbox is compact and grouped by week', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await PlannerStore.load();
    store.feeds.add(
      const RssFeed(
        id: 'feed',
        name: 'ARCI Bellezza',
        url: 'https://arcibellezza.it/feed/',
      ),
    );
    final currentWeek = addDays(
      dateOnly(DateTime.now()),
      1 - DateTime.now().weekday,
    );
    final nextWeek = addDays(currentWeek, 7);
    final followingWeek = addDays(currentWeek, 14);
    RssInboxItem item(String id, String title, DateTime date) => RssInboxItem(
      id: id,
      feedId: 'feed',
      source: 'ARCI Bellezza',
      title: title,
      link: 'https://arcibellezza.it/',
      eventDate: date,
      startPart: DayPart.night,
      slotLength: 1,
      locationName: 'Via Bellezza 16',
    );
    store.inbox.addAll([
      item('past', 'Past event', addDays(currentWeek, -1)),
      item('one', 'Insieme è più bello', nextWeek),
      item('two', 'Oltre i confini – sociә', addDays(nextWeek, 2)),
      item('three', 'A later event', followingWeek),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: InboxPage(store: store)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Next week'), findsOneWidget);
    expect(
      find.text(
        '${isoDate(followingWeek)} — '
        '${isoDate(addDays(followingWeek, 6))}',
      ),
      findsOneWidget,
    );
    expect(find.text('Import as activity'), findsNothing);
    expect(find.text('Import'), findsNWidgets(3));
    expect(find.text('Insieme è più bello'), findsOneWidget);
    expect(find.text('Past event'), findsNothing);
    final title = tester.widget<Text>(find.text('Insieme è più bello'));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    final preview = tester.widget<Text>(
      find.text(
        'Via Bellezza 16 · ${isoDate(nextWeek)} · night · ARCI Bellezza',
      ),
    );
    expect(preview.maxLines, 1);
    expect(preview.overflow, TextOverflow.ellipsis);
    await tester.tap(find.text('Insieme è più bello'));
    await tester.pumpAndSettle();

    expect(find.text('Feed entry'), findsOneWidget);
    expect(find.text('Date used for planning'), findsOneWidget);
    expect(find.text('Source page'), findsOneWidget);
    expect(find.text('Import as activity'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('feed sources are independently selectable with an only action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = await PlannerStore.load();
    final eventDate = addDays(dateOnly(DateTime.now()), 7);
    store.feeds.addAll([
      const RssFeed(
        id: 'arci',
        name: 'ARCI',
        url: 'https://example.com/arci.xml',
      ),
      const RssFeed(
        id: 'magnolia',
        name: 'Magnolia',
        url: 'https://example.com/magnolia.xml',
      ),
    ]);
    store.inbox.addAll([
      RssInboxItem(
        id: 'arci-event',
        feedId: 'arci',
        source: 'ARCI',
        title: 'ARCI event',
        link: 'https://example.com/arci-event',
        eventDate: eventDate,
        startPart: DayPart.night,
        slotLength: 1,
      ),
      RssInboxItem(
        id: 'magnolia-event',
        feedId: 'magnolia',
        source: 'Magnolia',
        title: 'Magnolia event',
        link: 'https://example.com/magnolia-event',
        eventDate: eventDate,
        startPart: DayPart.night,
        slotLength: 1,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: InboxPage(store: store)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All sources'), findsNothing);
    expect(find.text('Only'), findsNWidgets(2));
    expect(find.text('ARCI event'), findsOneWidget);
    expect(find.text('Magnolia event'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('source-toggle-arci')));
    await tester.pumpAndSettle();
    expect(find.text('ARCI event'), findsNothing);
    expect(find.text('Magnolia event'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('source-only-arci')));
    await tester.pumpAndSettle();
    expect(find.text('ARCI event'), findsOneWidget);
    expect(find.text('Magnolia event'), findsNothing);
  });

  test(
    'date, day, and slot rules make incompatible ideas unavailable',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await PlannerStore.load();
      final weekStart = DateTime(2026, 7, 20);
      final idea = ActivityIdea(
        id: 'test',
        name: 'Sunday lunch',
        rangeKind: DateRangeKind.exact,
        firstDate: DateTime(2026, 7, 26),
        startDay: WeekDay.sunday,
        startPart: DayPart.afternoon,
        slotLength: 1,
        people: const [],
      );

      expect(idea.isAvailableAt(slotDate(weekStart, 5)), isTrue);
      expect(idea.isAvailableAt(slotDate(weekStart, 2)), isFalse);
      expect(store.fitProblem(idea, weekStart, 5), isNull);
      expect(
        store.fitProblem(idea, weekStart, 2),
        'Starts on Sunday, not Saturday.',
      );
      expect(idea.slotLabel, 'Starts Sunday afternoon, lasts 1 slot');
    },
  );

  test('activity dates use strict editable ISO format', () {
    expect(parseIsoDate('2025-01-01'), DateTime(2025, 1, 1));
    expect(() => parseIsoDate('01/01/2025'), throwsFormatException);
    expect(() => parseIsoDate('2025-02-31'), throwsFormatException);
  });

  test('anytime activities are available on every weekend', () {
    final idea = ActivityIdea(
      id: 'anytime',
      name: 'Walk',
      rangeKind: DateRangeKind.anytime,
      firstDate: DateTime(2026, 1, 1),
      startPart: null,
      slotLength: 1,
      people: const [],
    );

    expect(idea.isAvailableAt(DateTime(2030, 12, 1)), isTrue);
    expect(idea.rangeLabel, 'Anytime');
  });

  test(
    'a fresh database contains no sample entries and is versioned',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await PlannerStore.load();

      expect(store.activities, isEmpty);
      expect(store.assignments, isEmpty);
      expect(store.cachedPeople, isEmpty);
      expect(
        jsonDecode(store.databaseJson())['schemaVersion'],
        PlannerStore.currentSchemaVersion,
      );
    },
  );

  test('schema one migrates through schema five without changing v1', () async {
    final activity = ActivityIdea(
      id: 'kept',
      name: 'Kept activity',
      rangeKind: DateRangeKind.within,
      firstDate: DateTime(2027, 1, 1),
      startPart: DayPart.night,
      slotLength: 1,
      people: const [],
    );
    final v1Activity = activity.toJson()
      ..remove('startDay')
      ..remove('frequencyCounterResetAt')
      ..remove('tags')
      ..['needsBooking'] = false;
    final v1Database = jsonEncode({
      'schemaVersion': 1,
      'activities': [v1Activity],
      'assignments': <String, dynamic>{},
      'cachedPeople': <String>[],
      'feeds': <dynamic>[],
      'inbox': <dynamic>[],
    });
    SharedPreferences.setMockInitialValues({
      'weekend_planner_state_v1': v1Database,
    });

    final store = await PlannerStore.load();
    final preferences = await SharedPreferences.getInstance();
    final v5Database =
        jsonDecode(preferences.getString('weekend_planner_state_v5')!)
            as Map<String, dynamic>;

    expect(store.activities.single.id, 'kept');
    expect(store.activities.single.startDay, isNull);
    expect(store.activities.single.frequencyCounterResetAt, isNull);
    expect(store.activities.single.tags, isEmpty);
    expect(jsonDecode(store.databaseJson())['schemaVersion'], 5);
    expect(v5Database['schemaVersion'], 5);
    expect(
      (v5Database['activities'] as List<dynamic>).single['startDay'],
      isNull,
    );
    expect(preferences.getString('weekend_planner_state_v1'), v1Database);
  });

  test('schema two migrates stable slot keys without changing v2', () async {
    final v2Database = jsonEncode({
      'schemaVersion': 2,
      'activities': <dynamic>[],
      'assignments': {
        '2026-07-24#1': {'activityId': 'trek', 'part': 1, 'total': 2},
        '2026-07-24#2': {'activityId': 'trek', 'part': 2, 'total': 2},
      },
      'cachedPeople': <String>[],
      'feeds': [
        {'id': 'venue', 'name': 'Venue', 'url': 'https://example.com/feed'},
      ],
      'inbox': <dynamic>[],
      'settings': {'calendarEnabled': false},
      'eventLog': <dynamic>[],
    });
    SharedPreferences.setMockInitialValues({
      'weekend_planner_state_v2': v2Database,
    });

    final store = await PlannerStore.load();
    final preferences = await SharedPreferences.getInstance();
    final migrated = jsonDecode(store.databaseJson()) as Map<String, dynamic>;
    final assignments = migrated['assignments'] as Map<String, dynamic>;

    expect(migrated['schemaVersion'], 5);
    expect(assignments.keys, contains('2026-07-25#morning'));
    expect(assignments.keys, contains('2026-07-25#afternoon'));
    expect(
      (assignments['2026-07-25#afternoon'] as Map<String, dynamic>)['startKey'],
      '2026-07-25#morning',
    );
    expect(store.feeds.single.kind, FeedKind.rss);
    expect(store.enabledSlots.map((slot) => slot.id), [
      for (final slot in PlannerSlot.defaults) slot.id,
    ]);
    expect(preferences.getString('weekend_planner_state_v2'), v2Database);
    expect(preferences.getString('weekend_planner_state_v5'), isNotNull);
  });

  test('schema three adds empty tags without changing v3', () async {
    final activity =
        ActivityIdea(
            id: 'cinema',
            name: 'Cinema',
            rangeKind: DateRangeKind.anytime,
            firstDate: DateTime(2026, 7, 26),
            startPart: DayPart.night,
            slotLength: 1,
            people: const [],
          ).toJson()
          ..remove('tags')
          ..['needsBooking'] = false;
    final v3Database = jsonEncode({
      'schemaVersion': 3,
      'activities': [activity],
      'assignments': <String, dynamic>{},
      'cachedPeople': <String>[],
      'feeds': <dynamic>[],
      'inbox': <dynamic>[],
      'settings': <String, dynamic>{},
      'eventLog': <dynamic>[],
    });
    SharedPreferences.setMockInitialValues({
      'weekend_planner_state_v3': v3Database,
    });

    final store = await PlannerStore.load();
    final preferences = await SharedPreferences.getInstance();

    expect(store.activities.single.tags, isEmpty);
    expect(jsonDecode(store.databaseJson())['schemaVersion'], 5);
    expect(preferences.getString('weekend_planner_state_v3'), v3Database);
    expect(preferences.getString('weekend_planner_state_v5'), isNotNull);
  });

  test('schema four removes booking without turning it into a tag', () async {
    final activity = ActivityIdea(
      id: 'cinema',
      name: 'Cinema',
      rangeKind: DateRangeKind.anytime,
      firstDate: DateTime(2026, 7, 26),
      startPart: DayPart.night,
      slotLength: 1,
      people: const [],
      tags: const ['Film'],
    ).toJson()..['needsBooking'] = true;
    final v4Database = jsonEncode({
      'schemaVersion': 4,
      'activities': [activity],
      'assignments': <String, dynamic>{},
      'cachedPeople': <String>[],
      'feeds': <dynamic>[],
      'inbox': <dynamic>[],
      'settings': <String, dynamic>{},
      'eventLog': <dynamic>[],
    });
    SharedPreferences.setMockInitialValues({
      'weekend_planner_state_v4': v4Database,
    });

    final store = await PlannerStore.load();
    final preferences = await SharedPreferences.getInstance();
    final migrated = jsonDecode(store.databaseJson()) as Map<String, dynamic>;
    final migratedActivity =
        (migrated['activities'] as List<dynamic>).single
            as Map<String, dynamic>;

    expect(store.activities.single.tags, ['Film']);
    expect(migratedActivity, isNot(contains('needsBooking')));
    expect(store.activities.single.tags, isNot(contains('booking')));
    expect(preferences.getString('weekend_planner_state_v4'), v4Database);
    expect(preferences.getString('weekend_planner_state_v5'), isNotNull);
  });

  testWidgets('activities can be filtered by tag without checkmarks', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = await PlannerStore.load();
    store.activities.addAll([
      ActivityIdea(
        id: 'walk',
        name: 'Long walk',
        rangeKind: DateRangeKind.anytime,
        firstDate: DateTime(2026, 7, 26),
        startPart: null,
        slotLength: 1,
        people: const [],
        tags: const ['Outdoors'],
      ),
      ActivityIdea(
        id: 'concert',
        name: 'Concert',
        rangeKind: DateRangeKind.anytime,
        firstDate: DateTime(2026, 7, 26),
        startPart: DayPart.night,
        slotLength: 1,
        people: const [],
        tags: const ['Music'],
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivitiesPage(store: store, onCreate: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('#Music').first);
    await tester.pumpAndSettle();

    expect(find.text('Concert'), findsOneWidget);
    expect(find.text('Long walk'), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });

  test('configured weekday slots keep assignments on stable keys', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await PlannerStore.load();
    const mondayNight = PlannerSlot(WeekDay.monday, DayPart.night);
    final weekStart = DateTime(2026, 7, 27);
    final activity = ActivityIdea(
      id: 'film',
      name: 'Monday film',
      rangeKind: DateRangeKind.anytime,
      firstDate: weekStart,
      startDay: WeekDay.monday,
      startPart: DayPart.night,
      slotLength: 1,
      people: const [],
    );
    store.activities.add(activity);

    store.setSlotEnabled(mondayNight, true);
    expect(store.enabledSlots.first.id, mondayNight.id);
    expect(store.fitProblem(activity, weekStart, 0), isNull);
    store.assign(activity, weekStart, 0);
    store.setSlotEnabled(mondayNight, false);
    store.setSlotEnabled(mondayNight, true);

    expect(store.assignmentAt(weekStart, 0)?.activityId, activity.id);
    expect(
      (jsonDecode(store.databaseJson())['assignments'] as Map<String, dynamic>)
          .keys,
      contains('2026-07-27#night'),
    );
  });

  testWidgets('a recurring frequency counter can be reset', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await PlannerStore.load();
    const activityId = 'weekly-walk';
    store.activities.add(
      ActivityIdea(
        id: activityId,
        name: 'Weekly walk',
        rangeKind: DateRangeKind.anytime,
        firstDate: DateTime(2026, 1, 1),
        startPart: null,
        slotLength: 1,
        people: const [],
        isRecurring: true,
        desiredFrequencyWeeks: 4,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ActivityDetailPage(store: store, activityId: activityId),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Not done yet'), findsOneWidget);
    await tester.tap(find.text('Reset counter'));
    await tester.pump();

    expect(find.textContaining('Not done yet'), findsNothing);
    expect(store.activityById(activityId)!.frequencyCounterResetAt, isNotNull);
    expect(
      store.frequencyWarning(
        store.activityById(activityId)!,
        now: addDays(DateTime.now(), 28),
      ),
      contains('4 weekends since counter reset'),
    );
  });

  test('all-caps RSS titles become sentence case', () {
    expect(
      normalizeAllCapsTitle('A VERY LOUD TITLE. ANOTHER SENTENCE! OK?'),
      'A very loud title. Another sentence! Ok?',
    );
    expect(normalizeAllCapsTitle('Already Mixed Case'), 'Already Mixed Case');
    expect(
      normalizeAllCapsTitle('Insieme è più bello – sociә'),
      'Insieme è più bello – sociә',
    );
  });

  test('iCalendar feeds are queried and imported as activities', () async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient(
      (request) async => http.Response(
        '''
BEGIN:VCALENDAR
VERSION:2.0
X-WR-CALNAME:Neighborhood events
BEGIN:VEVENT
UID:concert-1
DTSTART:20260727T203000
SUMMARY:A VERY LOUD CONCERT
LOCATION:Community Hall
URL:https://example.com/concert
END:VEVENT
END:VCALENDAR
''',
        200,
        headers: {'content-type': 'text/calendar; charset=utf-8'},
      ),
    );
    final store = await PlannerStore.load(httpClient: client);
    await store.addFeed('https://example.com/events.ics');

    final result = await store.refreshFeedsIfDue(maxAge: Duration.zero);

    expect(result.checked, 1);
    expect(result.added, 1);
    expect(store.feeds.single.kind, FeedKind.ics);
    expect(store.feeds.single.name, 'Neighborhood events');
    expect(store.inbox.single.title, 'A very loud concert');
    expect(store.inbox.single.eventDate, DateTime(2026, 7, 27, 20, 30));
    final activity = store.importInboxItem(store.inbox.single);
    expect(activity.startDay, WeekDay.monday);
    expect(activity.startPart, DayPart.night);
    expect(activity.location?.name, 'Community Hall');
    expect(activity.url, 'https://example.com/concert');
  });

  test('RSS infers credible event dates and excludes unknown dates', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.path == '/events.xml') {
        return http.Response(
          '''
<rss version="2.0">
  <channel>
    <item>
      <guid>written</guid>
      <title>Festival 5 settembre 2026 ore 23:00</title>
      <link>https://example.com/written</link>
      <pubDate>Thu, 23 Jul 2026 13:05:42 +0000</pubDate>
    </item>
    <item>
      <guid>structured</guid>
      <title>A concert with a structured page</title>
      <link>https://example.com/structured</link>
      <pubDate>Thu, 23 Jul 2026 13:05:42 +0000</pubDate>
    </item>
    <item>
      <guid>unknown</guid>
      <title>A post without an event date</title>
      <link>https://example.com/unknown</link>
      <pubDate>Thu, 23 Jul 2026 13:05:42 +0000</pubDate>
    </item>
  </channel>
</rss>
''',
          200,
          headers: {'content-type': 'application/rss+xml; charset=utf-8'},
        );
      }
      if (request.url.path == '/structured') {
        return http.Response(
          '''
<!doctype html>
<script type="application/ld+json">
{"@context":"https://schema.org","@type":"Event",
 "name":"A concert","startDate":"2026-09-13 17:30:00",
 "location":{"@type":"Place","name":"Community Hall",
             "address":{"streetAddress":"1 Main Street",
                        "addressLocality":"Milan"}}}
</script>
''',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }
      return http.Response(
        '''
<!doctype html>
<script type="application/ld+json">
{"@context":"https://schema.org","@type":"Article",
 "datePublished":"2026-07-23T13:05:42Z"}
</script>
''',
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });
    final store = await PlannerStore.load(httpClient: client);
    await store.addFeed('https://example.com/events.xml');

    final result = await store.refreshFeedsIfDue(maxAge: Duration.zero);

    expect(result.checked, 1);
    expect(result.added, 2);
    expect(result.skipped, 1);
    expect(store.inbox, hasLength(2));
    expect(
      store.inbox.map((item) => item.eventDate),
      containsAll([DateTime(2026, 9, 5, 23), DateTime(2026, 9, 13, 17, 30)]),
    );
    expect(
      requests.map((uri) => uri.path),
      containsAll(['/events.xml', '/structured', '/unknown']),
    );
    expect(
      store.inbox
          .singleWhere(
            (item) => item.title == 'A concert with a structured page',
          )
          .locationName,
      'Community Hall, 1 Main Street, Milan',
    );
    expect(
      store.eventLog.any(
        (entry) =>
            entry.message ==
            'Skipped an RSS entry with no credible event date.',
      ),
      isTrue,
    );
  });

  test('HTML discovery prefers an event calendar over generic RSS', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.path == '/') {
        return http.Response(
          '''
<!doctype html>
<link rel="alternate" type="application/rss+xml"
      title="News" href="/feed/">
<link rel="alternate" type="text/calendar"
      title="Events" href="/events.ics">
''',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }
      return http.Response(
        '''
BEGIN:VCALENDAR
VERSION:2.0
X-WR-CALNAME:Events from source
BEGIN:VEVENT
UID:event-1
DTSTART:20260905T230000
SUMMARY:Calendar event
END:VEVENT
END:VCALENDAR
''',
        200,
        headers: {'content-type': 'text/calendar; charset=utf-8'},
      );
    });
    final store = await PlannerStore.load(httpClient: client);
    final feed = await store.addFeed('https://example.com/');
    store.inbox.add(
      RssInboxItem(
        id: 'past',
        feedId: feed.id,
        source: feed.name,
        title: 'Past event',
        link: 'https://example.com/past',
        eventDate: addDays(dateOnly(DateTime.now()), -1),
        startPart: DayPart.night,
        slotLength: 1,
      ),
    );

    final result = await store.refreshFeedsIfDue(maxAge: Duration.zero);

    expect(result.added, 1);
    expect(store.inbox, hasLength(1));
    expect(store.inbox.single.title, 'Calendar event');
    expect(store.feeds.single.kind, FeedKind.ics);
    expect(store.feeds.single.name, 'Events');
    expect(store.feeds.single.url, 'https://example.com/events.ics');
    expect(requests.map((uri) => uri.path), ['/', '/events.ics']);

    store.renameFeed(store.feeds.single.id, 'My calendar');
    await store.refreshFeedsIfDue(maxAge: Duration.zero);

    expect(store.feeds.single.name, 'My calendar');
    expect(store.inbox.single.source, 'My calendar');
    expect(requests.map((uri) => uri.path), [
      '/',
      '/events.ics',
      '/events.ics',
    ]);
  });

  test(
    'HTML discovery follows a calendar index to the Magnolia event feed',
    () async {
      SharedPreferences.setMockInitialValues({});
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        switch (request.url.path) {
          case '/':
            return http.Response(
              '''
<!doctype html>
<link rel="alternate" type="application/rss+xml"
      title="News" href="/feed/">
<a href="/event_listing_category/eventi/">Calendario</a>
''',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          case '/event_listing_category/eventi/':
            return http.Response(
              '''
<!doctype html>
<link rel="alternate" type="application/rss+xml"
      title="News" href="/feed/">
<link rel="alternate" type="application/rss+xml"
      title="Eventi" href="/event_listing_category/eventi/feed/">
''',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          case '/event_listing_category/eventi/feed/':
            return http.Response(
              '''
<rss version="2.0">
  <channel>
    <title>Circolo Magnolia Eventi</title>
    <item>
      <guid>bunny-club</guid>
      <title>BUNNY CLUB</title>
      <link>https://www.circolomagnolia.it/evento/bunny-club/</link>
      <pubDate>Thu, 23 Jul 2026 13:05:42 +0000</pubDate>
    </item>
  </channel>
</rss>
''',
              200,
              headers: {'content-type': 'application/rss+xml; charset=utf-8'},
            );
          case '/evento/bunny-club/':
            return http.Response(
              '''
<!doctype html>
<script type="application/ld+json">
{"@context":"https://schema.org","@type":"Event",
 "name":"Bunny Club","startDate":"2026-09-05 23:00:00",
 "location":{"@type":"Place","name":"Circolo Magnolia"}}
</script>
''',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          default:
            return http.Response('Not found', 404);
        }
      });
      final store = await PlannerStore.load(httpClient: client);
      await store.addFeed('https://www.circolomagnolia.it/');

      final result = await store.refreshFeedsIfDue(maxAge: Duration.zero);

      expect(result.added, 1);
      expect(store.feeds.single.url, contains('/eventi/feed/'));
      expect(store.inbox.single.title, 'Bunny club');
      expect(store.inbox.single.eventDate, DateTime(2026, 9, 5, 23));
      expect(store.inbox.single.locationName, 'Circolo Magnolia');
      expect(requests.map((uri) => uri.path), [
        '/',
        '/event_listing_category/eventi/',
        '/event_listing_category/eventi/feed/',
        '/evento/bunny-club/',
      ]);
    },
  );

  test('summary RSS prefers its exact companion screening calendar', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      switch (request.url.path) {
        case '/bah/beltrade/upcoming_events':
          return http.Response(
            '''
<rss version="2.0">
  <channel>
    <title>Cinema Beltrade Prossimi eventi</title>
    <link>https://bandhi.it/bah/beltrade</link>
    <item>
      <title>OBSESSION</title>
      <description>Fino a 28 Luglio 2026.</description>
    </item>
  </channel>
</rss>
''',
            200,
            headers: {'content-type': 'text/xml; charset=utf-8'},
          );
        case '/bah/beltrade':
          return http.Response(
            '''
<!doctype html>
<a href="webcal://bandhi.it/bah/beltrade/wp-content/uploads/sites/2/beltrade.ics">
  iCal
</a>
''',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        case '/bah/beltrade/wp-content/uploads/sites/2/beltrade.ics':
          return http.Response(
            '''
BEGIN:VCALENDAR
VERSION:2.0
X-WR-CALNAME:Cinema Beltrade
X-WR-TIMEZONE:Europe/Rome
BEGIN:VEVENT
UID:screening-33837
DTSTART;TZID=Europe/Rome:20260726T104000
SUMMARY:OBSESSION
LOCATION:Cinema Beltrade\\nVia Nino Oxilia 10, Milano
URL:https://bandhi.it/bah/beltrade/production/obsession/
END:VEVENT
END:VCALENDAR
''',
            200,
            headers: {'content-type': 'text/calendar'},
          );
        default:
          return http.Response('Not found', 404);
      }
    });
    final store = await PlannerStore.load(httpClient: client);
    await store.addFeed('https://bandhi.it/bah/beltrade/upcoming_events');

    final result = await store.refreshFeedsIfDue(maxAge: Duration.zero);

    expect(result.added, 1);
    expect(store.feeds.single.kind, FeedKind.ics);
    expect(store.feeds.single.name, 'Cinema Beltrade');
    expect(store.feeds.single.url, endsWith('/beltrade.ics'));
    expect(store.inbox.single.title, 'Obsession');
    expect(store.inbox.single.eventDate, DateTime(2026, 7, 26, 10, 40));
    expect(
      store.inbox.single.locationName,
      'Cinema Beltrade\nVia Nino Oxilia 10, Milano',
    );
    expect(requests.map((uri) => uri.path), [
      '/bah/beltrade/upcoming_events',
      '/bah/beltrade',
      '/bah/beltrade/wp-content/uploads/sites/2/beltrade.ics',
    ]);
  });

  test(
    'run-window RSS is rejected when no exact calendar is available',
    () async {
      SharedPreferences.setMockInitialValues({});
      final client = MockClient((request) async {
        if (request.url.path == '/upcoming_events') {
          return http.Response(
            '''
<rss version="2.0">
  <channel>
    <title>Cinema Prossimi eventi</title>
    <link>https://example.com/cinema</link>
    <item>
      <title>A film</title>
      <description>Fino a 28 Luglio 2026.</description>
    </item>
  </channel>
</rss>
''',
            200,
            headers: {'content-type': 'text/xml; charset=utf-8'},
          );
        }
        return http.Response(
          '<!doctype html><title>Cinema</title>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });
      final store = await PlannerStore.load(httpClient: client);
      await store.addFeed('https://example.com/upcoming_events');

      final result = await store.refreshFeedsIfDue(maxAge: Duration.zero);

      expect(result.errors, hasLength(1));
      expect(result.errors.single, contains('run windows'));
      expect(store.inbox, isEmpty);
    },
  );

  test(
    'RSS refresh removes a previously stored entry if its date is unknown',
    () async {
      SharedPreferences.setMockInitialValues({});
      var includesDate = true;
      final client = MockClient((request) async {
        if (request.url.path == '/events.xml') {
          return http.Response(
            '''
<rss version="2.0">
  <channel>
    <item>
      <guid>changing-event</guid>
      <title>${includesDate ? 'Concert 5 settembre 2026' : 'Concert'}</title>
      <link>https://example.com/concert</link>
      <pubDate>Thu, 23 Jul 2026 13:05:42 +0000</pubDate>
    </item>
  </channel>
</rss>
''',
            200,
            headers: {'content-type': 'application/rss+xml; charset=utf-8'},
          );
        }
        return http.Response(
          '''
<!doctype html>
<script type="application/ld+json">
{"@context":"https://schema.org","@type":"Article",
 "datePublished":"2026-07-23T13:05:42Z"}
</script>
''',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });
      final store = await PlannerStore.load(httpClient: client);
      await store.addFeed('https://example.com/events.xml');
      await store.refreshFeedsIfDue(maxAge: Duration.zero);
      expect(store.inbox, hasLength(1));

      includesDate = false;
      await store.refreshFeedsIfDue(maxAge: Duration.zero);

      expect(store.inbox, isEmpty);
    },
  );

  testWidgets('people can be added directly from the People tab', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = await PlannerStore.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PeoplePage(store: store)),
      ),
    );
    await tester.tap(find.text('Add person'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Giulia');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(store.cachedPeople, ['Giulia']);
    expect(find.text('Giulia'), findsOneWidget);
  });

  test('locations accept coordinates, geo URLs, and full plus codes', () {
    final pair = parseActivityLocation('Milan', '45.4642, 9.1900')!;
    final geo = parseActivityLocation('', 'geo:45.4642,9.1900?z=16')!;
    final plusCode = parseActivityLocation('', '849VCWC8+R9')!;

    expect(pair.latitude, closeTo(45.4642, 0.000001));
    expect(geo.longitude, closeTo(9.19, 0.000001));
    expect(plusCode.latitude, closeTo(37.422, 0.001));
    expect(plusCode.longitude, closeTo(-122.084, 0.001));
  });
}
