import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../planner_store.dart';
import '../widgets.dart';
import 'activity_form_page.dart';
import 'feed_manager_page.dart';
import 'feed_entry_detail_page.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({required this.store, super.key});

  final PlannerStore store;

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  final Set<String> _disabledFeedIds = {};

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final activeFeedIds = store.feeds
        .where((feed) => !_disabledFeedIds.contains(feed.id))
        .map((feed) => feed.id)
        .toSet();
    final currentInbox = store.inbox
        .where(
          (item) =>
              !dateOnly(item.eventDate).isBefore(dateOnly(DateTime.now())),
        )
        .toList();
    final visible = currentInbox
        .where((item) => activeFeedIds.contains(item.feedId))
        .toList();
    final pending = visible.where((item) => !item.imported).length;
    final sourceSummary = activeFeedIds.length == store.feeds.length
        ? '$pending new from ${store.feeds.length} '
              '${store.feeds.length == 1 ? 'feed' : 'feeds'}'
        : '$pending new from ${activeFeedIds.length} of '
              '${store.feeds.length} sources';
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
                      : sourceSummary,
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
        if (store.feeds.isNotEmpty)
          SizedBox(
            height: 45,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              children: [
                for (final feed in store.feeds) ...[
                  _SourceFilterButton(
                    feed: feed,
                    selected: activeFeedIds.contains(feed.id),
                    onToggle: () => setState(() {
                      if (activeFeedIds.contains(feed.id)) {
                        _disabledFeedIds.add(feed.id);
                      } else {
                        _disabledFeedIds.remove(feed.id);
                      }
                    }),
                    onOnly: () => setState(() {
                      _disabledFeedIds
                        ..clear()
                        ..addAll(
                          store.feeds
                              .where((candidate) => candidate.id != feed.id)
                              .map((candidate) => candidate.id),
                        );
                    }),
                  ),
                  const SizedBox(width: 7),
                ],
              ],
            ),
          ),
        Expanded(
          child: currentInbox.isEmpty
              ? EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'Your feed inbox is empty',
                  message: store.feeds.isEmpty
                      ? 'Add RSS, Atom, or iCalendar feeds, then import their '
                            'entries as activity ideas.'
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
                  title: activeFeedIds.isEmpty
                      ? 'No sources selected'
                      : 'No entries from selected sources',
                  message: activeFeedIds.isEmpty
                      ? 'Enable at least one source to see its events.'
                      : 'Enable another source or refresh the feeds.',
                  action: OutlinedButton(
                    onPressed: () => setState(_disabledFeedIds.clear),
                    child: const Text('Enable all sources'),
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
                            onOpen: () => _openEntry(context, item),
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

  Future<void> _openEntry(BuildContext context, RssInboxItem item) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            FeedEntryDetailPage(store: widget.store, itemId: item.id),
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
    final result = await widget.store.refreshFeeds();
    if (!context.mounted) return;
    final message = result.errors.isNotEmpty
        ? result.errors.join('\n')
        : result.skipped > 0
        ? '${result.added == 0 ? 'No dated events found.' : '${result.added} new ${result.added == 1 ? 'entry' : 'entries'} added.'} '
              '${result.skipped} ${result.skipped == 1 ? 'entry was' : 'entries were'} skipped because no event date could be found.'
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

class _SourceFilterButton extends StatelessWidget {
  const _SourceFilterButton({
    required this.feed,
    required this.selected,
    required this.onToggle,
    required this.onOnly,
  });

  final RssFeed feed;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onOnly;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.primaryDark : AppColors.muted;
    return Material(
      color: selected ? AppColors.primaryContainer : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: ValueKey('source-toggle-${feed.id}'),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              child: Text(
                feed.name,
                style: TextStyle(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
          Container(width: 1, height: 22, color: AppColors.border),
          Tooltip(
            message: 'Show only ${feed.name}',
            child: InkWell(
              key: ValueKey('source-only-${feed.id}'),
              onTap: onOnly,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                child: Text(
                  'Only',
                  style: TextStyle(
                    color: foreground,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxCard extends StatelessWidget {
  const _InboxCard({
    required this.item,
    required this.onOpen,
    required this.onImport,
    required this.onDismiss,
  });

  final RssInboxItem item;
  final VoidCallback onOpen;
  final VoidCallback? onImport;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              normalizeAllCapsTitle(item.title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      if (item.locationName != null) item.locationName!,
                      isoDate(item.eventDate),
                      item.startPart.name,
                      item.source,
                    ].join(' · '),
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
