import 'package:flutter/material.dart';

import '../models.dart';
import '../screens/post_screen.dart';
import '../theme.dart';
import 'common.dart';
import 'expandable_caption.dart';
import 'gates.dart';

/// Chat-style post card used on the channel page and in the Feed.
class PostBubble extends StatelessWidget {
  final Post post;
  final bool showChannel;
  final VoidCallback? onDelete;
  const PostBubble({
    super.key,
    required this.post,
    this.showChannel = false,
    this.onDelete,
  });

  void _openPost(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PostScreen(postId: post.id, initial: post),
    ),
  );

  void _menu(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Open post'),
            onTap: () {
              Navigator.pop(context);
              _openPost(context);
            },
          ),
          if (onDelete != null)
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: AppColors.danger,
              ),
              title: const Text('Delete post'),
              onTap: () {
                Navigator.pop(context);
                onDelete!();
              },
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cover = post.cover;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: channel + menu
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: ChannelAvatar(
                      url: post.channelIcon,
                      name: post.channelName,
                      size: 35,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          showChannel ? post.channelName : post.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'More',
                    icon: const Icon(Icons.more_vert, color: AppColors.muted),
                    onPressed: () => _menu(context),
                  ),
                ],
              ),
            ),
            if (cover != null)
              DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(color: AppColors.border),
                  ),
                ),
                child: GestureDetector(
                  onTap: () => post.items.length > 1
                      ? _openPost(context)
                      : openItem(context, post, cover),
                  child: ClipRRect(
                    borderRadius: BorderRadius.zero,
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          NetThumb(
                            url: cover.thumbUrl,
                            fallback: cover.isVideo
                                ? Icons.movie_outlined
                                : Icons.image_outlined,
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: AppColors.scrim,
                            ),
                          ),
                          if (cover.isVideo)
                            const Center(child: PlayOverlay(size: 56)),
                          if (cover.isPremium)
                            const Positioned(
                              top: 10,
                              left: 10,
                              child: PremiumBadge(),
                            ),
                          if (cover.isVideo &&
                              (cover.durationS ?? 0) > 0 &&
                              post.items.length <= 1)
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: ThumbPill(
                                formatDuration(cover.durationS!),
                              ),
                            ),
                          if (post.items.length > 1)
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: ThumbPill(
                                '+${post.items.length - 1} more',
                                icon: Icons.collections_outlined,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showChannel)
                    Text(
                      post.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  if (post.caption != null && post.caption!.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: showChannel ? 4 : 0),
                      child: ExpandableCaption(
                        text: post.caption!,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: AppColors.muted,
                          height: 1.45,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
