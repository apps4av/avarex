import 'package:flutter/material.dart';
import 'package:flutter_material_design_icons/flutter_material_design_icons.dart';

import '../models/group_post.dart';

class PostCard extends StatelessWidget {
  final GroupPost post;
  final bool canDelete;
  final VoidCallback? onDelete;
  final VoidCallback? onTapAirport;

  const PostCard({
    super.key,
    required this.post,
    this.canDelete = false,
    this.onDelete,
    this.onTapAirport,
  });

  String _relativeTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return "just now";
    if (d.inHours < 1) return "${d.inMinutes}m ago";
    if (d.inDays < 1) return "${d.inHours}h ago";
    if (d.inDays < 7) return "${d.inDays}d ago";
    final w = d.inDays ~/ 7;
    if (w < 5) return "${w}w ago";
    final mo = d.inDays ~/ 30;
    if (mo < 12) return "${mo}mo ago";
    return "${d.inDays ~/ 365}y ago";
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = post.authorName.isNotEmpty
        ? post.authorName.trim().substring(0, 1).toUpperCase()
        : "?";

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    initials,
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.authorName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        _relativeTime(post.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canDelete)
                  IconButton(
                    onPressed: onDelete,
                    icon: Icon(Icons.delete_outline,
                        size: 18, color: scheme.error),
                    tooltip: "Delete post",
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: Text(
                post.text,
                style: const TextStyle(fontSize: 14, height: 1.35),
              ),
            ),
            if (post.attachedAirport != null && post.attachedAirport!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: ActionChip(
                  avatar: Icon(MdiIcons.airport, size: 16),
                  label: Text(post.attachedAirport!),
                  onPressed: onTapAirport,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
