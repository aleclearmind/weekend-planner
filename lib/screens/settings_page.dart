import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../planner_store.dart';
import '../platform/platform_services.dart';
import '../widgets.dart';
import 'event_log_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.store, super.key});

  final PlannerStore store;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 36),
        children: [
          const SectionLabel('Data'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.download_rounded,
                    color: AppColors.primary,
                  ),
                  title: const Text('Export database'),
                  subtitle: Text(
                    'JSON · schema ${PlannerStore.currentSchemaVersion}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _export(context),
                ),
                const Divider(height: 1, color: AppColors.outer),
                ListTile(
                  leading: const Icon(
                    Icons.receipt_long_outlined,
                    color: AppColors.primary,
                  ),
                  title: const Text('Event log'),
                  subtitle: Text(
                    '${store.eventLog.length} low-level '
                    '${store.eventLog.length == 1 ? 'entry' : 'entries'}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EventLogPage(store: store),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('Planner slots'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose every part of the week you want to plan. '
                    'At least one slot must stay enabled.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 13),
                  for (final day in WeekDay.values)
                    _DaySlotSelector(store: store, day: day),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('Calendar'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(
                    Icons.calendar_month_outlined,
                    color: AppColors.primary,
                  ),
                  title: const Text('Show Android calendar events'),
                  subtitle: Text(
                    PlatformServices.calendarSupported
                        ? 'Optional read-only access. The first event is '
                              'shown beside each available slot.'
                        : 'Available in the Android app.',
                  ),
                  value: PlatformServices.calendarSupported
                      ? store.calendarEnabled
                      : false,
                  onChanged: PlatformServices.calendarSupported
                      ? (value) => _toggleCalendar(context, value)
                      : null,
                ),
                if (store.calendarEnabled &&
                    store.availableCalendars.isNotEmpty) ...[
                  const Divider(height: 1, color: AppColors.outer),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 13, 16, 3),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Calendars to include',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ),
                  for (final calendar in store.availableCalendars)
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(calendar.name),
                      subtitle: Text(calendar.subtitle),
                      value: store.includedCalendarIds.contains(calendar.id),
                      onChanged: (value) => store.setCalendarIncluded(
                        calendar.id,
                        value ?? false,
                      ),
                    ),
                ] else if (store.calendarEnabled &&
                    !store.calendarSelectionInitialized) ...[
                  const Divider(height: 1, color: AppColors.outer),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Loading calendars…'),
                      ],
                    ),
                  ),
                ] else if (store.calendarEnabled) ...[
                  const Divider(height: 1, color: AppColors.outer),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('No visible Android calendars found.'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Calendar data is queried read-only and is not included in the '
            'planner database export.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          const SectionLabel('Feeds'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.sync_rounded, color: AppColors.primary),
              title: const Text('Automatic refresh'),
              subtitle: const Text(
                'RSS, Atom, and iCalendar feeds are checked every 30 minutes '
                'while the app is active and whenever it resumes.',
              ),
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('About this database'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Text(
                'The on-device database is explicitly versioned. Its current '
                'schema is ${PlannerStore.currentSchemaVersion}; schema '
                'updates run one migration step at a time.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _export(BuildContext context) async {
    try {
      await store.exportDatabase();
      if (context.mounted) {
        _message(context, 'Database export created.');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _message(context, 'Database export failed: $error');
      }
    }
  }

  Future<void> _toggleCalendar(BuildContext context, bool value) async {
    final enabled = await store.setCalendarEnabled(value);
    if (!context.mounted) return;
    if (value && !enabled) {
      _message(
        context,
        'Calendar access was not granted. You can enable it later.',
      );
    } else {
      _message(
        context,
        value ? 'Calendar events are now visible.' : 'Calendar overlay off.',
      );
    }
  }

  void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DaySlotSelector extends StatelessWidget {
  const _DaySlotSelector({required this.store, required this.day});

  final PlannerStore store;
  final WeekDay day;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            weekDayLabel(day),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final part in DayPart.values)
                FilterChip(
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  label: Text(switch (part) {
                    DayPart.morning => 'AM',
                    DayPart.afternoon => 'PM',
                    DayPart.night => 'Night',
                  }),
                  selected: store.enabledSlots.any(
                    (slot) => slot.weekDay == day && slot.part == part,
                  ),
                  onSelected: (value) =>
                      store.setSlotEnabled(PlannerSlot(day, part), value),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
