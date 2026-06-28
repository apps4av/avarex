import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_material_design_icons/flutter_material_design_icons.dart';

import '../constants.dart';
import '../main_screen.dart';
import '../plan/plan_route.dart';
import '../storage.dart';
import '../utils/toast.dart';
import 'data/community_repository.dart';
import 'group_members_screen.dart';
import 'models/group_member.dart';
import 'models/group_post.dart';
import 'models/pilot_group.dart';
import 'post_compose_screen.dart';
import 'post_thread_screen.dart';
import 'widgets/join_leave_button.dart';
import 'widgets/post_card.dart';

class GroupDetailScreen extends StatelessWidget {
  final String groupId;
  const GroupDetailScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PilotGroup?>(
      stream: CommunityRepository.instance.watchGroup(groupId),
      builder: (context, gSnap) {
        final group = gSnap.data;
        return StreamBuilder<GroupMember?>(
          stream: CommunityRepository.instance.watchMyMembership(groupId),
          builder: (context, mSnap) {
            final membership = mSnap.data;
            if (gSnap.connectionState == ConnectionState.waiting ||
                mSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            if (group == null) {
              return Scaffold(
                appBar: AppBar(
                  backgroundColor: Constants.appBarBackgroundColor,
                  title: const Text("Group"),
                ),
                body: const Center(
                    child: Text("This group has been deleted.")),
              );
            }
            return _GroupDetailBody(group: group, membership: membership);
          },
        );
      },
    );
  }
}

class _GroupDetailBody extends StatelessWidget {
  final PilotGroup group;
  final GroupMember? membership;
  const _GroupDetailBody({required this.group, this.membership});

