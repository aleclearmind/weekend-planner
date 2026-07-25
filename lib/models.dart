enum DateRangeKind { anytime, within, between, exact }

enum DayPart { morning, afternoon, night }

enum WeekendDay { friday, saturday, sunday }

enum InterestStatus { possibly, interested, confirmed }

class WeekendSlot {
  const WeekendSlot(this.weekendDay, this.part);

  final WeekendDay weekendDay;
  final DayPart part;

  String get day => weekendDayLabel(weekendDay);
  int get dayOffset => weekendDay.index;
  String get partLabel => part.name;

  static const all = <WeekendSlot>[
    WeekendSlot(WeekendDay.friday, DayPart.night),
    WeekendSlot(WeekendDay.saturday, DayPart.morning),
    WeekendSlot(WeekendDay.saturday, DayPart.afternoon),
    WeekendSlot(WeekendDay.saturday, DayPart.night),
    WeekendSlot(WeekendDay.sunday, DayPart.morning),
    WeekendSlot(WeekendDay.sunday, DayPart.afternoon),
    WeekendSlot(WeekendDay.sunday, DayPart.night),
  ];
}

String weekendDayLabel(WeekendDay day) =>
    '${day.name[0].toUpperCase()}${day.name.substring(1)}';

String activityStartLabel(WeekendDay? day, DayPart? part) =>
    switch ((day, part)) {
      (null, null) => 'any time',
      (final day?, null) => weekendDayLabel(day),
      (null, final part?) => 'a ${part.name}',
      (final day?, final part?) => '${weekendDayLabel(day)} ${part.name}',
    };

class Participant {
  const Participant({required this.name, required this.status});

  final String name;
  final InterestStatus status;

  Participant copyWith({String? name, InterestStatus? status}) =>
      Participant(name: name ?? this.name, status: status ?? this.status);

  Map<String, dynamic> toJson() => {'name': name, 'status': status.name};

  factory Participant.fromJson(Map<String, dynamic> json) => Participant(
    name: json['name'] as String? ?? '',
    status: _enumByName(
      InterestStatus.values,
      json['status'],
      InterestStatus.possibly,
    ),
  );
}

class ActivityLocation {
  const ActivityLocation({
    required this.name,
    this.latitude,
    this.longitude,
    this.coordinateInput,
  });

  final String name;
  final double? latitude;
  final double? longitude;
  final String? coordinateInput;

  bool get hasCoordinates => latitude != null && longitude != null;

  String get coordinateLabel => hasCoordinates
      ? '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}'
      : '';

  Map<String, dynamic> toJson() => {
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'coordinateInput': coordinateInput,
  };

  factory ActivityLocation.fromJson(Map<String, dynamic> json) =>
      ActivityLocation(
        name: json['name'] as String? ?? '',
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        coordinateInput: json['coordinateInput'] as String?,
      );
}

class ActivityIdea {
  const ActivityIdea({
    required this.id,
    required this.name,
    required this.rangeKind,
    required this.firstDate,
    this.secondDate,
    this.startDay,
    required this.startPart,
    required this.slotLength,
    required this.needsBooking,
    required this.people,
    this.isRecurring = false,
    this.desiredFrequencyWeeks,
    this.location,
    this.url,
    this.createdAt,
    this.frequencyCounterResetAt,
  });

  final String id;
  final String name;
  final DateRangeKind rangeKind;
  final DateTime firstDate;
  final DateTime? secondDate;

  /// Null means the activity may start on any day of the weekend.
  final WeekendDay? startDay;

  /// Null means the activity may start at any available time of day.
  final DayPart? startPart;
  final int slotLength;
  final bool needsBooking;
  final List<Participant> people;
  final bool isRecurring;
  final int? desiredFrequencyWeeks;
  final ActivityLocation? location;
  final String? url;
  final DateTime? createdAt;
  final DateTime? frequencyCounterResetAt;

