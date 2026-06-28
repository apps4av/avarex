import 'package:flutter/material.dart';
import 'package:flutter_material_design_icons/flutter_material_design_icons.dart';

import '../constants.dart';
import '../utils/toast.dart';
import 'data/community_repository.dart';
import 'group_create_screen.dart';
import 'group_detail_screen.dart';
import 'models/pilot_group.dart';
import 'models/pilot_profile.dart';
import 'notifications_screen.dart';
import 'profile_edit_screen.dart';
import 'widgets/group_card.dart';

/// Main Community landing screen: My Groups / Discover / Profile tabs.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final _repo = CommunityRepository.instance;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  // Lazily create the user's profile doc. Errors (e.g. Firestore rules not
  // deployed yet, no network) are caught here so they don't become unhandled
  // exceptions; the inline banner below tells the user what's wrong.
  Future<void> _bootstrap() async {
    try {
      await _repo.ensureMyProfile();
      if (mounted && _initError != null) setState(() => _initError = null);
    } catch (e) {
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Constants.appBarBackgroundColor,
          title: Row(
            children: [
              Icon(MdiIcons.accountGroup, size: 24),
              const SizedBox(width: 8),
              const Text("Pilot Community"),
            ],
          ),
          actions: [
            const CommunityNotificationsBell(),
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: "Disclaimer",
              onPressed: () => showCommunityDisclaimer(context),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.groups), text: "My Groups"),
              Tab(icon: Icon(Icons.explore), text: "Discover"),
              Tab(icon: Icon(Icons.person), text: "Profile"),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GroupCreateScreen()),
            );
          },
          icon: const Icon(Icons.add),
          label: const Text("New Group"),
        ),
        body: Column(
          children: [
            if (_initError != null) _SetupBanner(message: _initError!),
            const _DisclaimerStrip(),
            const Expanded(
              child: TabBarView(
                children: [
                  _MyGroupsTab(),
                  _DiscoverTab(),
                  _ProfileTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Friendly explainer shown when Firestore returns permission-denied or the
/// backend hasn't been provisioned yet. Tells the user (and the developer)
/// what's missing instead of crashing the screen.
class _SetupBanner extends StatelessWidget {
  final String message;
  const _SetupBanner({required this.message});

  bool get _isPermissionDenied =>
      message.toLowerCase().contains("permission-denied") ||
      message.toLowerCase().contains("permission denied");

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer.withAlpha(120),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isPermissionDenied
                      ? "Community backend not ready"
                      : "Couldn't reach the community backend",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: scheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isPermissionDenied
                      ? "Firestore rules haven't been deployed for this project yet. "
                          "From the repo root run: firebase deploy --only firestore"
                      : message,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact always-visible bar that reminds pilots the Community is
/// unmoderated and not a place for sensitive data. Tap to open the full
/// disclaimer dialog.
class _DisclaimerStrip extends StatelessWidget {
  const _DisclaimerStrip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => showCommunityDisclaimer(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: scheme.tertiaryContainer.withAlpha(120),
        child: Row(
          children: [
            Icon(Icons.info_outline,
                size: 16, color: scheme.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Community is unmoderated. Don't share sensitive info. "
                "Tap for full disclaimer.",
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ),
            Icon(Icons.chevron_right,
                size: 16, color: scheme.onTertiaryContainer),
          ],
        ),
      ),
    );
  }
}

/// Shows the full Community disclaimer. Called from the AppBar info icon
/// and from the always-visible disclaimer strip on the main Community
/// screen. Kept top-level so future Community screens (Group detail,
/// post compose, etc.) can surface the same text without duplication.
Future<void> showCommunityDisclaimer(BuildContext context) {
  return showDialog(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      Widget bullet(IconData icon, String title, String body) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(body,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        );
      }

      return AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline),
            SizedBox(width: 8),
            Text("Community Disclaimer"),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bullet(
                Icons.warning_amber_outlined,
                "Not responsible for data loss",
                "Apps4Av is not responsible for any data loss in the "
                "Pilot Community. Treat posts and group content as "
                "ephemeral and keep your own copies of anything you "
                "want to keep.",
              ),
              bullet(
                Icons.lock_outline,
                "Don't share sensitive information",
                "Do not post passwords, government IDs, financial "
                "details, medical records, or any other sensitive "
                "personal information. Anything you post may be visible "
                "to other pilots.",
              ),
              bullet(
                Icons.gavel_outlined,
                "No moderation by Apps4Av",
                "Apps4Av does not moderate Pilot Community activity. "
                "Group owners are responsible for their own groups. "
                "Use your own judgment when interacting with other "
                "pilots and content.",
              ),
              bullet(
                Icons.shield_outlined,
                "Data is not shared with third parties",
                "Apps4Av will not share your Pilot Community data with "
                "third parties. Data is stored in the project's Firebase "
                "backend solely to operate this feature.",
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close"),
          ),
        ],
      );
    },
  );
}

class _MyGroupsTab extends StatelessWidget {
  const _MyGroupsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PilotGroup>>(
      stream: CommunityRepository.instance.watchMyGroups(),
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
            icon: Icons.groups_2_outlined,
            title: "No groups yet",
            subtitle:
                "Tap Discover to find pilot communities, or New Group to create one.",
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: groups.length,
          itemBuilder: (context, i) {
            final g = groups[i];
            return GroupCard(
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
              hintText: "Search groups by name (public + private)",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<PilotGroup>>(
            stream: CommunityRepository.instance
                .discoverGroups(query: _query),
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
                      ? "No public groups yet"
                      : "No groups match \"$_query\"",
                  subtitle: _query.isEmpty
                      ? "Be the first — tap New Group to create one."
                      : "Try a different search, or create the first group on this topic.",
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: groups.length,
                itemBuilder: (context, i) => GroupCard(
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

class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<PilotProfile?>(
      stream: CommunityRepository.instance.watchMyProfile(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final profile = snap.data;
        if (profile == null) {
          return const Center(child: Text("Profile unavailable"));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: scheme.primaryContainer,
                      child: Text(
                        profile.displayName.isNotEmpty
                            ? profile.displayName.substring(0, 1).toUpperCase()
                            : "?",
                        style: TextStyle(
                          fontSize: 22,
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.displayName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (profile.homeAirport != null)
                            Text(
                              "Home: ${profile.homeAirport}",
                              style: TextStyle(color: scheme.outline),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProfileEditScreen(profile: profile),
                          ),
                        );
                      },
                      icon: const Icon(Icons.edit),
                      tooltip: "Edit profile",
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (profile.bio != null && profile.bio!.isNotEmpty) ...[
              _section(context, "About"),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(profile.bio!),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (profile.ratings.isNotEmpty) ...[
              _section(context, "Ratings"),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: profile.ratings
                    .map((r) => Chip(label: Text(r)))
                    .toList(),
              ),
              const SizedBox(height: 12),
            ],
            if (profile.aircraftTypes.isNotEmpty) ...[
              _section(context, "Aircraft I fly"),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: profile.aircraftTypes
                    .map((a) => Chip(
                          avatar: Icon(MdiIcons.airplane, size: 14),
                          label: Text(a),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 24),
            Center(
              child: Text(
                "Your profile is visible to other AvareX pilots in groups you join.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _section(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

void _openGroup(BuildContext context, String groupId) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => GroupDetailScreen(groupId: groupId),
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
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
    // Surface backend errors via the existing toast pattern as well.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        Toast.showToast(context, "Community error: $error",
            const Icon(Icons.error, color: Colors.red), 4);
      }
    });
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          "Something went wrong loading the community.\n$error",
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
