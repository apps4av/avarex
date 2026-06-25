import 'package:flutter/material.dart';
import 'package:flutter_material_design_icons/flutter_material_design_icons.dart';

import '../constants.dart';
import '../utils/toast.dart';
import 'data/scheduler_repository.dart';
import 'models/scheduler_group.dart';
import 'scheduler_create_screen.dart';
import 'scheduler_detail_screen.dart';
import 'widgets/scheduler_card.dart';

/// Main Aircraft Scheduler landing screen: My Schedulers / Discover tabs.
class SchedulerScreen extends StatelessWidget {
  const SchedulerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Constants.appBarBackgroundColor,
          title: Row(
            children: [
              Icon(MdiIcons.calendarClock, size: 24),
              const SizedBox(width: 8),
              const Text("Aircraft Scheduler"),
            ],
          ),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.calendar_month), text: "My Schedulers"),
              Tab(icon: Icon(Icons.explore), text: "Discover"),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SchedulerCreateScreen()),
            );
          },
          icon: const Icon(Icons.add),
          label: const Text("New Scheduler"),
        ),
        body: const TabBarView(
          children: [
            _MySchedulersTab(),
            _DiscoverTab(),
          ],
        ),
      ),
    );
  }
}

class _MySchedulersTab extends StatelessWidget {
  const _MySchedulersTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SchedulerGroup>>(
      stream: SchedulerRepository.instance.watchMyGroups(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _ErrorView(error: snap.error);
        }
        final groups = snap.data ?? const [];
        if (groups.isEmpty) {
          return const _EmptyState(
            icon: Icons.calendar_today_outlined,
            title: "No schedulers yet",
            subtitle:
                "Tap Discover to find a flying club, or New Scheduler to create one and add aircraft.",
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: groups.length,
          itemBuilder: (context, i) {
            final g = groups[i];
            return SchedulerCard(
              group: g,
              onTap: () => _openGroup(context, g.id),
            );
          },
        );
      },
    );
  }
}

class _DiscoverTab extends StatefulWidget {
  const _DiscoverTab();
  @override
  State<_DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<_DiscoverTab> {
  final _searchCtrl = TextEditingController();
  String _query = "";

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = "");
                      },
                    ),
              hintText: "Search schedulers by name",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<SchedulerGroup>>(
            stream:
                SchedulerRepository.instance.discoverGroups(query: _query),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return _ErrorView(error: snap.error);
              }
              final groups = snap.data ?? const [];
              if (groups.isEmpty) {
                return _EmptyState(
                  icon: Icons.search_off,
                  title: _query.isEmpty
                      ? "Search for a scheduler"
                      : "No schedulers match \"$_query\"",
                  subtitle: _query.isEmpty
                      ? "Schedulers are private. Type a name to find one to join, or tap New Scheduler to create your own."
                      : "Try a different search, or tap New Scheduler to create your own.",
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: groups.length,
                itemBuilder: (context, i) => SchedulerCard(
                  group: groups[i],
                  onTap: () => _openGroup(context, groups[i].id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

void _openGroup(BuildContext context, String groupId) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => SchedulerDetailScreen(groupId: groupId),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object? error;
  const _ErrorView({required this.error});
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        Toast.showToast(context, "Scheduler error: $error",
            const Icon(Icons.error, color: Colors.red), 4);
      }
    });
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          "Something went wrong loading the scheduler.\n$error",
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
