import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../planner_store.dart';
import '../widgets.dart';

class EventLogPage extends StatelessWidget {
  const EventLogPage({required this.store, super.key});

  final PlannerStore store;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Event log'),
        actions: [
          IconButton(
            tooltip: 'Clear event log',
            onPressed: store.eventLog.isEmpty ? null : () => _clear(context),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: store.eventLog.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No events logged',
              message:
                  'HTTP requests, parser failures, calendar access, and data '
                  'exports will leave diagnostic details here.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 36),
              itemCount: store.eventLog.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _LogCard(entry: store.eventLog[index]),
            ),
    ),
  );

  Future<void> _clear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear the event log?'),
        content: const Text('This only removes diagnostic entries.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) store.clearEventLog();
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.entry});

  final DiagnosticLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final isError = entry.level == 'error';
    final color = isError
        ? Theme.of(context).colorScheme.error
        : entry.level == 'warning'
        ? AppColors.warning
        : AppColors.primary;
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          isError
              ? Icons.error_outline_rounded
              : entry.level == 'warning'
              ? Icons.warning_amber_rounded
              : Icons.info_outline_rounded,
          color: color,
        ),
        title: Text(
          entry.message,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${_timestamp(entry.timestamp)} · '
          '${entry.category.toUpperCase()} · ${entry.level.toUpperCase()}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        children: [
          if (entry.details != null && entry.details!.trim().isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(15, 0, 15, 15),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                entry.details!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _timestamp(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}:'
      '${value.second.toString().padLeft(2, '0')}';
}
