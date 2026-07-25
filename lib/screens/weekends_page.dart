import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../planner_store.dart';
import '../platform/platform_services.dart';
import 'activity_detail_page.dart';
import 'activity_picker_page.dart';

class WeekendsPage extends StatefulWidget {
  const WeekendsPage({required this.store, this.now, super.key});

  final PlannerStore store;
  final DateTime? now;

  @override
  State<WeekendsPage> createState() => _WeekendsPageState();
}

class _WeekendsPageState extends State<WeekendsPage> {
  int _weeksShown = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.store.refreshCalendarForWeeks(weeks: _weeksShown),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now ?? DateTime.now();
    final today = dateOnly(now);
    final currentWeek = weekStartFor(today);
    final firstWeek = firstRelevantWeekStart(now, widget.store.enabledSlots);
    final initialWeekOffset = firstWeek.difference(currentWeek).inDays ~/ 7;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 28),
      itemCount: _weeksShown + 1,
      itemBuilder: (context, weekendIndex) {
        if (weekendIndex == _weeksShown) {
          return Padding(
            padding: const EdgeInsets.only(top: 2),
            child: OutlinedButton(
              onPressed: () {
                setState(() => _weeksShown += 4);
                widget.store.refreshCalendarForWeeks(weeks: _weeksShown);
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                shape: const StadiumBorder(),
              ),
              child: const Text('Load more weeks'),
            ),
          );
        }
        final weekStart = addDays(firstWeek, weekendIndex * 7);
        final absoluteWeekIndex = initialWeekOffset + weekendIndex;
        return _WeekendSection(
          store: widget.store,
          weekStart: weekStart,
          today: today,
          weekIndex: absoluteWeekIndex,
          onOpenPicker: (slotIndex) => _openPicker(weekStart, slotIndex),
          onOpenActivity: _openActivity,
          onClear: (slotIndex) {
            widget.store.clearAssignment(weekStart, slotIndex);
            _showMessage('Activity cleared from this week.');
          },
        );
      },
    );
  }

  Future<void> _openPicker(DateTime weekStart, int slotIndex) async {
    final activity = await Navigator.push<ActivityIdea>(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityPickerPage(
          store: widget.store,
          weekStart: weekStart,
          slotIndex: slotIndex,
        ),
      ),
    );
    if (activity == null || !mounted) return;
    _showMessage(
      activity.needsBooking
          ? '${activity.name} assigned — remember to book it.'
          : '${activity.name} assigned.',
    );
  }

  Future<void> _openActivity(ActivityIdea activity) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ActivityDetailPage(store: widget.store, activityId: activity.id),
      ),
    );
    if (result == null || !mounted) return;
    if (result == 'deleted') _showMessage('Activity deleted.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _WeekendSection extends StatelessWidget {
  const _WeekendSection({
    required this.store,
    required this.weekStart,
    required this.today,
    required this.weekIndex,
    required this.onOpenPicker,
    required this.onOpenActivity,
    required this.onClear,
  });

  final PlannerStore store;
  final DateTime weekStart;
  final DateTime today;
  final int weekIndex;
  final ValueChanged<int> onOpenPicker;
  final ValueChanged<ActivityIdea> onOpenActivity;
  final ValueChanged<int> onClear;

  @override
  Widget build(BuildContext context) {
    final days = <({String name, DateTime date, List<int> slotIndexes})>[
      for (final day in WeekDay.values)
        if (store.enabledSlots.any((slot) => slot.weekDay == day))
          (
            name: weekDayLabel(day),
            date: addDays(weekStart, day.index),
            slotIndexes: [
              for (var index = 0; index < store.enabledSlots.length; index++)
                if (store.enabledSlots[index].weekDay == day) index,
            ],
          ),
    ].where((day) => !day.date.isBefore(today)).toList();
    final label = switch (weekIndex) {
      0 => 'This week',
      1 => 'Next week',
      _ => 'Week ${weekIndex + 1}',
    };
    final firstDate = days.isEmpty ? weekStart : days.first.date;
    final lastDate = days.isEmpty ? addDays(weekStart, 6) : days.last.date;
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(3, 7, 3, 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${friendlyDate(firstDate)}–${friendlyDate(lastDate)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          for (var position = 0; position < days.length; position++) ...[
            if (position > 0) const SizedBox(height: 13),
            _DayGroup(
              key: ValueKey('weekend-day-${isoDate(days[position].date)}'),
              name: days[position].name,
              date: days[position].date,
              slotIndexes: days[position].slotIndexes,
              store: store,
              weekStart: weekStart,
              onOpenPicker: onOpenPicker,
              onOpenActivity: onOpenActivity,
              onClear: onClear,
            ),
          ],
        ],
      ),
    );
  }
}

