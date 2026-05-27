import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_material_design_icons/flutter_material_design_icons.dart';
import 'package:widget_zoom/widget_zoom.dart';

import '../models/group_post.dart';

class PostCard extends StatelessWidget {
  final GroupPost post;
  final bool canDelete;
  final VoidCallback? onDelete;
  final VoidCallback? onTapAirport;
  final VoidCallback? onLoadRoute;

  const PostCard({
    super.key,
    required this.post,
    this.canDelete = false,
    this.onDelete,
    this.onTapAirport,
    this.onLoadRoute,
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
            if (post.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 8),
                child: Text(
                  post.text,
                  style: const TextStyle(fontSize: 14, height: 1.35),
                ),
              ),
            ],
            if (post.hasMedia) ...[
              const SizedBox(height: 10),
              _MediaGrid(urls: post.mediaUrls),
            ],
            if (post.hasRoute) ...[
              const SizedBox(height: 10),
              _RouteChip(
                routeText: post.attachedRouteText!,
                routeName: post.attachedRouteName,
                onLoad: onLoadRoute,
              ),
            ],
            if (post.attachedAirport != null && post.attachedAirport!.isNotEmpty) ...[
              const SizedBox(height: 8),
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

class _MediaGrid extends StatelessWidget {
  final List<String> urls;
  const _MediaGrid({required this.urls});

  @override
  Widget build(BuildContext context) {
    if (urls.length == 1) {
      return _thumb(urls.first, double.infinity, 220, BoxFit.cover);
    }
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) =>
            _thumb(urls[i], 140, 140, BoxFit.cover),
      ),
    );
  }

  Widget _thumb(String url, double w, double h, BoxFit fit) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: WidgetZoom(
        heroAnimationTag: url,
        zoomWidget: CachedNetworkImage(
          imageUrl: url,
          width: w,
          height: h,
          fit: fit,
          placeholder: (_, __) => Container(
            width: w == double.infinity ? null : w,
            height: h,
            color: Colors.black12,
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            width: w == double.infinity ? null : w,
            height: h,
            color: Colors.black26,
            child: const Icon(Icons.broken_image, color: Colors.white70),
          ),
        ),
      ),
    );
  }
}

class _RouteChip extends StatelessWidget {
  final String routeText;
  final String? routeName;
  final VoidCallback? onLoad;
  const _RouteChip({
    required this.routeText,
    this.routeName,
    this.onLoad,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 4, right: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route, size: 16, color: scheme.onSecondaryContainer),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  routeName?.isNotEmpty == true ? routeName! : "Shared flight plan",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
              if (onLoad != null)
                FilledButton.tonalIcon(
                  onPressed: onLoad,
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text("Load"),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            routeText,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: scheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
