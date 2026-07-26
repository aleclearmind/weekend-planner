import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../planner_store.dart';
import '../widgets.dart';
import 'activity_form_page.dart';

class ActivityPickerPage extends StatefulWidget {
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
  State<ActivityPickerPage> createState() => _ActivityPickerPageState();
}

class _ActivityPickerPageState extends State<ActivityPickerPage> {
  String? _tagFilter;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final selectedSlot = store.enabledSlots[widget.slotIndex];
    final date = slotDate(
      widget.weekStart,
      widget.slotIndex,
      store.enabledSlots,
    );
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final tags = _availableTags;
        final selectedTag = tags
            .where((tag) => tag.toLowerCase() == _tagFilter?.toLowerCase())
            .firstOrNull;
        final rows =
            store.activities
                .where(
                  (activity) =>
                      selectedTag == null ||
                      activity.tags.any(
                        (tag) => tag.toLowerCase() == selectedTag.toLowerCase(),
                      ),
                )
                .toList()
              ..sort((a, b) {
                final aFits =
                    store.fitProblem(a, widget.weekStart, widget.slotIndex) ==
                    null;
                final bFits =
                    store.fitProblem(b, widget.weekStart, widget.slotIndex) ==
                    null;
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
                    '${selectedSlot.day} ${selectedSlot.partLabel} · '
                    '${friendlyDate(date)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          ),
          body: Column(
            children: [
              if (tags.isNotEmpty)
                SizedBox(
                  height: 49,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
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
                child: store.activities.isEmpty
                    ? EmptyState(
                        icon: Icons.lightbulb_outline_rounded,
                        title: 'No activity ideas yet',
                        message:
                            'Create an idea first, then it will appear here '
                            'when its dates and slots fit.',
                        action: FilledButton.icon(
                          onPressed: () => _createActivity(context),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('New activity'),
                        ),
                      )
                    : rows.isEmpty
                    ? EmptyState(
                        icon: Icons.filter_alt_off_outlined,
                        title: 'No activities with this tag',
                        message: 'Choose another tag to see more ideas.',
                        action: OutlinedButton(
                          onPressed: () => setState(() => _tagFilter = null),
                          child: const Text('Show all tags'),
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
                            widget.weekStart,
                            widget.slotIndex,
                          );
                          return _PickerCard(
                            activity: activity,
                            problem: problem,
                            frequencyWarning: store.frequencyWarning(activity),
                            onAssign: problem == null
                                ? () {
                                    store.assign(
                                      activity,
                                      widget.weekStart,
                                      widget.slotIndex,
                                    );
                                    Navigator.pop(context, activity);
                                  }
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
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

  Future<void> _createActivity(BuildContext context) async {
    await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => ActivityFormPage(store: widget.store)),
    );
  }
}

class _PickerCard extends StatelessWidget {
  const _PickerCard({
    required this.activity,
    required this.problem,
    required this.frequencyWarning,
    required this.onAssign,
  });

  final ActivityIdea activity;
  final String? problem;
  final String? frequencyWarning;
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
                Text(
                  activity.name,
                  style: Theme.of(context).textTheme.titleMedium,
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
                if (activity.tags.isNotEmpty) ...[
                  const SizedBox(height: 9),
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
                if (frequencyWarning != null) ...[
                  const SizedBox(height: 10),
                  FrequencyWarningBadge(message: frequencyWarning!),
                ],
                if (problem != null) ...[
                  const SizedBox(height: 10),
                  Text(problem!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
