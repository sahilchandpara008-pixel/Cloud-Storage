import 'package:flutter/material.dart';

import '../models.dart';
import '../services/backend.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/expandable_caption.dart';
import '../widgets/gates.dart';
import '../widgets/report.dart';
import 'channel_screen.dart';

/// Content page in the style of a streaming app: big poster with a play
/// button, title and duration, separate "Play" (full content) and "Trailer"
/// buttons, description, who uploaded it, and more from the same uploader.
/// Who may play what is unchanged (see widgets/gates.dart).
class PostScreen extends StatefulWidget {
  final String postId;
  final Post? initial;
  const PostScreen({super.key, required this.postId, this.initial});

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  Post? post;
  String? error;
  List<Post>? more;
  int selected = 0;

  @override
  void initState() {
    super.initState();
    post = widget.initial;
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await Backend.post(widget.postId);
      if (!mounted) return;
      setState(() {
        post = p;
        error = p == null ? 'This post is no longer available.' : null;
        if (selected >= (p?.items.length ?? 0)) selected = 0;
      });
      if (p != null) _loadMore(p);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  Future<void> _loadMore(Post p) async {
    try {
      final list = await Backend.moreFromCreator(p);
      if (mounted) setState(() => more = list);
    } catch (_) {
      if (mounted) setState(() => more = const []);
    }
  }

  void _openChannel(Post p) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ChannelScreen(channelId: p.channelId)),
  );

  @override
  Widget build(BuildContext context) {
    final p = post;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: const _GlassBack(),
      ),
      body: p == null
          ? (error != null
                ? ErrorRetry(message: error!, onRetry: _load)
                : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(onRefresh: _load, child: _body(p)),
    );
  }

  Widget _body(Post p) {
    final item = p.items.isEmpty ? null : p.items[selected];
    final top = MediaQuery.paddingOf(context).top;
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        SizedBox(height: top),
        if (item == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No media in this post.'),
          )
        else
          _Hero(post: p, item: item),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.title,
                style: const TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 8),
              _MetaRow(post: p, item: item),
              if (item != null) ...[
                const SizedBox(height: 14),
                _Buttons(post: p, item: item),
              ],
              if (p.items.length > 1) ...[
                const SizedBox(height: 18),
                _PartsStrip(
                  post: p,
                  selected: selected,
                  onSelect: (i) => setState(() => selected = i),
                ),
              ],
              if (p.caption != null && p.caption!.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                ExpandableCaption(
                  text: p.caption!.trim(),
                  style: const TextStyle(fontSize: 14.5, height: 1.45),
                ),
              ],
              const SizedBox(height: 16),
              _Uploader(post: p, onTap: () => _openChannel(p)),
              const SizedBox(height: 6),
              Row(
                children: [
                  _ActionIcon(
                    icon: Icons.video_library_outlined,
                    label: 'Channel',
                    onTap: () => _openChannel(p),
                  ),
                  _ActionIcon(
                    icon: Icons.flag_outlined,
                    label: 'Report',
                    onTap: () => reportContent(
                      context,
                      postId: p.id,
                      title: 'this post',
                    ),
                  ),
                  if (item != null)
                    _ActionIcon(
                      icon: Icons.download_rounded,
                      label: 'Download',
                      onTap: () => downloadItem(context, p, item),
                    ),
                ],
              ),
            ],
          ),
        ),
        _MoreFromCreator(posts: more),
      ],
    );
  }
}

// ------------------------------------------------------------------ hero

class _Hero extends StatelessWidget {
  final Post post;
  final PostItem item;
  const _Hero({required this.post, required this.item});

  @override
  Widget build(BuildContext context) {
    final locked = item.isPremium && !canWatchFull(post, item);
    final trailerOnly = canWatchTrailer(post, item);
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: GestureDetector(
        onTap: () => openItem(context, post, item),
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetThumb(
              url: item.thumbUrl,
              fallback: item.isVideo
                  ? Icons.movie_outlined
                  : Icons.image_outlined,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(gradient: AppColors.scrim),
            ),
            // Fade into the page below.
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 70,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x000A0A0C), AppColors.background],
                  ),
                ),
              ),
            ),
            if (item.isVideo)
              Center(
                child: locked && !trailerOnly
                    ? const _LockCircle()
                    : const _BigPlay(),
              ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Row(
                children: [
                  if (item.hasTrailer && item.isVideo)
                    const _Tag(text: 'Trailer', icon: Icons.play_arrow_rounded),
                  if (item.hasTrailer && item.isPremium)
                    const SizedBox(width: 6),
                  if (item.isPremium) const PremiumBadge(compact: true),
                ],
              ),
            ),
            if (item.durationS != null)
              Positioned(
                right: 12,
                bottom: 12,
                child: ThumbPill(formatDuration(item.durationS!)),
              ),
          ],
        ),
      ),
    );
  }
}

class _BigPlay extends StatelessWidget {
  const _BigPlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 66,
      height: 66,
      decoration: const BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x73FF7A1A),
            blurRadius: 30,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        color: AppColors.ink,
        size: 40,
      ),
    );
  }
}