  bool get _isOwner => membership?.isOwner ?? false;
  bool get _canPost => membership?.isActive ?? false;

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete group?"),
        content: Text(
            "Delete '${group.name}'? This removes all posts and memberships and cannot be undone."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await CommunityRepository.instance.deleteGroup(group.id);
      if (!context.mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        Toast.showToast(context, "Delete failed: $e",
            const Icon(Icons.error, color: Colors.red), 4);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pendingBadge = _isOwner
        ? StreamBuilder<List<GroupMember>>(
            stream: CommunityRepository.instance
                .watchMembers(group.id, status: MemberStatus.pending),
            builder: (context, snap) {
              final count = snap.data?.length ?? 0;
              if (count == 0) return const SizedBox.shrink();
              return Positioned(
                top: 8,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: scheme.error,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "$count",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              );
            },
          )
        : const SizedBox.shrink();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Constants.appBarBackgroundColor,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  group.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (group.isPrivate)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.lock_outline,
                      size: 16, color: scheme.outline),
                ),
            ],
          ),
          actions: [
            if (_isOwner)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: "Delete group",
                onPressed: () => _confirmDelete(context),
              ),
          ],
          bottom: TabBar(
            tabs: [
              const Tab(icon: Icon(Icons.forum), text: "Feed"),
              Tab(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.people),
                    pendingBadge,
                  ],
                ),
                text: "Members",
              ),
              const Tab(icon: Icon(Icons.info_outline), text: "About"),
            ],
          ),
        ),
        floatingActionButton: _canPost
            ? FloatingActionButton.extended(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PostComposeScreen(
                        groupId: group.id,
                        groupName: group.name,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.edit),
                label: const Text("Post"),
              )
            : null,
        body: Column(
          children: [
            _MembershipBanner(group: group, membership: membership),
            Expanded(
              child: TabBarView(
                children: [
                  _FeedTab(group: group, isOwner: _isOwner, canPost: _canPost),
                  GroupMembersScreen(
                    groupId: group.id,
                    isOwner: _isOwner,
                    embedded: true,
                  ),
                  _AboutTab(group: group),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MembershipBanner extends StatelessWidget {
  final PilotGroup group;
  final GroupMember? membership;
  const _MembershipBanner({required this.group, this.membership});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: scheme.surfaceContainerHighest.withAlpha(120),
      child: Row(
        children: [
          Expanded(
            child: Text(
              membership == null
                  ? (group.isPrivate
                      ? "This is a private group. Request to join to see the feed."
                      : "You aren't a member yet.")
                  : (membership!.isPending
                      ? "Your request is waiting for owner approval."
                      : membership!.isOwner
                          ? "You own this group."
                          : "You're a member."),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          JoinLeaveButton(
            group: group,
            membership: membership,
            onMessage: (m) {
              if (context.mounted) {
                Toast.showToast(
                    context, m, const Icon(Icons.info), 3);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _FeedTab extends StatefulWidget {
  final PilotGroup group;
  final bool isOwner;
  final bool canPost;
  const _FeedTab({
    required this.group,
    required this.isOwner,
    required this.canPost,
  });

  @override
  State<_FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<_FeedTab> {
  PilotGroup get group => widget.group;
  bool get isOwner => widget.isOwner;
  bool get canPost => widget.canPost;

  // Topics created after this instant are shown bold (unread). Captured
  // once when the feed opens; the group is then marked read up to "now"
  // so these same topics count as read on the next visit.
  DateTime? _readBaseline;
  bool _baselineLoaded = false;

  @override
  void initState() {
    super.initState();
    _initReadState();
  }

  Future<void> _initReadState() async {
    final baseline =
        await CommunityRepository.instance.fetchGroupLastRead(group.id);
    if (mounted) {
      setState(() {
        _readBaseline = baseline;
        _baselineLoaded = true;
      });
    }
    // Mark the feed read up to now for the next visit. Best-effort.
    try {
      await CommunityRepository.instance.markGroupRead(group.id);
    } catch (_) {/* non-fatal */}
  }

  bool _isUnread(GroupPost p, String? myUid) {
    // Nothing is bold until we know the baseline, and a pilot's own posts
    // are never "unread" to themselves. A null baseline (first ever visit)
    // is treated as all-read to avoid a wall of bold text.
    if (!_baselineLoaded || _readBaseline == null) return false;
    if (myUid != null && myUid == p.authorUid) return false;
    return p.createdAt.isAfter(_readBaseline!);
  }

  @override
  Widget build(BuildContext context) {
    if (group.isPrivate && !canPost && !isOwner) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            "Posts in this private group are hidden until your membership is approved.",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return StreamBuilder<List<GroupPost>>(
      stream: CommunityRepository.instance.watchPosts(group.id),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text("Couldn't load feed: ${snap.error}"));
        }
        final posts = snap.data ?? const [];
        if (posts.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                "No posts yet. Be the first to say hi.",
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final myUid = FirebaseAuth.instance.currentUser?.uid;
        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 80),
          itemCount: posts.length,
          itemBuilder: (context, i) {
            final p = posts[i];
            final canDelete = isOwner || (myUid != null && myUid == p.authorUid);
            void openThread() {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PostThreadScreen(
                    groupId: group.id,
                    groupName: group.name,
                    topicId: p.id,
                    isOwner: isOwner,
                    canPost: canPost,
                  ),
                ),
              );
            }

            return PostCard(
              post: p,
              canDelete: canDelete,
              unread: _isUnread(p, myUid),
              onOpenThread: openThread,
              onReply: canPost
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PostComposeScreen(
                            groupId: group.id,
                            groupName: group.name,
                            replyToId: p.id,
                            replyToAuthorName: p.authorName,
                          ),
                        ),
                      );
                    }
                  : null,
              onDelete: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Delete post?"),
                    content: const Text("This cannot be undone."),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text("Cancel")),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                            foregroundColor: Colors.red),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text("Delete"),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  try {
                    await CommunityRepository.instance
                        .deletePost(group.id, p.id);
                  } catch (e) {
                    if (context.mounted) {
                      Toast.showToast(context, "Delete failed: $e",
                          const Icon(Icons.error, color: Colors.red), 4);
                    }
                  }
                }
              },
              onTapAirport: () {
                Toast.showToast(
                  context,
                  "Search for ${p.attachedAirport} in the Find tab",
                  Icon(MdiIcons.airport),
                  3,
                );
              },
              onLoadRoute: p.hasRoute
                  ? () => _confirmLoadRoute(context, p)
                  : null,
            );
          },
        );
      },
    );
  }

  Future<void> _confirmLoadRoute(BuildContext context, GroupPost p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Load shared plan?"),
        content: Text(
          "This will replace your current flight plan with:\n\n"
          "${p.attachedRouteText}\n\n"
          "Your current plan will be lost unless you've saved it.",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.download, size: 18),
            label: const Text("Load to PLAN"),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final name = (p.attachedRouteName?.isNotEmpty == true)
          ? p.attachedRouteName!
          : "Shared plan";
      final loaded = await PlanRoute.fromLine(name, p.attachedRouteText!);
      Storage().route.copyFrom(loaded);
      Storage().route.setCurrentWaypoint(0);
      if (!context.mounted) return;
      // Pop the group + community stack and switch to the PLAN tab.
      Navigator.popUntil(context, (r) => r.isFirst);
      MainScreenState.gotoPlan();
      Toast.showToast(
        context,
        "Loaded \"$name\" into PLAN",
        const Icon(Icons.check, color: Colors.green),
        3,
      );
    } catch (e) {
      if (context.mounted) {
        Toast.showToast(
          context,
          "Couldn't load plan: $e",
          const Icon(Icons.error, color: Colors.red),
          4,
        );
      }
    }
  }
}

class _AboutTab extends StatelessWidget {
  final PilotGroup group;
  const _AboutTab({required this.group});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  group.description.isEmpty
                      ? "No description provided."
                      : group.description,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                _kv(context, "Owner", group.ownerName),
                _kv(context, "Visibility",
                    group.isPrivate ? "Private" : "Public"),
                if (group.homeAirport != null)
                  _kv(context, "Home airport", group.homeAirport!),
                _kv(context, "Members", "${group.memberCount}"),
                _kv(context, "Posts", "${group.postCount}"),
                _kv(context, "Created",
                    group.createdAt.toLocal().toString().split(' ').first),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 12)),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
