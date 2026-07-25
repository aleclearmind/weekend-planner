import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'planner_store.dart';
import 'screens/activities_page.dart';
import 'screens/activity_form_page.dart';
import 'screens/inbox_page.dart';
import 'screens/people_page.dart';
import 'screens/settings_page.dart';
import 'screens/weekends_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await PlannerStore.load();
  runApp(WeekendPlannerApp(store: store));
}

class WeekendPlannerApp extends StatelessWidget {
  const WeekendPlannerApp({required this.store, super.key});

  final PlannerStore store;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Weekend Planner',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: _ResponsiveFrame(child: HomeShell(store: store)),
  );
}

class _ResponsiveFrame extends StatelessWidget {
  const _ResponsiveFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.outer,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final framed = constraints.maxWidth > 760;
        if (!framed) return child;
        final height = math.min(constraints.maxHeight - 32, 960.0);
        return Center(
          child: Container(
            width: 680,
            height: height,
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(30),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x330B0F0C),
                  blurRadius: 42,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        );
      },
    ),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({required this.store, super.key});

  final PlannerStore store;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tabIndex = 0;

  static const _titles = ['Planner', 'Activities', 'People', 'Feed inbox'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.startPeriodicFeedRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.stopPeriodicFeedRefresh();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    widget.store.refreshFeedsIfDue();
    widget.store.refreshCalendarForWeeks();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        toolbarHeight: 66,
        title: Text(
          _titles[_tabIndex],
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          WeekendsPage(store: widget.store),
          ActivitiesPage(store: widget.store, onCreate: _createActivity),
          PeoplePage(store: widget.store),
          InboxPage(store: widget.store),
        ],
      ),
      floatingActionButton: _tabIndex == 1
          ? FloatingActionButton.extended(
              onPressed: _createActivity,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New activity'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (value) => setState(() => _tabIndex = value),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Planner',
          ),
          const NavigationDestination(
            icon: Icon(Icons.lightbulb_outline_rounded),
            selectedIcon: Icon(Icons.lightbulb_rounded),
            label: 'Activities',
          ),
          const NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group_rounded),
            label: 'People',
          ),
          NavigationDestination(
            icon: _InboxIcon(
              count: widget.store.inbox.where((item) => !item.imported).length,
            ),
            selectedIcon: _InboxIcon(
              count: widget.store.inbox.where((item) => !item.imported).length,
              selected: true,
            ),
            label: 'Inbox',
          ),
        ],
      ),
    ),
  );

  Future<void> _createActivity() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => ActivityFormPage(store: widget.store)),
    );
    if (result == null || !mounted) return;
    setState(() => _tabIndex = 1);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Activity saved.')));
  }

  Future<void> _openSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => SettingsPage(store: widget.store)),
    );
  }
}

class _InboxIcon extends StatelessWidget {
  const _InboxIcon({required this.count, this.selected = false});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) => Badge(
    isLabelVisible: count > 0,
    label: Text(count > 99 ? '99+' : '$count'),
    child: Icon(selected ? Icons.inbox_rounded : Icons.inbox_outlined),
  );
}