  ActivityIdea copyWith({
    String? id,
    String? name,
    DateRangeKind? rangeKind,
    DateTime? firstDate,
    DateTime? secondDate,
    bool clearSecondDate = false,
    WeekendDay? startDay,
    bool useAnyStartDay = false,
    DayPart? startPart,
    bool useAnyStart = false,
    int? slotLength,
    bool? needsBooking,
    List<Participant>? people,
    bool? isRecurring,
    int? desiredFrequencyWeeks,
    bool clearDesiredFrequency = false,
    ActivityLocation? location,
    bool clearLocation = false,
    String? url,
    bool clearUrl = false,
    DateTime? createdAt,
    DateTime? frequencyCounterResetAt,
    bool clearFrequencyCounterReset = false,
  }) => ActivityIdea(
    id: id ?? this.id,
    name: name ?? this.name,
    rangeKind: rangeKind ?? this.rangeKind,
    firstDate: firstDate ?? this.firstDate,
    secondDate: clearSecondDate ? null : secondDate ?? this.secondDate,
    startDay: useAnyStartDay ? null : startDay ?? this.startDay,
    startPart: useAnyStart ? null : startPart ?? this.startPart,
    slotLength: slotLength ?? this.slotLength,
    needsBooking: needsBooking ?? this.needsBooking,
    people: people ?? this.people,
    isRecurring: isRecurring ?? this.isRecurring,
    desiredFrequencyWeeks: clearDesiredFrequency
        ? null
        : desiredFrequencyWeeks ?? this.desiredFrequencyWeeks,
    location: clearLocation ? null : location ?? this.location,
    url: clearUrl ? null : url ?? this.url,
    createdAt: createdAt ?? this.createdAt,
    frequencyCounterResetAt: clearFrequencyCounterReset
        ? null
        : frequencyCounterResetAt ?? this.frequencyCounterResetAt,
  );

  bool isAvailableAt(DateTime startDate) {
    final date = dateOnly(startDate);
    final first = dateOnly(firstDate);
    return switch (rangeKind) {
      DateRangeKind.anytime => true,
      DateRangeKind.within => !date.isAfter(first),
      DateRangeKind.exact => date == first,
      DateRangeKind.between =>
        !date.isBefore(first) &&
            !date.isAfter(dateOnly(secondDate ?? firstDate)),
    };
  }

  String get rangeLabel => switch (rangeKind) {
    DateRangeKind.anytime => 'Anytime',
    DateRangeKind.within => 'Within ${isoDate(firstDate)}',
    DateRangeKind.exact => 'Exact ${isoDate(firstDate)}',
    DateRangeKind.between =>
      'Between ${isoDate(firstDate)} and '
          '${isoDate(secondDate ?? firstDate)}',
  };

  String get slotLabel {
    final start = activityStartLabel(startDay, startPart);
    return 'Starts $start, lasts $slotLength '
        '${slotLength == 1 ? 'slot' : 'slots'}';
  }

  String? get frequencyLabel => desiredFrequencyWeeks == null
      ? null
      : 'Every ${desiredFrequencyWeeks!} '
            '${desiredFrequencyWeeks == 1 ? 'weekend' : 'weekends'}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'rangeKind': rangeKind.name,
    'firstDate': isoDate(firstDate),
    'secondDate': secondDate == null ? null : isoDate(secondDate!),
    'startDay': startDay?.name,
    'startPart': startPart?.name,
    'slotLength': slotLength,
    'needsBooking': needsBooking,
    'people': people.map((person) => person.toJson()).toList(),
    'isRecurring': isRecurring,
    'desiredFrequencyWeeks': desiredFrequencyWeeks,
    'location': location?.toJson(),
    'url': url,
    'createdAt': createdAt?.toIso8601String(),
    'frequencyCounterResetAt': frequencyCounterResetAt == null
        ? null
        : isoDate(frequencyCounterResetAt!),
  };

  factory ActivityIdea.fromJson(Map<String, dynamic> json) {
    final rawStartDay = json['startDay'];
    final rawStart = json['startPart'];
    return ActivityIdea(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      rangeKind: _enumByName(
        DateRangeKind.values,
        json['rangeKind'],
        DateRangeKind.within,
      ),
      firstDate:
          _tryParseIsoDate(json['firstDate']) ?? dateOnly(DateTime.now()),
      secondDate: _tryParseIsoDate(json['secondDate']),
      startDay: rawStartDay == null
          ? null
          : _enumByName(WeekendDay.values, rawStartDay, WeekendDay.friday),
      startPart: rawStart == null
          ? null
          : _enumByName(DayPart.values, rawStart, DayPart.night),
      slotLength: (json['slotLength'] as num?)?.toInt() ?? 1,
      needsBooking: json['needsBooking'] as bool? ?? false,
      people: (json['people'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Participant.fromJson)
          .toList(),
      isRecurring: json['isRecurring'] as bool? ?? false,
      desiredFrequencyWeeks: (json['desiredFrequencyWeeks'] as num?)?.toInt(),
      location: json['location'] is Map<String, dynamic>
          ? ActivityLocation.fromJson(json['location'] as Map<String, dynamic>)
          : null,
      url: _nonEmpty(json['url'] as String?),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      frequencyCounterResetAt: _tryParseIsoDate(
        json['frequencyCounterResetAt'],
      ),
    );
  }
}

