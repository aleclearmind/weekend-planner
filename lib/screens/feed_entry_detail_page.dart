import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../planner_store.dart';
import '../platform/platform_services.dart';
import '../widgets.dart';
import 'activity_form_page.dart';

class FeedEntryDetailPage extends StatelessWidget {
  const FeedEntryDetailPage({
    required this.store,
    required this.itemId,
    super.key,
  });

  final PlannerStore store;
  final String itemId;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final item = _item;
      if (item == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Feed entry')),
          body: const EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Entry no longer available',
            message: 'It may have been removed with its feed.',
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          title: const Text('Feed entry'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
          children: [
            Text(
              normalizeAllCapsTitle(item.title),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (item.imported) ...[
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: _ImportedBadge(),
              ),
            ],
            const SizedBox(height: 24),
            _InfoCard(
              children: [
                _InfoRow(
                  icon: Icons.dynamic_feed_rounded,
                  label: 'Source',
                  value: item.source,
                ),
                _InfoRow(
                  icon: Icons.event_rounded,
                  label: 'Date used for planning',
                  value: isoDate(item.eventDate),
                ),
                _InfoRow(
                  icon: Icons.schedule_rounded,
                  label: 'Suggested slot',
                  value:
                      '${item.startPart.name}, ${item.slotLength} '
                      '${item.slotLength == 1 ? 'slot' : 'slots'}',
                ),
                if (item.locationName != null)
                  _InfoRow(
                    icon: Icons.place_outlined,
                    label: 'Location',
                    value: item.locationName!,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'For iCalendar entries this date comes from DTSTART. RSS and '
              'Atom do not have a standard event-date field, so their date '
              'may be inferred from the entry.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (item.link.trim().isNotEmpty) ...[
              const SizedBox(height: 22),
              const SectionLabel('Source page'),
              Card(
                child: InkWell(
                  onTap: () => _openUrl(context, item.link),
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
                            item.link,
                            maxLines: 3,
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
            if (!item.imported) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _import(context, item),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Import as activity'),
              ),
            ],
          ],
        ),
      );
    },
  );

  RssInboxItem? get _item {
    for (final item in store.inbox) {
      if (item.id == itemId) return item;
    }
    return null;
  }

  Future<void> _import(BuildContext context, RssInboxItem item) async {
    final activity = store.importInboxItem(item);
    await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityFormPage(store: store, activity: activity),
      ),
    );
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
        Icon(icon, color: AppColors.primary, size: 21),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ImportedBadge extends StatelessWidget {
  const _ImportedBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.primaryContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_rounded, size: 16, color: AppColors.primary),
        SizedBox(width: 5),
        Text(
          'imported',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
