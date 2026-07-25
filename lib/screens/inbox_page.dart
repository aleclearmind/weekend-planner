import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../planner_store.dart';
import '../widgets.dart';
import 'activity_form_page.dart';
import 'feed_manager_page.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({required this.store, super.key});

  final PlannerStore store;

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  String? _feedFilter;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final selectedFeed = store.feeds.any((feed) => feed.id == _feedFilter)
        ? _feedFilter
        : null;
    final visible = store.inbox
        .where((item) => selectedFeed == null || item.feedId == selectedFeed)
        .toList();
    final pending = visible.where((item) => !item.imported).length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  store.feeds.isEmpty
                      ? 'Connect a venue feed to start an inbox'
                      : '$pending new from ${store.feeds.length} '
                            '${store.feeds.length == 1 ? 'feed' : 'feeds'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _openFeeds(context),
                icon: const Icon(Icons.rss_feed_rounded, size: 18),
                label: const Text('Feeds'),
              ),
            ],
          ),
        ),
        if (store.feeds.length > 1)
          SizedBox(
            height: 43,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              children: [
                ChoiceChip(
                  label: const Text('All sources'),
                  selected: selectedFeed == null,
                  onSelected: (_) => setState(() => _feedFilter = null),
                ),
                const SizedBox(width: 7),
                for (final feed in store.feeds) ...[
                  ChoiceChip(
                    label: Text(feed.name),
                    selected: selectedFeed == feed.id,
                    onSelected: (_) => setState(() => _feedFilter = feed.id),
                  ),
                  const SizedBox(width: 7),
                ],
              ],
            ),
          ),
        Expanded(
          child: store.inbox.isEmpty
              ? EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'Your RSS inbox is empty',
                  message: store.feeds.isEmpty
                      ? 'Add feeds from venues and local guides, then import '
                            'their entries as activity ideas.'
                      : 'Refresh your feeds to look for new entries.',
                  action: store.feeds.isEmpty
                      ? FilledButton.icon(
                          onPressed: () => _openFeeds(context),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add a feed'),
                        )
                      : FilledButton.icon(
                          onPressed: store.isRefreshingFeeds
                              ? null
                              : () => _refresh(context),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Refresh feeds'),
                        ),
                )
              : visible.isEmpty
              ? EmptyState(
                  icon: Icons.filter_alt_off_outlined,
                  title: 'No entries from this source',
                  message: 'Choose another source or refresh the feed.',
                  action: OutlinedButton(
                    onPressed: () => setState(() => _feedFilter = null),
                    child: const Text('Show all sources'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _refresh(context),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      final week = _weekStart(item.eventDate);
                      final previousWeek = index == 0
                          ? null
                          : _weekStart(visible[index - 1].eventDate);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (previousWeek != week)
                            _WeekHeading(week: week, first: index == 0),
                          _InboxCard(
                            item: item,
                            onImport: item.imported
                                ? null
                                : () => _import(context, item),
                            onDismiss: item.imported
                                ? null
                                : () => store.dismissInboxItem(item.id),
                          ),
                          const SizedBox(height: 6),
                        ],
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _import(BuildContext context, RssInboxItem item) async {
    final activity = widget.store.importInboxItem(item);
    await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ActivityFormPage(store: widget.store, activity: activity),
      ),
    );
  }

  Future<void> _openFeeds(BuildContext context) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => FeedManagerPage(store: widget.store)),
    );
  }

  Future<void> _refresh(BuildContext context) async {
    final result = await widget.store.refreshFeeds(onlyFeedId: _feedFilter);
    if (!context.mounted) return;
    final message = result.errors.isNotEmpty
        ? result.errors.join('\n')
        : result.added == 0
        ? 'Feeds are up to date.'
        : '${result.added} new '
              '${result.added == 1 ? 'entry' : 'entries'} added.';
    _showMessage(context, message);
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _InboxCard extends StatelessWidget {
  const _InboxCard({
    required this.item,
    required this.onImport,
    required this.onDismiss,
  });

  final RssInboxItem item;
  final VoidCallback? onImport;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            normalizeAllCapsTitle(item.title),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${item.source} · ${isoDate(item.eventDate)} · '
                  '${item.startPart.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (item.imported)
                const Padding(
                  padding: EdgeInsets.only(left: 8, right: 5),
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                )
              else ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onDismiss,
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
                FilledButton.tonalIcon(
                  onPressed: onImport,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Import'),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}

class _WeekHeading extends StatelessWidget {
  const _WeekHeading({required this.week, required this.first});

  final DateTime week;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(3, first ? 7 : 13, 3, 6),
    child: Text(
      _weekLabel(week),
      style: const TextStyle(
        color: AppColors.muted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.25,
      ),
    ),
  );
}

DateTime _weekStart(DateTime date) => addDays(dateOnly(date), 1 - date.weekday);

String _weekLabel(DateTime week) {
  final current = _weekStart(DateTime.now());
  if (week == current) return 'This week';
  if (week == addDays(current, 7)) return 'Next week';
  return '${isoDate(week)} — ${isoDate(addDays(week, 6))}';
}