class SlotAssignment {
  const SlotAssignment({
    required this.activityId,
    required this.part,
    required this.total,
  });

  final String activityId;
  final int part;
  final int total;

  Map<String, dynamic> toJson() => {
    'activityId': activityId,
    'part': part,
    'total': total,
  };

  factory SlotAssignment.fromJson(Map<String, dynamic> json) => SlotAssignment(
    activityId: json['activityId'] as String,
    part: (json['part'] as num?)?.toInt() ?? 1,
    total: (json['total'] as num?)?.toInt() ?? 1,
  );
}

class ActivityPlacement {
  const ActivityPlacement({
    required this.friday,
    required this.slotIndex,
    required this.slotLength,
  });

  final DateTime friday;
  final int slotIndex;
  final int slotLength;

  DateTime get date => slotDate(friday, slotIndex);
  WeekendSlot get slot => WeekendSlot.all[slotIndex];

  String get label =>
      '${slot.day} ${slot.partLabel} · ${friendlyDate(date, includeYear: true)}';
}

class RssFeed {
  const RssFeed({
    required this.id,
    required this.name,
    required this.url,
    this.lastChecked,
  });

  final String id;
  final String name;
  final String url;
  final DateTime? lastChecked;

  RssFeed copyWith({String? name, String? url, DateTime? lastChecked}) =>
      RssFeed(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        lastChecked: lastChecked ?? this.lastChecked,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'lastChecked': lastChecked?.toIso8601String(),
  };

  factory RssFeed.fromJson(Map<String, dynamic> json) => RssFeed(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'RSS feed',
    url: json['url'] as String? ?? '',
    lastChecked: DateTime.tryParse(json['lastChecked'] as String? ?? ''),
  );
}

class RssInboxItem {
  const RssInboxItem({
    required this.id,
    required this.feedId,
    required this.source,
    required this.title,
    required this.link,
    required this.eventDate,
    required this.startPart,
    required this.slotLength,
    this.imported = false,
  });

  final String id;
  final String feedId;
  final String source;
  final String title;
  final String link;
  final DateTime eventDate;
  final DayPart startPart;
  final int slotLength;
  final bool imported;

  RssInboxItem copyWith({bool? imported}) => RssInboxItem(
    id: id,
    feedId: feedId,
    source: source,
    title: title,
    link: link,
    eventDate: eventDate,
    startPart: startPart,
    slotLength: slotLength,
    imported: imported ?? this.imported,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'feedId': feedId,
    'source': source,
    'title': title,
    'link': link,
    'eventDate': eventDate.toIso8601String(),
    'startPart': startPart.name,
    'slotLength': slotLength,
    'imported': imported,
  };

  factory RssInboxItem.fromJson(Map<String, dynamic> json) => RssInboxItem(
    id: json['id'] as String,
    feedId: json['feedId'] as String? ?? '',
    source: json['source'] as String? ?? 'RSS',
    title: normalizeAllCapsTitle(json['title'] as String? ?? 'Untitled event'),
    link: json['link'] as String? ?? '',
    eventDate:
        DateTime.tryParse(json['eventDate'] as String? ?? '') ?? DateTime.now(),
    startPart: _enumByName(
      DayPart.values,
      json['startPart'],
      DayPart.afternoon,
    ),
    slotLength: (json['slotLength'] as num?)?.toInt() ?? 1,
    imported: json['imported'] as bool? ?? false,
  );
}

