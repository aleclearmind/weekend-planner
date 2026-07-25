import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../planner_store.dart';
import '../widgets.dart';
import 'activity_detail_page.dart';
import 'activity_form_page.dart';

class ActivitiesPage extends StatefulWidget {
  const ActivitiesPage({
    required this.store,
    required this.onCreate,
    super.key,
  });

  final PlannerStore store;
  final VoidCallback onCreate;

  @override
  State<ActivitiesPage> createState() => _ActivitiesPageState();
}

class _ActivitiesPageState extends State<ActivitiesPage> {
  bool _bookingOnly = false;

  @override
  Widget build(BuildContext context) {
    final activities = widget.store.activities
        .where((activity) => !_bookingOnly || activity.needsBooking)
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.store.activities.length} ideas ready for a '
                  'free slot',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              FilterChip(
                selected: _bookingOnly,
                avatar: Icon(
                  _bookingOnly
                      ? Icons.check_rounded
                      : Icons.filter_list_rounded,
                  size: 17,
                ),
                label: const Text('Needs booking'),
                onSelected: (value) => setState(() => _bookingOnly = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: activities.isEmpty
              ? EmptyState(
                  icon: _bookingOnly
                      ? Icons.event_available_rounded
                      : Icons.lightbulb_outline_rounded,
                  title: _bookingOnly
                      ? 'Nothing needs booking'
                      : 'No activity ideas yet',
                  message: _bookingOnly
                      ? 'Turn off the filter to see spontaneous activities.'
                      : 'Save things you would enjoy, then assign them to '
                            'weekend slots.',
                  action: _bookingOnly
                      ? OutlinedButton(
                          onPressed: () => setState(() => _bookingOnly = false),
                          child: const Text('Show every idea'),
                        )
                      : FilledButton.icon(
                          onPressed: widget.onCreate,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('New activity'),
                        ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 112),
                  itemCount: activities.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 11),
                  itemBuilder: (context, index) => _ActivityCard(
                    activity: activities[index],
                    frequencyWarning: widget.store.frequencyWarning(
                      activities[index],
                    ),
                    onView: () => _view(activities[index]),
                    onEdit: () => _edit(activities[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _view(ActivityIdea activity) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ActivityDetailPage(store: widget.store, activityId: activity.id),
      ),
    );
    if (!mounted || result != 'deleted') return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Activity deleted.')));
  }

  Future<void> _edit(ActivityIdea activity) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ActivityFormPage(store: widget.store, activity: activity),
      ),
    );
    if (!mounted || result == null) return;
    final message = result == 'deleted'
        ? 'Activity deleted.'
        : 'Activity updated.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.activity,
    required this.frequencyWarning,
    required this.onView,
    required this.onEdit,
  });

  final ActivityIdea activity;
  final String? frequencyWarning;
  final VoidCallback onView;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onView,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 15, 10, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        activity.rangeLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        activity.slotLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (activity.needsBooking) ...[
                  const SizedBox(width: 8),
                  const BookingBadge(),
                ],
                if (activity.isRecurring) ...[
                  const SizedBox(width: 7),
                  const Icon(
                    Icons.repeat_rounded,
                    size: 19,
                    color: AppColors.primary,
                  ),
                ],
                IconButton(
                  tooltip: 'Edit activity',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
              ],
            ),
            if (frequencyWarning != null) ...[
              const SizedBox(height: 10),
              FrequencyWarningBadge(message: frequencyWarning!),
            ],
            if (activity.people.isNotEmpty) ...[
              const SizedBox(height: 11),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final person in activity.people)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatusDot(person.status, size: 7),
                          const SizedBox(width: 6),
                          Text(
                            person.name,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