class _LockCircle extends StatelessWidget {
  const _LockCircle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0x99FFB547), width: 1.5),
      ),
      child: const Icon(Icons.lock_rounded, color: AppColors.gold, size: 28),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final IconData? icon;
  const _Tag({required this.text, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
      decoration: BoxDecoration(
        color: const Color(0xD9000000),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 2),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ info

/// "Premium  2h 19m  HD". View counts are not shown in the app.
class _MetaRow extends StatelessWidget {
  final Post post;
  final PostItem? item;
  const _MetaRow({required this.post, required this.item});

  static String _long(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
    if (m > 0) return '${m}m';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: AppColors.muted, fontSize: 13.5);
    final parts = <String>[
      if (item?.durationS != null) _long(item!.durationS!),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (item?.isPremium ?? false) const PremiumBadge(),
        if (parts.isNotEmpty) Text(parts.join('  ·  '), style: style),
        if (item?.isVideo ?? false)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.muted),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'HD',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

/// "Play" = full content (login → plan gates as before);
/// "Watch trailer" = the trailer, when this viewer may watch it.
class _Buttons extends StatelessWidget {
  final Post post;
  final PostItem item;
  const _Buttons({required this.post, required this.item});

  @override
  Widget build(BuildContext context) {
    final locked = item.isPremium && !canWatchFull(post, item);
    final trailer = showTrailerButton(post, item);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          icon: Icon(
            !item.isVideo
                ? Icons.image_outlined
                : locked
                ? Icons.lock_rounded
                : Icons.play_arrow_rounded,
            size: 26,
          ),
          label: Text(
            !item.isVideo
                ? 'View'
                : trailer
                ? 'Play full content'
                : 'Play',
          ),
          // Viewers with a plan start on the preview with a Skip button;
          // everyone else goes on as before (plans page if needed).
          onPressed: () => previewFirst(post, item) && canWatchFull(post, item)
              ? openItem(context, post, item)
              : watchItem(context, post, item),
        ),
        if (trailer) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.surface,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.border),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            icon: const Icon(Icons.movie_filter_outlined, size: 22),
            label: const Text('Watch trailer'),
            onPressed: () => watchTrailer(context, post, item),
          ),
        ],
      ],
    );
  }
}

/// Posts with several videos/images: pick which one the buttons play.
class _PartsStrip extends StatelessWidget {
  final Post post;
  final int selected;
  final ValueChanged<int> onSelect;
  const _PartsStrip({
    required this.post,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'In this post (${post.items.length})',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 78,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: post.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final it = post.items[i];
              final on = i == selected;
              return GestureDetector(
                onTap: () => onSelect(i),
                child: Container(
                  width: 124,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: on ? AppColors.primary : AppColors.border,
                      width: on ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NetThumb(
                        url: it.thumbUrl,
                        fallback: it.isVideo
                            ? Icons.movie_outlined
                            : Icons.image_outlined,
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(gradient: AppColors.scrim),
                      ),
                      Positioned(
                        left: 6,
                        bottom: 4,
                        child: Text(
                          'Part ${i + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (it.durationS != null)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: ThumbPill(formatDuration(it.durationS!)),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}


class _Uploader extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;
  const _Uploader({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ChannelAvatar(
              url: post.channelIcon,
              name: post.channelName,
              size: 40,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Uploaded by',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  Text(
                    post.channelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionIcon({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 22, 8),
        child: Column(
          children: [
            Icon(icon, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ more

class _MoreFromCreator extends StatelessWidget {
  final List<Post>? posts;
  const _MoreFromCreator({required this.posts});

  @override
  Widget build(BuildContext context) {
    final list = posts;
    if (list != null && list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'More Like This',
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 6),
              SizedBox(
                width: 40,
                height: 3,
                child: ColoredBox(color: AppColors.primary),
              ),
              SizedBox(height: 4),
              Text(
                'More from this creator',
                style: TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (list == null)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: list.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2 / 3,
            ),
            itemBuilder: (_, i) => _Poster(post: list[i]),
          ),
      ],
    );
  }
}

class _Poster extends StatelessWidget {
  final Post post;
  const _Poster({required this.post});

  @override
  Widget build(BuildContext context) {
    final cover = post.cover;
    return PressScale(
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PostScreen(postId: post.id, initial: post),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetThumb(
                url: cover?.thumbUrl,
                fallback: (cover?.isVideo ?? true)
                    ? Icons.movie_outlined
                    : Icons.image_outlined,
              ),
              const DecoratedBox(
                decoration: BoxDecoration(gradient: AppColors.scrim),
              ),
              if (post.hasPremium)
                const Positioned(
                  top: 6,
                  left: 6,
                  child: PremiumBadge(compact: true),
                ),
              if (cover?.hasTrailer ?? false)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: _Tag(text: 'Trailer'),
                ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: Text(
                  post.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ bar

class _GlassBack extends StatelessWidget {
  const _GlassBack();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: _GlassIcon(
        icon: Icons.arrow_back_rounded,
        tooltip: 'Back',
        onTap: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}

class _GlassIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _GlassIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: const Color(0x80000000),
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icon, color: Colors.white, size: 22),
          onPressed: onTap,
        ),
      ),
    );
  }
}
