import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../planner_store.dart';
import '../widgets.dart';

class PeoplePage extends StatelessWidget {
  const PeoplePage({required this.store, super.key});

  final PlannerStore store;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    if (store.cachedPeople.isEmpty) {
      return EmptyState(
        icon: Icons.group_outlined,
        title: 'No saved names yet',
        message:
            'Save someone here and their name will be suggested whenever '
            'you edit an activity.',
        action: FilledButton.icon(
          onPressed: () => _addPerson(context),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Add person'),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(3, 0, 3, 13),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Names are cached locally for activity autocomplete.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                onPressed: () => _addPerson(context),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            children: [
              for (
                var index = 0;
                index < store.cachedPeople.length;
                index++
              ) ...[
                if (index > 0) const Divider(height: 1, color: AppColors.outer),
                _PersonRow(
                  name: store.cachedPeople[index],
                  activityCount: store.activities
                      .where(
                        (activity) => activity.people.any(
                          (person) =>
                              person.name.toLowerCase() ==
                              store.cachedPeople[index].toLowerCase(),
                        ),
                      )
                      .length,
                  onEdit: () => _editPerson(context, store.cachedPeople[index]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addPerson(BuildContext context) async {
    var enteredName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add person'),
        content: TextFormField(
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (value) => enteredName = value,
          onFieldSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, enteredName),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    if (!store.addPerson(name) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That person is already saved.')),
      );
    }
  }

  Future<void> _editPerson(BuildContext context, String currentName) async {
    var editedName = currentName;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit person'),
        content: TextFormField(
          initialValue: currentName,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (value) => editedName = value,
          onFieldSubmitted: (_) => Navigator.pop(context, 'save'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'remove'),
            child: Text(
              'Remove',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (action == 'save') {
      if (editedName.trim().isEmpty) return;
      store.renamePerson(currentName, editedName);
    } else if (action == 'remove' && context.mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Remove $currentName?'),
          content: const Text(
            'The name will also be removed from every activity.',
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
      if (confirmed == true) store.removePerson(currentName);
    }
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.name,
    required this.activityCount,
    required this.onEdit,
  });

  final String name;
  final int activityCount;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surface,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: AppColors.primaryContainer,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: const TextStyle(
              color: AppColors.primaryDark,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(context).textTheme.titleMedium),
              Text(
                activityCount == 0
                    ? 'No activities yet'
                    : 'In $activityCount '
                          '${activityCount == 1 ? 'activity' : 'activities'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Edit person',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 20),
        ),
      ],
    ),
  );
}
