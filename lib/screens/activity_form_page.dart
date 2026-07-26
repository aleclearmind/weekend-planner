import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../location_parser.dart';
import '../models.dart';
import '../planner_store.dart';
import '../widgets.dart';

class ActivityFormPage extends StatefulWidget {
  const ActivityFormPage({required this.store, this.activity, super.key});

  final PlannerStore store;
  final ActivityIdea? activity;

  @override
  State<ActivityFormPage> createState() => _ActivityFormPageState();
}

class _ActivityFormPageState extends State<ActivityFormPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _tagController;
  late final FocusNode _tagFocusNode;
  late final TextEditingController _personController;
  late final TextEditingController _locationNameController;
  late final TextEditingController _coordinatesController;
  late final TextEditingController _urlController;
  late final TextEditingController _firstDateController;
  late final TextEditingController _secondDateController;
  late DateRangeKind _rangeKind;
  late DateTime _firstDate;
  late DateTime _secondDate;
  late WeekDay? _startDay;
  late DayPart? _startPart;
  late int _slotLength;
  late bool _isRecurring;
  late bool _hasFrequency;
  late int _frequencyWeeks;
  late List<Participant> _people;
  late List<String> _tags;

  bool get _editing => widget.activity != null;

  @override
  void initState() {
    super.initState();
    final now = dateOnly(DateTime.now());
    final activity = widget.activity;
    _nameController = TextEditingController(text: activity?.name ?? '');
    _tagController = TextEditingController();
    _tagFocusNode = FocusNode();
    _personController = TextEditingController();
    _locationNameController = TextEditingController(
      text: activity?.location?.name ?? '',
    );
    _coordinatesController = TextEditingController(
      text:
          activity?.location?.coordinateInput ??
          activity?.location?.coordinateLabel ??
          '',
    );
    _urlController = TextEditingController(text: activity?.url ?? '');
    _rangeKind = activity?.rangeKind ?? DateRangeKind.anytime;
    _firstDate = activity?.firstDate ?? addDays(now, 90);
    _secondDate =
        activity?.secondDate ??
        (activity == null
            ? addDays(now, 180)
            : addDays(activity.firstDate, 30));
    _firstDateController = TextEditingController(text: isoDate(_firstDate));
    _secondDateController = TextEditingController(text: isoDate(_secondDate));
    _startDay = activity?.startDay;
    _startPart = activity?.startPart;
    _slotLength = activity?.slotLength ?? 1;
    _isRecurring = activity?.isRecurring ?? false;
    _hasFrequency = activity?.desiredFrequencyWeeks != null;
    _frequencyWeeks = activity?.desiredFrequencyWeeks ?? 4;
    _people = List<Participant>.from(activity?.people ?? const []);
    _tags = List<String>.from(activity?.tags ?? const []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tagController.dispose();
    _tagFocusNode.dispose();
    _personController.dispose();
    _locationNameController.dispose();
    _coordinatesController.dispose();
    _urlController.dispose();
    _firstDateController.dispose();
    _secondDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    const timeSegments = [
      ButtonSegment(value: 'any', label: Text('Any time')),
      ButtonSegment(value: 'morning', label: Text('Morning')),
      ButtonSegment(value: 'afternoon', label: Text('Afternoon')),
      ButtonSegment(value: 'night', label: Text('Night')),
    ];
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(_editing ? 'Edit activity' : 'New activity'),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'Delete activity',
              onPressed: _confirmDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          TextButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 6, 20, 32 + bottomInset),
        children: [
          const SectionLabel('Name'),
          TextField(
            controller: _nameController,
            autofocus: !_editing,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: 'Activity name'),
          ),
          const SizedBox(height: 22),
          const SectionLabel('Tags'),
          if (_tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (var index = 0; index < _tags.length; index++)
                    InputChip(
                      label: Text('#${_tags[index]}'),
                      onDeleted: () => setState(() => _tags.removeAt(index)),
                    ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: RawAutocomplete<String>(
                  textEditingController: _tagController,
                  focusNode: _tagFocusNode,
                  optionsBuilder: _tagAutocompleteOptions,
                  onSelected: _addTags,
                  fieldViewBuilder:
                      (context, controller, focusNode, onFieldSubmitted) =>
                          TextField(
                            controller: controller,
                            focusNode: focusNode,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (value) {
                              if (_tagAutocompleteOptions(
                                controller.value,
                              ).isEmpty) {
                                _addTags(value);
                              } else {
                                onFieldSubmitted();
                              }
                            },
                            decoration: const InputDecoration(
                              hintText: 'Outdoors, music…',
                              prefixIcon: Icon(Icons.tag_rounded),
                              helperText:
                                  'Autocomplete from existing tags; commas '
                                  'add several.',
                            ),
                          ),
                  optionsViewBuilder: (context, onSelected, options) => Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 5,
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(13),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 320,
                          maxHeight: 220,
                        ),
                        child: ListView(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          children: [
                            for (final option in options)
                              ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.tag_rounded,
                                  size: 18,
                                ),
                                title: Text(option),
                                onTap: () => onSelected(option),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              SizedBox(
                height: 54,
                child: FilledButton(
                  onPressed: () => _addTags(_tagController.text),
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const SectionLabel('Date range'),
          _RangeSelector(
            value: _rangeKind,
            onChanged: (value) => setState(() => _rangeKind = value),
          ),
          if (_rangeKind != DateRangeKind.anytime) ...[
            if (_rangeKind == DateRangeKind.within) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _withinPreset('1w', days: 7),
                  _withinPreset('1m', months: 1),
                  _withinPreset('2m', months: 2),
                  _withinPreset('3m', months: 3),
                  _withinPreset('1y', months: 12),
                  ActionChip(
                    label: Text(_nextSeason.label),
                    onPressed: () => _setFirstDate(_nextSeason.deadline),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _DateInput(
                    label: _rangeKind == DateRangeKind.between
                        ? 'From'
                        : 'Date',
                    controller: _firstDateController,
                    errorText: _dateError(_firstDateController.text),
                    onChanged: (_) => _dateTextChanged(first: true),
                    onCalendarPressed: () => _pickDate(first: true),
                  ),
                ),
                if (_rangeKind == DateRangeKind.between) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(8, 18, 8, 0),
                    child: Text('to', style: TextStyle(color: AppColors.muted)),
                  ),
                  Expanded(
                    child: _DateInput(
                      label: 'Until',
                      controller: _secondDateController,
                      errorText: _dateError(_secondDateController.text),
                      onChanged: (_) => _dateTextChanged(first: false),
                      onCalendarPressed: () => _pickDate(first: false),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(_rangePreview, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 24),
          const SectionLabel('Starts on'),
          Text('Day of week', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _startDay?.name ?? 'any',
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.today_rounded),
            ),
            items: [
              const DropdownMenuItem(value: 'any', child: Text('Any day')),
              for (final day in WeekDay.values)
                DropdownMenuItem(
                  value: day.name,
                  child: Text(weekDayLabel(day)),
                ),
            ],
            onChanged: (value) => setState(() {
              _startDay = value == 'any' ? null : WeekDay.values.byName(value!);
            }),
          ),
          const SizedBox(height: 12),
          Text('Time of day', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: timeSegments,
            selected: {_startPart?.name ?? 'any'},
            onSelectionChanged: (values) => setState(() {
              final value = values.single;
              _startPart = value == 'any' ? null : DayPart.values.byName(value);
            }),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lasts',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _slotPreview,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _RoundIconButton(
                icon: Icons.remove_rounded,
                tooltip: 'One slot less',
                onPressed: _slotLength > 1
                    ? () => setState(() => _slotLength--)
                    : null,
              ),
              SizedBox(
                width: 42,
                child: Text(
                  '$_slotLength',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _RoundIconButton(
                icon: Icons.add_rounded,
                tooltip: 'One slot more',
                onPressed: _slotLength < widget.store.enabledSlots.length
                    ? () => setState(() => _slotLength++)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SwitchSection(
            title: 'Recurring activity',
            subtitle: 'It remains reusable, but assignments are always manual.',
            value: _isRecurring,
            onChanged: (value) => setState(() {
              _isRecurring = value;
              if (!value) _hasFrequency = false;
            }),
          ),
          if (_isRecurring) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Desired frequency'),
              subtitle: const Text('Warn me when this activity is overdue.'),
              value: _hasFrequency,
              onChanged: (value) => setState(() => _hasFrequency = value),
            ),
            if (_hasFrequency)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Once every $_frequencyWeeks '
                      '${_frequencyWeeks == 1 ? 'weekend' : 'weekends'}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  _RoundIconButton(
                    icon: Icons.remove_rounded,
                    tooltip: 'Less often',
                    onPressed: _frequencyWeeks > 1
                        ? () => setState(() => _frequencyWeeks--)
                        : null,
                  ),
                  SizedBox(
                    width: 42,
                    child: Text(
                      '$_frequencyWeeks',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  _RoundIconButton(
                    icon: Icons.add_rounded,
                    tooltip: 'More weekends',
                    onPressed: _frequencyWeeks < 52
                        ? () => setState(() => _frequencyWeeks++)
                        : null,
                  ),
                ],
              ),
          ],
          const SizedBox(height: 25),
          const SectionLabel('Location'),
          TextField(
            controller: _locationNameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'Place name (optional)',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _coordinatesController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: '45.4642, 9.1900 · geo:… · OLC',
              prefixIcon: Icon(Icons.my_location_rounded),
              helperText:
                  'Latitude/longitude, a geo: URL, or a full plus code.',
            ),
          ),
          const SizedBox(height: 22),
          const SectionLabel('Related URL'),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'https://example.com/activity',
              prefixIcon: Icon(Icons.link_rounded),
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('People who might join'),
          if (_people.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (var index = 0; index < _people.length; index++)
                    InputChip(
                      avatar: StatusDot(_people[index].status),
                      label: Text(
                        '${_people[index].name} · '
                        '${interestLabel(_people[index].status).toLowerCase()}',
                      ),
                      tooltip: 'Tap to change their status',
                      onPressed: () => _cycleStatus(index),
                      onDeleted: () => setState(() => _people.removeAt(index)),
                    ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _personController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: _addPerson,
                  decoration: const InputDecoration(
                    hintText: 'Type a name',
                    prefixIcon: Icon(Icons.person_add_alt_1_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              SizedBox(
                height: 54,
                child: FilledButton(
                  onPressed: () => _addPerson(_personController.text),
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
          if (_suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 7),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  for (final suggestion in _suggestions)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.history_rounded, size: 19),
                      title: Text(suggestion),
                      onTap: () => _addPerson(suggestion),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String get _rangePreview => switch (_rangeKind) {
    DateRangeKind.anytime => 'Available at any date.',
    DateRangeKind.within =>
      _validFirstDate == null
          ? 'Enter the date as YYYY-MM-DD.'
          : 'Within ${isoDate(_validFirstDate!)}',
    DateRangeKind.exact =>
      _validFirstDate == null
          ? 'Enter the date as YYYY-MM-DD.'
          : 'Exact ${isoDate(_validFirstDate!)}',
    DateRangeKind.between =>
      _validFirstDate == null || _validSecondDate == null
          ? 'Enter both dates as YYYY-MM-DD.'
          : 'Between ${isoDate(_validFirstDate!)} and '
                '${isoDate(_validSecondDate!)}',
  };

  DateTime? get _validFirstDate => _tryDateText(_firstDateController.text);

  DateTime? get _validSecondDate => _tryDateText(_secondDateController.text);

  ({String label, DateTime deadline}) get _nextSeason =>
      _nextSeasonDeadline(dateOnly(DateTime.now()));

  String get _slotPreview {
    final start = activityStartLabel(_startDay, _startPart);
    return 'Starts $start, lasts $_slotLength '
        '${_slotLength == 1 ? 'slot' : 'slots'}';
  }

  List<String> get _suggestions {
    final query = _personController.text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return widget.store.cachedPeople
        .where(
          (name) =>
              name.toLowerCase().contains(query) &&
              !_people.any(
                (person) => person.name.toLowerCase() == name.toLowerCase(),
              ),
        )
        .take(4)
        .toList();
  }

  Iterable<String> _tagAutocompleteOptions(TextEditingValue value) {
    final query = value.text.trim().toLowerCase();
    final suggestions = <String>[];
    final seen = <String>{};
    for (final activity in widget.store.activities) {
      for (final tag in activity.tags) {
        final normalized = tag.toLowerCase();
        if ((query.isNotEmpty && !normalized.contains(query)) ||
            !seen.add(normalized) ||
            _tags.any((current) => current.toLowerCase() == normalized)) {
          continue;
        }
        suggestions.add(tag);
      }
    }
    suggestions.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return suggestions.take(8);
  }

  Future<void> _pickDate({required bool first}) async {
    final current = first
        ? _validFirstDate ?? _firstDate
        : _validSecondDate ?? _secondDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (first) {
        _firstDate = picked;
        _firstDateController.text = isoDate(picked);
        if ((_validSecondDate ?? _secondDate).isBefore(_firstDate)) {
          _secondDate = _firstDate;
          _secondDateController.text = isoDate(_secondDate);
        }
      } else {
        _secondDate = picked;
        _secondDateController.text = isoDate(picked);
      }
    });
  }

  Widget _withinPreset(String label, {int? days, int? months}) => ActionChip(
    label: Text(label),
    onPressed: () {
      final today = dateOnly(DateTime.now());
      _setFirstDate(
        days == null
            ? _addCalendarMonths(today, months!)
            : addDays(today, days),
      );
    },
  );

  void _setFirstDate(DateTime date) {
    setState(() {
      _firstDate = dateOnly(date);
      _firstDateController.text = isoDate(_firstDate);
    });
  }

  void _dateTextChanged({required bool first}) {
    final parsed = _tryDateText(
      first ? _firstDateController.text : _secondDateController.text,
    );
    setState(() {
      if (parsed == null) return;
      if (first) {
        _firstDate = parsed;
      } else {
        _secondDate = parsed;
      }
    });
  }

  void _addPerson(String value) {
    final name = value.trim();
    if (name.isEmpty) return;
    final exists = _people.any(
      (person) => person.name.toLowerCase() == name.toLowerCase(),
    );
    _personController.clear();
    if (exists) {
      setState(() {});
      return;
    }
    setState(() {
      _people.add(Participant(name: name, status: InterestStatus.possibly));
    });
  }

  void _addTags(String value) {
    final additions = value
        .split(',')
        .map((tag) => tag.trim().replaceFirst(RegExp(r'^#+'), '').trim())
        .where((tag) => tag.isNotEmpty);
    for (final tag in additions) {
      final exists = _tags.any(
        (current) => current.toLowerCase() == tag.toLowerCase(),
      );
      if (!exists) _tags.add(tag);
    }
    _tagController.clear();
    setState(() {});
  }

  void _cycleStatus(int index) {
    final current = _people[index];
    final next =
        InterestStatus.values[(InterestStatus.values.indexOf(current.status) +
                1) %
            InterestStatus.values.length];
    setState(() => _people[index] = current.copyWith(status: next));
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Give the activity a name.');
      return;
    }
    final firstDate = _rangeKind == DateRangeKind.anytime
        ? _firstDate
        : _validFirstDate;
    final secondDate = _rangeKind == DateRangeKind.between
        ? _validSecondDate
        : null;
    if (firstDate == null ||
        (secondDate == null && _rangeKind == DateRangeKind.between)) {
      _showMessage('Enter dates in the YYYY-MM-DD format.');
      return;
    }
    if (_rangeKind == DateRangeKind.between &&
        secondDate!.isBefore(firstDate)) {
      _showMessage('The end date needs to come after the start date.');
      return;
    }

    ActivityLocation? location;
    try {
      location = parseActivityLocation(
        _locationNameController.text,
        _coordinatesController.text,
      );
    } on LocationParseException catch (error) {
      _showMessage(error.message);
      return;
    }

    final urlText = _urlController.text.trim();
    final url = Uri.tryParse(urlText);
    if (urlText.isNotEmpty &&
        (url == null ||
            !url.hasScheme ||
            (url.scheme != 'http' && url.scheme != 'https'))) {
      _showMessage('Enter a complete http:// or https:// activity URL.');
      return;
    }

    widget.store.saveActivity(
      ActivityIdea(
        id:
            widget.activity?.id ??
            'activity-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        rangeKind: _rangeKind,
        firstDate: dateOnly(firstDate),
        secondDate: _rangeKind == DateRangeKind.between
            ? dateOnly(secondDate!)
            : null,
        startDay: _startDay,
        startPart: _startPart,
        slotLength: _slotLength,
        people: List.unmodifiable(_people),
        tags: List.unmodifiable(_tags),
        isRecurring: _isRecurring,
        desiredFrequencyWeeks: _isRecurring && _hasFrequency
            ? _frequencyWeeks
            : null,
        location: location,
        url: urlText.isEmpty ? null : urlText,
        createdAt: widget.activity?.createdAt ?? DateTime.now(),
        frequencyCounterResetAt: _isRecurring && _hasFrequency
            ? widget.activity?.frequencyCounterResetAt
            : null,
      ),
    );
    Navigator.pop(context, _editing ? 'updated' : 'created');
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this activity?'),
        content: const Text('It will also be removed from any planner slots.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.store.deleteActivity(widget.activity!.id);
    Navigator.pop(context, 'deleted');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SwitchSection extends StatelessWidget {
  const _SwitchSection({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border.symmetric(horizontal: BorderSide(color: AppColors.outer)),
    ),
    child: SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    ),
  );
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.value, required this.onChanged});

  final DateRangeKind value;
  final ValueChanged<DateRangeKind> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<DateRangeKind>(
    showSelectedIcon: false,
    segments: const [
      ButtonSegment(value: DateRangeKind.anytime, label: Text('Anytime')),
      ButtonSegment(value: DateRangeKind.within, label: Text('Within')),
      ButtonSegment(value: DateRangeKind.between, label: Text('Between')),
      ButtonSegment(value: DateRangeKind.exact, label: Text('Exact')),
    ],
    selected: {value},
    onSelectionChanged: (values) => onChanged(values.single),
  );
}

class _DateInput extends StatelessWidget {
  const _DateInput({
    required this.label,
    required this.controller,
    required this.errorText,
    required this.onChanged,
    required this.onCalendarPressed,
  });

  final String label;
  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String> onChanged;
  final VoidCallback onCalendarPressed;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.datetime,
    autocorrect: false,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      hintText: '2025-01-01',
      errorText: errorText,
      suffixIcon: IconButton(
        tooltip: 'Open calendar',
        onPressed: onCalendarPressed,
        icon: const Icon(Icons.calendar_today_rounded, size: 18),
      ),
    ),
  );
}

DateTime? _tryDateText(String value) {
  try {
    return parseIsoDate(value);
  } on FormatException {
    return null;
  }
}

String? _dateError(String value) =>
    _tryDateText(value) == null ? 'YYYY-MM-DD' : null;

DateTime _addCalendarMonths(DateTime date, int months) {
  final rawMonth = date.month - 1 + months;
  final year = date.year + rawMonth ~/ 12;
  final month = rawMonth % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, date.day.clamp(1, lastDay));
}

({String label, DateTime deadline}) _nextSeasonDeadline(DateTime today) {
  const starts = <(int, String)>[
    (3, 'spring'),
    (6, 'summer'),
    (9, 'autumn'),
    (12, 'winter'),
  ];
  final candidates = <({DateTime start, String name})>[
    for (var year = today.year; year <= today.year + 2; year++)
      for (final season in starts)
        (start: DateTime(year, season.$1), name: season.$2),
  ];
  final nextIndex = candidates.indexWhere(
    (candidate) => candidate.start.isAfter(today),
  );
  final next = candidates[nextIndex];
  final afterNext = candidates[nextIndex + 1];
  return (label: 'Next ${next.name}', deadline: addDays(afterNext.start, -1));
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton.outlined(
    onPressed: onPressed,
    tooltip: tooltip,
    icon: Icon(icon),
    style: IconButton.styleFrom(
      minimumSize: const Size.square(38),
      maximumSize: const Size.square(38),
      padding: EdgeInsets.zero,
    ),
  );
}