class _DayGroup extends StatelessWidget {
  const _DayGroup({
    super.key,
    required this.name,
    required this.date,
    required this.slotIndexes,
    required this.store,
    required this.weekStart,
    required this.onOpenPicker,
    required this.onOpenActivity,
    required this.onClear,
  });

  final String name;
  final DateTime date;
  final List<int> slotIndexes;
  final PlannerStore store;
  final DateTime weekStart;
  final ValueChanged<int> onOpenPicker;
  final ValueChanged<ActivityIdea> onOpenActivity;
  final ValueChanged<int> onClear;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(3, 0, 3, 6),
        child: Row(
          children: [
            Text(
              name,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              friendlyDate(date),
              style: const TextStyle(fontSize: 11.5, color: AppColors.faint),
            ),
          ],
        ),
      ),
      ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Column(
          children: [
            for (
              var position = 0;
              position < slotIndexes.length;
              position++
            ) ...[
              if (position > 0)
                const Divider(height: 1, color: AppColors.outer),
              _SlotRow(
                store: store,
                weekStart: weekStart,
                slotIndex: slotIndexes[position],
                onOpenPicker: () => onOpenPicker(slotIndexes[position]),
                onOpenActivity: onOpenActivity,
                onClear: () => onClear(slotIndexes[position]),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.store,
    required this.weekStart,
    required this.slotIndex,
    required this.onOpenPicker,
    required this.onOpenActivity,
    required this.onClear,
  });

  final PlannerStore store;
  final DateTime weekStart;
  final int slotIndex;
  final VoidCallback onOpenPicker;
  final ValueChanged<ActivityIdea> onOpenActivity;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final slot = store.enabledSlots[slotIndex];
    final assignment = store.assignmentAt(weekStart, slotIndex);
    final activity = assignment == null
        ? null
        : store.activityById(assignment.activityId);
    final calendarTitle = store.calendarEventAt(weekStart, slotIndex);
    return Container(
      color: AppColors.surface,
      constraints: const BoxConstraints(minHeight: 66),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  slot.day,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  slot.partLabel.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.1,
                    letterSpacing: 0.65,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (activity == null)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onOpenPicker,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      const Text(
                        '+',
                        style: TextStyle(
                          fontSize: 24,
                          height: 0.9,
                          fontWeight: FontWeight.w300,
                          color: AppColors.faint,
                        ),
                      ),
                      if (calendarTitle != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            calendarTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: AppColors.faint,
                              fontSize: 11.5,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            )
          else ...[
            Expanded(
              child: Material(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onOpenActivity(activity),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                activity.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ),
                            if (assignment!.total > 1)
                              Text(
                                '${assignment.part}/${assignment.total}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                              ),
                          ],
                        ),
                        if (activity.people.isNotEmpty)
                          Text(
                            activity.people
                                .map((person) => person.name)
                                .join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                            ),
                          ),
                        if (activity.location != null)
                          Text(
                            activity.location!.name.isEmpty
                                ? activity.location!.coordinateLabel
                                : activity.location!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (activity.location?.hasCoordinates ?? false)
              IconButton(
                tooltip: 'Open location in OsmAnd',
                onPressed: () => _openLocation(context, activity),
                icon: const Icon(Icons.place_outlined, size: 20),
              ),
            IconButton(
              tooltip: 'Clear activity',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openLocation(
    BuildContext context,
    ActivityIdea activity,
  ) async {
    final location = activity.location!;
    try {
      final opened = await PlatformServices.openOsmAnd(
        latitude: location.latitude!,
        longitude: location.longitude!,
        label: location.name.isEmpty ? activity.name : location.name,
      );
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OsmAnd could not be opened.')),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open OsmAnd: $error')),
        );
      }
    }
  }
}
