import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weekend_planner/location_parser.dart';
import 'package:weekend_planner/main.dart';
import 'package:weekend_planner/models.dart';
import 'package:weekend_planner/planner_store.dart';
import 'package:weekend_planner/screens/activity_form_page.dart';
import 'package:weekend_planner/screens/activity_picker_page.dart';
import 'package:weekend_planner/screens/inbox_page.dart';

void main() {
  testWidgets('shows the upcoming weekend slots', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await PlannerStore.load();

    await tester.pumpWidget(WeekendPlannerApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('Weekends'), findsWidgets);
    expect(find.text('This weekend'), findsOneWidget);
    expect(find.text('Friday'), findsWidgets);
    expect(find.text('Saturday'), findsWidgets);
    expect(find.text('Sunday'), findsWidgets);
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

    expect(find.text('Any time'), findsOneWidget);
    expect(find.text('1w'), findsOneWidget);
    expect(find.text('1m'), findsOneWidget);
    expect(
      find.text(isoDate(addDays(dateOnly(DateTime.now()), 90))),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity picker assigns by tapping the whole entry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = await PlannerStore.load();
    final friday = firstRelevantFriday(DateTime.now());
    store.activities.add(
      ActivityIdea(
        id: 'walk',
        name: 'Long walk',
        rangeKind: DateRangeKind.anytime,
        firstDate: dateOnly(DateTime.now()),
        startPart: null,
        slotLength: 1,
        needsBooking: false,
        people: const [],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ActivityPickerPage(store: store, friday: friday, slotIndex: 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Assign here'), findsNothing);
    await tester.tap(find.text('Long walk'));
    await tester.pump();

    expect(store.assignmentAt(friday, 0)?.activityId, 'walk');
  });

  testWidgets('RSS inbox is compact and grouped by week', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await PlannerStore.load();
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
    );
    store.inbox.addAll([
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
    expect(tester.takeException(), isNull);
  });

  test('date and slot rules make incompatible ideas unavailable', () {
    final friday = DateTime(2026, 7, 24);
    final idea = ActivityIdea(
      id: 'test',
      name: 'Sunday lunch',
      rangeKind: DateRangeKind.exact,
      firstDate: DateTime(2026, 7, 26),
      startPart: DayPart.afternoon,
      slotLength: 1,
      needsBooking: false,
      people: const [],
    );

    expect(idea.isAvailableAt(slotDate(friday, 5)), isTrue);
    expect(idea.isAvailableAt(slotDate(friday, 2)), isFalse);
  });

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
      needsBooking: false,
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

  test('legacy schema-one data is loaded without losing activities', () async {
    final activity = ActivityIdea(
      id: 'kept',
      name: 'Kept activity',
      rangeKind: DateRangeKind.within,
      firstDate: DateTime(2027, 1, 1),
      startPart: DayPart.night,
      slotLength: 1,
      needsBooking: false,
      people: const [],
    );
    SharedPreferences.setMockInitialValues({
      'weekend_planner_state_v1': jsonEncode({
        'activities': [activity.toJson()],
        'assignments': <String, dynamic>{},
        'cachedPeople': <String>[],
        'feeds': <dynamic>[],
        'inbox': <dynamic>[],
      }),
    });

    final store = await PlannerStore.load();

    expect(store.activities.single.id, 'kept');
    expect(jsonDecode(store.databaseJson())['schemaVersion'], 1);
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
