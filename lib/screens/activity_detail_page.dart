import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../planner_store.dart';
import '../platform/platform_services.dart';
import '../widgets.dart';
import 'activity_form_page.dart';

class ActivityDetailPage extends StatelessWidget {
  const ActivityDetailPage({
    required this.store,
    required this.activityId,
    super.key,
  });

  final PlannerStore store;
  final String activityId;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final activity = store.activityById(activityId);
      if (activity == null) {
        return const Scaffold(body: SizedBox.shrink());
      }
      final placements = store.placementsForActivity(activity.id);
      final frequencyWarning = store.frequencyWarning(activity);
      return Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          title: const Text('Activity'),
          actions: [
            IconButton(
              tooltip: 'Edit activity',
              onPressed: () => _edit(context, activity),
              icon: const Icon(Icons.edit_outlined),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
          children: [
            Text(
              activity.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                if (activity.needsBooking) const BookingBadge(),
                if (activity.isRecurring)
                  const _DetailBadge(
                    icon: Icons.repeat_rounded,
                    label: 'recurring',
                  ),
                if (activity.frequencyLabel != null)
                  _DetailBadge(
                    icon: Icons.timelapse_rounded,
                    label: activity.frequencyLabel!.toLowerCase(),
                  ),
              ],
            ),
            if (frequencyWarning != null) ...[
              const SizedBox(height: 13),
              FrequencyWarningBadge(message: frequencyWarning),
            ],
            const SizedBox(height: 24),
            _InfoCard(
              children: [
                _InfoRow(
                  icon: Icons.date_range_rounded,
                  label: 'Dates',
                  value: activity.rangeLabel,
                ),
                _InfoRow(
                  icon: Icons.view_timeline_outlined,
                  label: 'Slots',
                  value: activity.slotLabel,
                ),
                _InfoRow(
                  icon: Icons.event_available_rounded,
                  label: 'Planning',
                  value: activity.needsBooking
                      ? 'Needs booking'
                      : 'No booking needed',
                ),
              ],
            ),
            if (activity.location != null) ...[
              const SizedBox(height: 22),
              const SectionLabel('Location'),
              Card(
                child: InkWell(
                  onTap: activity.location!.hasCoordinates
                      ? () => _openLocation(context, activity)
                      : null,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.place_rounded,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                activity.location!.name.isEmpty
                                    ? 'Pinned location'
                                    : activity.location!.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (activity.location!.hasCoordinates)
                                Text(
                                  activity.location!.coordinateLabel,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        if (activity.location!.hasCoordinates)
                          const Icon(
                            Icons.open_in_new_rounded,
                            size: 19,
                            color: AppColors.faint,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (activity.url != null) ...[
              const SizedBox(height: 22),
              const SectionLabel('Link'),
              Card(
                child: InkWell(
                  onTap: () => _openUrl(context, activity.url!),
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.link_rounded,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            activity.url!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.open_in_new_rounded,
                          size: 19,
                          color: AppColors.faint,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (activity.people.isNotEmpty) ...[
              const SizedBox(height: 22),
              const SectionLabel('People who might join'),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final person in activity.people)
                    Chip(
                      avatar: StatusDot(person.status),
                      label: Text(
                        '${person.name} · '
                        '${interestLabel(person.status).toLowerCase()}',
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(child: SectionLabel('Assignments')),
                Text(
                  '${placements.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (placements.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        color: AppColors.faint,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Not assigned to a weekend yet.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < placements.length;
                        index++
                      ) ...[
                        if (index > 0)
                          const Divider(height: 1, color: AppColors.outer),
                        _AssignmentRow(placement: placements[index]),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  Future<void> _edit(BuildContext context, ActivityIdea activity) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityFormPage(store: store, activity: activity),
      ),
    );
    if (!context.mounted || result == null) return;
    if (result == 'deleted') {
      Navigator.pop(context, 'deleted');
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Activity updated.')));
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
        _message(context, 'OsmAnd could not be opened on this device.');
      }
    } on Object catch (error) {
      if (context.mounted) _message(context, 'Could not open location: $error');
    }
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    try {
      final opened = await PlatformServices.openUrl(url);
      if (!opened && context.mounted) {
        _message(context, 'No app could open this URL.');
      }
    } on Object catch (error) {
      if (context.mounted) _message(context, 'Could not open URL: $error');
    }
  }

  void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const Divider(height: 1, color: AppColors.outer),
            children[index],
          ],
        ],
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 12),
        SizedBox(
          width: 68,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _DetailBadge extends StatelessWidget {
  const _DetailBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.primaryContainer,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.primaryDark),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.primaryDark,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _AssignmentRow extends StatelessWidget {
  const _AssignmentRow({required this.placement});

  final ActivityPlacement placement;

  @override
  Widget build(BuildContext context) {
    final isPast = placement.date.isBefore(dateOnly(DateTime.now()));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      child: Row(
        children: [
          Icon(
            isPast ? Icons.history_rounded : Icons.event_rounded,
            size: 20,
            color: isPast ? AppColors.faint : AppColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  placement.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${placement.slotLength} '
                  '${placement.slotLength == 1 ? 'slot' : 'slots'} · '
                  '${isPast ? 'past' : 'upcoming'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