class DiagnosticLogEntry {
  const DiagnosticLogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.details,
  });

  final DateTime timestamp;
  final String level;
  final String category;
  final String message;
  final String? details;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level,
    'category': category,
    'message': message,
    'details': details,
  };

  factory DiagnosticLogEntry.fromJson(Map<String, dynamic> json) =>
      DiagnosticLogEntry(
        timestamp:
            DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        level: json['level'] as String? ?? 'info',
        category: json['category'] as String? ?? 'app',
        message: json['message'] as String? ?? '',
        details: json['details'] as String?,
      );
}

class CalendarBusyEvent {
  const CalendarBusyEvent({
    required this.title,
    required this.start,
    required this.end,
  });

  final String title;
  final DateTime start;
  final DateTime end;

  factory CalendarBusyEvent.fromMap(Map<Object?, Object?> map) =>
      CalendarBusyEvent(
        title: map['title'] as String? ?? '(untitled event)',
        start: DateTime.fromMillisecondsSinceEpoch(
          (map['start'] as num).toInt(),
        ),
        end: DateTime.fromMillisecondsSinceEpoch((map['end'] as num).toInt()),
      );
}

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime addDays(DateTime value, int days) =>
    dateOnly(value).add(Duration(days: days));

String isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

DateTime parseIsoDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
  if (match == null) {
    throw const FormatException('Use the YYYY-MM-DD date format.');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    throw const FormatException('Enter a real calendar date.');
  }
  return parsed;
}

DateTime? _tryParseIsoDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  try {
    return parseIsoDate(value);
  } on Object {
    return DateTime.tryParse(value);
  }
}

const monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String friendlyDate(DateTime value, {bool includeYear = false}) {
  final year = includeYear || value.year != DateTime.now().year
      ? ' ${value.year}'
      : '';
  return '${value.day} ${monthNames[value.month - 1]}$year';
}

DateTime firstRelevantFriday(DateTime now) {
  final today = dateOnly(now);
  return addDays(today, DateTime.friday - today.weekday);
}

DateTime slotDate(DateTime friday, int slotIndex) =>
    addDays(friday, WeekendSlot.all[slotIndex].dayOffset);

DateTime slotStart(DateTime friday, int slotIndex) {
  final date = slotDate(friday, slotIndex);
  final hour = switch (WeekendSlot.all[slotIndex].part) {
    DayPart.morning => 0,
    DayPart.afternoon => 12,
    DayPart.night => 18,
  };
  return DateTime(date.year, date.month, date.day, hour);
}

DateTime slotEnd(DateTime friday, int slotIndex) {
  final start = slotStart(friday, slotIndex);
  return switch (WeekendSlot.all[slotIndex].part) {
    DayPart.morning => start.add(const Duration(hours: 12)),
    DayPart.afternoon => start.add(const Duration(hours: 6)),
    DayPart.night => DateTime(
      start.add(const Duration(days: 1)).year,
      start.add(const Duration(days: 1)).month,
      start.add(const Duration(days: 1)).day,
    ),
  };
}

DayPart inferDayPart(DateTime date) {
  if (date.hour < 12) return DayPart.morning;
  if (date.hour < 18) return DayPart.afternoon;
  return DayPart.night;
}

WeekendDay? inferWeekendDay(DateTime date) => switch (date.weekday) {
  DateTime.friday => WeekendDay.friday,
  DateTime.saturday => WeekendDay.saturday,
  DateTime.sunday => WeekendDay.sunday,
  _ => null,
};

String normalizeAllCapsTitle(String input) {
  final title = input.trim().replaceAll(RegExp(r'\s+'), ' ');
  final letters = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]').allMatches(title).toList();
  if (letters.length < 2) return title;
  final hasLowercase = letters.any(
    (match) => match.group(0) == match.group(0)!.toLowerCase(),
  );
  if (hasLowercase) return title;

  final lowered = title.toLowerCase();
  final buffer = StringBuffer();
  var capitalizeNext = true;
  for (final rune in lowered.runes) {
    final character = String.fromCharCode(rune);
    final isLetter = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]').hasMatch(character);
    if (capitalizeNext && isLetter) {
      buffer.write(character.toUpperCase());
      capitalizeNext = false;
    } else {
      buffer.write(character);
    }
    if ('.!?'.contains(character)) capitalizeNext = true;
  }
  return buffer.toString();
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is String) {
    for (final value in values) {
      if (value.name == name) return value;
    }
  }
  return fallback;
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
