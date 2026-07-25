import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../planner_store.dart';
import '../widgets.dart';

class FeedManagerPage extends StatefulWidget {
  const FeedManagerPage({required this.store, super.key});

  final PlannerStore store;

  @override
  State<FeedManagerPage> createState() => _FeedManagerPageState();
}

class _FeedManagerPageState extends State<FeedManagerPage> {
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Feeds'),
        actions: [
          IconButton(
            tooltip: 'Refresh all feeds',
            onPressed:
                widget.store.feeds.isEmpty || widget.store.isRefreshingFeeds
                ? null
                : _refreshAll,
            icon: widget.store.isRefreshingFeeds
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
        children: [
          Text(
            'Add RSS, Atom, or iCalendar (.ics) feeds from venues and '
            'calendars. New entries land in the Inbox as activity ideas.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
          const SectionLabel('Feed URL'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addFeed(),
                  decoration: const InputDecoration(
                    hintText: 'https://venue.example/events.rss or .ics',
                    prefixIcon: Icon(Icons.add_link_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              SizedBox(
                height: 54,
                child: FilledButton(
                  onPressed: widget.store.isRefreshingFeeds ? null : _addFeed,
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Row(
            children: [
              const Expanded(child: SectionLabel('Your feeds')),
              if (widget.store.feeds.isNotEmpty)
                Text(
                  '${widget.store.feeds.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          if (widget.store.feeds.isEmpty)
            const EmptyState(
              icon: Icons.dynamic_feed_outlined,
              title: 'No feeds connected',
              message:
                  'Paste an RSS, Atom, iCalendar, or discoverable web page '
                  'URL above. We will remember it on this device.',
            )
          else
            ...widget.store.feeds.map(
              (feed) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FeedCard(
                  feed: feed,
                  itemCount: widget.store.inbox
                      .where((item) => item.feedId == feed.id)
                      .length,
                  onRefresh: widget.store.isRefreshingFeeds
                      ? null
                      : () => _refresh(feed),
                  onRename: () => _rename(feed),
                  onRemove: () => _remove(feed),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Future<void> _addFeed() async {
    try {
      final feed = await widget.store.addFeed(_urlController.text);
      _urlController.clear();
      if (!mounted) return;
      _showMessage('Feed added. Checking it now…');
      await _refresh(feed);
    } on FormatException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _refresh(RssFeed feed) async {
    final result = await widget.store.refreshFeeds(onlyFeedId: feed.id);
    if (!mounted) return;
    _showRefreshResult(result);
  }

  Future<void> _refreshAll() async {
    final result = await widget.store.refreshFeeds();
    if (!mounted) return;
    _showRefreshResult(result);
  }

  void _showRefreshResult(FeedRefreshResult result) {
    if (result.errors.isNotEmpty) {
      _showMessage(result.errors.join('\n'));
    } else {
      _showMessage(
        result.added == 0
            ? 'Feeds are up to date.'
            : '${result.added} new '
                  '${result.added == 1 ? 'entry' : 'entries'} added.',
      );
    }
  }

  Future<void> _rename(RssFeed feed) async {
    final controller = TextEditingController(text: feed.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename feed'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null) widget.store.renameFeed(feed.id, name);
  }

  Future<void> _remove(RssFeed feed) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${feed.name}?'),
        content: const Text(
          'Its Inbox entries will be removed too. Activities you already '
          'imported stay in your ideas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.store.removeFeed(feed.id);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({
    required this.feed,
    required this.itemCount,
    required this.onRefresh,
    required this.onRename,
    required this.onRemove,
  });

  final RssFeed feed;
  final int itemCount;
  final VoidCallback? onRefresh;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(15, 14, 8, 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              feed.kind == FeedKind.ics
                  ? Icons.calendar_month_rounded
                  : Icons.rss_feed_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(feed.name, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  '${feed.kind == FeedKind.ics ? 'iCalendar' : 'RSS / Atom'} · '
                  '$itemCount ${itemCount == 1 ? 'entry' : 'entries'} · '
                  '${feed.lastChecked == null ? 'not checked yet' : 'checked ${friendlyDate(feed.lastChecked!)}'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  feed.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh feed',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'Feed options',
            onSelected: (value) {
              if (value == 'rename') onRename();
              if (value == 'remove') onRemove();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'remove', child: Text('Remove')),
            ],
          ),
        ],
      ),
    ),
  );
}
