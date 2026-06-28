import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_material_design_icons/flutter_material_design_icons.dart';

import '../constants.dart';
import '../main_screen.dart';
import '../plan/plan_route.dart';
import '../storage.dart';
import '../utils/toast.dart';
import 'data/community_repository.dart';
import 'models/group_post.dart';
import 'post_compose_screen.dart';
import 'widgets/post_card.dart';

/// A single threaded discussion: one topic (top-level post) followed by
/// its replies, oldest first, with a composer to add a reply. Opened from
/// the group feed when a topic is tapped or replied to.
class PostThreadScreen extends StatelessWidget {
  final String groupId;
  final String groupName;
  final String topicId;
  final bool isOwner;
  final bool canPost;

  const PostThreadScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.topicId,
    required this.isOwner,
    required this.canPost,
  });

  Future<void> _reply(BuildContext context, GroupPost topic) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostComposeScreen(
          groupId: groupId,
          groupName: groupName,
          replyToId: topic.id,
          replyToAuthorName: topic.authorName,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, GroupPost post, bool isTopic) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isTopic ? "Delete topic?" : "Delete reply?"),
        content: Text(isTopic
            ? "This deletes the topic and all of its replies. This cannot be undone."
            : "This cannot be undone."),
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
      await CommunityRepository.instance.deletePost(groupId, post.id);
      // Removing the topic closes the thread; a removed reply just
      // disappears from the live list below.
      if (isTopic && context.mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        Toast.showToast(context, "Delete failed: $e",
            const Icon(Icons.error, color: Colors.red), 4);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text("Discussion"),
      ),
      floatingActionButton: canPost
          ? StreamBuilder<GroupPost?>(
              stream:
                  CommunityRepository.instance.watchPost(groupId, topicId),
              builder: (context, snap) {
                final topic = snap.data;
                if (topic == null) return const SizedBox.shrink();
                return FloatingActionButton.extended(
                  onPressed: () => _reply(context, topic),
                  icon: const Icon(Icons.reply),
                  label: const Text("Reply"),
                );
              },
            )
          : null,
      body: StreamBuilder<GroupPost?>(
        stream: CommunityRepository.instance.watchPost(groupId, topicId),
        builder: (context, topicSnap) {
          if (topicSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final topic = topicSnap.data;
          if (topic == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "This topic has been deleted.",
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final canDeleteTopic =
              isOwner || (myUid != null && myUid == topic.authorUid);
          return StreamBuilder<List<GroupPost>>(
            stream:
                CommunityRepository.instance.watchReplies(groupId, topic.id),
            builder: (context, repliesSnap) {
              final replies = repliesSnap.data ?? const <GroupPost>[];
              final repliesError = repliesSnap.error;
              return ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 88),
                children: [
                  PostCard(
                    post: topic,
                    canDelete: canDeleteTopic,
                    onDelete: () => _confirmDelete(context, topic, true),
                    onTapAirport: () {
                      Toast.showToast(
                        context,
                        "Search for ${topic.attachedAirport} in the Find tab",
                        Icon(MdiIcons.airport),
                        3,
                      );
                    },
                    onLoadRoute: topic.hasRoute
                        ? () => _confirmLoadRoute(context, topic)
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      replies.isEmpty
                          ? "No replies yet"
                          : replies.length == 1
                              ? "1 reply"
                              : "${replies.length} replies",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                  if (repliesSnap.connectionState == ConnectionState.waiting &&
                      replies.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (repliesError != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Text(
                        "Couldn't load replies: $repliesError",
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12),
                      ),
                    ),
                  for (final r in replies)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: PostCard(
                        post: r,
                        canDelete: isOwner ||
                            (myUid != null && myUid == r.authorUid),
                        onDelete: () => _confirmDelete(context, r, false),
                      ),
                    ),
                  if (canPost && replies.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text(
                        "Be the first to reply to this topic.",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
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
