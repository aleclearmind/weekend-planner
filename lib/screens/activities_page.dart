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
  String? _tagFilter;

  @override
  Widget build(BuildContext context) {
    final tags = _availableTags;
    final selectedTag = tags
        .where((tag) => tag.toLowerCase() == _tagFilter?.toLowerCase())
        .firstOrNull;
    final activities = widget.store.activities
        .where(
          (activity) =>
              selectedTag == null ||
              activity.tags.any(
                (tag) => tag.toLowerCase() == selectedTag.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${widget.store.activities.length} ideas ready for a free slot',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        if (tags.isNotEmpty)
          SizedBox(
            height: 43,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              children: [
                ChoiceChip(
                  showCheckmark: false,
                  label: const Text('All tags'),
                  selected: selectedTag == null,
                  onSelected: (_) => setState(() => _tagFilter = null),
                ),
                const SizedBox(width: 7),
                for (final tag in tags) ...[
                  ChoiceChip(
                    showCheckmark: false,
                    label: Text('#$tag'),
                    selected: selectedTag == tag,
                    onSelected: (_) => setState(() => _tagFilter = tag),
                  ),
                  const SizedBox(width: 7),
                ],
              ],
            ),
          ),
        Expanded(
          child: activities.isEmpty
              ? EmptyState(
                  icon: selectedTag != null
                      ? Icons.event_available_rounded
                      : Icons.lightbulb_outline_rounded,
                  title: selectedTag != null
                      ? 'No matching activities'
                      : 'No activity ideas yet',
                  message: selectedTag != null
                      ? 'Clear the filters to see every activity idea.'
                      : 'Save things you would enjoy, then assign them to '
                            'planner slots.',
                  action: selectedTag != null
                      ? OutlinedButton(
                          onPressed: () => setState(() => _tagFilter = null),
                          child: const Text('Clear filters'),
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

  List<String> get _availableTags {
    final tagsByKey = <String, String>{};
    for (final activity in widget.store.activities) {
      for (final tag in activity.tags) {
        tagsByKey.putIfAbsent(tag.toLowerCase(), () => tag);
      }
    }
    return tagsByKey.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
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
            if (activity.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in activity.tags)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('#$tag'),
                    ),
                ],
              ),
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
