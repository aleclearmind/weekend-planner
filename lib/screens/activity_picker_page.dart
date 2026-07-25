import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../planner_store.dart';
import '../widgets.dart';
import 'activity_form_page.dart';

class ActivityPickerPage extends StatelessWidget {
  const ActivityPickerPage({
    required this.store,
    required this.weekStart,
    required this.slotIndex,
    super.key,
  });

  final PlannerStore store;
  final DateTime weekStart;
  final int slotIndex;

  @override
  Widget build(BuildContext context) {
    final selected = store.enabledSlots[slotIndex];
    final date = slotDate(weekStart, slotIndex, store.enabledSlots);
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final rows = List<ActivityIdea>.from(store.activities)
          ..sort((a, b) {
            final aFits = store.fitProblem(a, weekStart, slotIndex) == null;
            final bFits = store.fitProblem(b, weekStart, slotIndex) == null;
            if (aFits != bFits) return aFits ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
        return Scaffold(
          appBar: AppBar(
            leading: const BackButton(),
            title: const Text('Pick an activity'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(28),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(
                    '${selected.day} ${selected.partLabel} · '
                    '${friendlyDate(date)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          ),
          body: rows.isEmpty
              ? EmptyState(
                  icon: Icons.lightbulb_outline_rounded,
                  title: 'No activity ideas yet',
                  message:
                      'Create an idea first, then it will appear here when '
                      'its dates and slots fit.',
                  action: FilledButton.icon(
                    onPressed: () => _createActivity(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New activity'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
                  itemCount: rows.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (index == rows.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: OutlinedButton.icon(
                          onPressed: () => _createActivity(context),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Create another activity'),
                        ),
                      );
                    }
                    final activity = rows[index];
                    final problem = store.fitProblem(
                      activity,
                      weekStart,
                      slotIndex,
                    );
                    return _PickerCard(
                      activity: activity,
                      problem: problem,
                      frequencyWarning: store.frequencyWarning(activity),
                      showBookingWarning:
                          problem == null &&
                          activity.needsBooking &&
                          date.difference(dateOnly(DateTime.now())).inDays <=
                              14,
                      onAssign: problem == null
                          ? () {
                              store.assign(activity, weekStart, slotIndex);
                              Navigator.pop(context, activity);
                            }
                          : null,
                    );
                  },
                ),
        );
      },
    );
  }

  Future<void> _createActivity(BuildContext context) async {
    await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => ActivityFormPage(store: store)),
    );
  }
}

class _PickerCard extends StatelessWidget {
  const _PickerCard({
    required this.activity,
    required this.problem,
    required this.frequencyWarning,
    required this.showBookingWarning,
    required this.onAssign,
  });

  final ActivityIdea activity;
  final String? problem;
  final String? frequencyWarning;
  final bool showBookingWarning;
  final VoidCallback? onAssign;

  @override
  Widget build(BuildContext context) {
    final fits = problem == null;
    return Opacity(
      opacity: fits ? 1 : 0.58,
      child: Card(
        color: fits ? AppColors.surfaceStrong : const Color(0xFFEFF1EF),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onAssign,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        activity.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (activity.needsBooking) ...[
                      const SizedBox(width: 8),
                      const BookingBadge(compact: true),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  activity.slotLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  activity.rangeLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (frequencyWarning != null) ...[
                  const SizedBox(height: 10),
                  FrequencyWarningBadge(message: frequencyWarning!),
                ],
                if (problem != null) ...[
                  const SizedBox(height: 10),
                  Text(problem!, style: Theme.of(context).textTheme.bodySmall),
                ],
                if (showBookingWarning) ...[
                  const SizedBox(height: 11),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1DC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: AppColors.warning,
                          size: 18,
                        ),
                        SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'This needs booking and the selected date is only '
                            'days away.',
                            style: TextStyle(
                              color: AppColors.warning,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
