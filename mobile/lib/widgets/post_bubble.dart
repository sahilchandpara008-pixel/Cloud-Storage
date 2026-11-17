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
    final time = TimeOfDay.fromDateTime(post.publishedAt).format(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
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
            // Header: channel + time + menu
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(
                children: [
                  ChannelAvatar(
                    url: post.channelIcon,
                    name: post.channelName,
                    size: 36,
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
                        Text(
                          '${timeAgo(post.publishedAt)} · $time',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 11.5,
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: GestureDetector(
                  onTap: () => post.items.length > 1
                      ? _openPost(context)
                      : openItem(context, post, cover),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
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
                            const Center(child: PlayOverlay(size: 54)),
                          if (cover.isPremium)
                            const Positioned(
                              top: 10,
                              right: 10,
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
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showChannel)
                    Text(
                      post.title,
                      style: const TextStyle(
                        fontSize: 15,
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

/// "01 Oct 2025" separator between days.
class DateChip extends StatelessWidget {
  final DateTime date;
  const DateChip({super.key, required this.date});

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final label =
        '${date.day.toString().padLeft(2, '0')} ${_months[date.month - 1]} ${date.year}';
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
