import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/backend.dart';
import '../widgets/common.dart';
import '../widgets/reload.dart';
import '../theme.dart';
import 'post_screen.dart';

/// Explore: every visible post from all channels, as a grid of media cards.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  static const tabs = [
    ('all', 'All'),
    ('latest', 'Latest'),
    ('popular', 'Popular'),
    ('most_watched', 'Most watched'),
  ];

  final _controller = TextEditingController();
  Timer? _debounce;
  bool searching = false;
  String query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _closeSearch() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      searching = false;
      query = '';
    });
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.barGradient),
            child: SizedBox.expand(),
          ),
          title: searching
              ? TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  onSubmitted: (v) {
                    _debounce?.cancel();
                    setState(() => query = v.trim());
                  },
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'Search videos, shows, channels',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                )
              : const Text('Explore'),
          actions: searching
              ? [
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close search',
                    onPressed: _closeSearch,
                  ),
                ]
              : [
            IconButton(
              icon: const Icon(Icons.search_rounded),
              tooltip: 'Search',
              onPressed: () => setState(() => searching = true),
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'About Explore',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Explore'),
                  content: const Text(
                    'Discover posts from all channels. Tap a post to watch it.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              ),
            ),
            const CrownButton(),
          ],
          bottom: searching
              ? null
              : PreferredSize(
            preferredSize: const Size.fromHeight(52),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.muted,
                indicatorSize: TabBarIndicatorSize.tab,
                splashBorderRadius: BorderRadius.circular(20),
                indicator: BoxDecoration(
                  gradient: AppColors.gradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                labelStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
                tabs: [
                  for (final t in tabs)
                    Tab(
                      height: 34,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(t.$2),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // The tabs stay mounted (just hidden) while searching, so closing the
        // search brings back exactly what was on screen.
        body: Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: searching,
              child: TabBarView(
                children: [for (final t in tabs) _ExploreGrid(tab: t.$1)],
              ),
            ),
            if (searching)
              query.isEmpty
                  ? const EmptyState(
                      message: 'Search videos, shows and channels.',
                      icon: Icons.search_rounded,
                    )
                  : _SearchResults(key: ValueKey(query), query: query),
          ],
        ),
      ),
    );
  }
}

class _ExploreGrid extends StatefulWidget {
  final String tab;
  const _ExploreGrid({required this.tab});

  @override
  State<_ExploreGrid> createState() => _ExploreGridState();
}

class _ExploreGridState extends State<_ExploreGrid>
    with ContentReload, AutomaticKeepAliveClientMixin {
  List<Post>? posts;
  String? error;
  bool loadingMore = false;
  bool done = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Future<void> reload() async {
    try {
      final list = await Backend.explore(widget.tab);
      if (!mounted) return;
      setState(() {
        posts = list;
        error = null;
        done = list.length < 30;
      });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  Future<void> _more() async {
    if (loadingMore || done || posts == null) return;
    loadingMore = true;
    try {
      final list = await Backend.explore(widget.tab, offset: posts!.length);
      if (mounted) {
        setState(() {
          posts = [...posts!, ...list];
          done = list.length < 30;
        });
      }
    } finally {
      loadingMore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (error != null && posts == null) {
      return ErrorRetry(message: error!, onRetry: reload);
    }
    if (posts == null) return const LoadingSkeleton();
    if (posts!.isEmpty) {
      return RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            EmptyState(
              message: 'Nothing here yet.\nNew posts from channels will show up here.',
              icon: Icons.explore_outlined,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: reload,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 400) _more();
          return false;
        },
        child: LayoutBuilder(
          builder: (context, box) {
            // First post as a featured hero, the rest as 16:9 cards.
            final cols = (box.maxWidth / 230).floor().clamp(2, 5);
            final cardW = (box.maxWidth - 16 * 2 - 12 * (cols - 1)) / cols;
            final rest = posts!.skip(1).toList();
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: _Hero(post: posts!.first),
                  ),
                ),
                if (rest.isNotEmpty)
                  const SliverToBoxAdapter(
                    child: SectionTitle('Recommended for You'),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: cardW * 9 / 16 + 52,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _Tile(post: rest[i]),
                      childCount: rest.length,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Results for a search: same cards as the Explore grid. The database applies
/// the normal visibility rules, so a user only ever finds what they could open.
class _SearchResults extends StatefulWidget {
  final String query;
  const _SearchResults({super.key, required this.query});

  @override
  State<_SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<_SearchResults> {
  List<Post>? posts;
  String? error;
  bool loadingMore = false;
  bool done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await Backend.explore('all', search: widget.query);
      if (!mounted) return;
      setState(() {
        posts = list;
        error = null;
        done = list.length < 30;
      });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  Future<void> _more() async {
    if (loadingMore || done || posts == null) return;
    loadingMore = true;
    try {
      final list = await Backend.explore(
        'all',
        offset: posts!.length,
        search: widget.query,
      );
      if (mounted) {
        setState(() {
          posts = [...posts!, ...list];
          done = list.length < 30;
        });
      }
    } finally {
      loadingMore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null && posts == null) {
      return ErrorRetry(message: error!, onRetry: _load);
    }
    if (posts == null) return const LoadingSkeleton();
    if (posts!.isEmpty) {
      return EmptyState(
        message:
            'No videos found for "${widget.query}".\nTry another word, or look for a channel in the Channels tab.',
        icon: Icons.search_off_rounded,
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels > n.metrics.maxScrollExtent - 400) _more();
        return false;
      },
      child: LayoutBuilder(
        builder: (context, box) {
          final cols = (box.maxWidth / 230).floor().clamp(2, 5);
          final cardW = (box.maxWidth - 16 * 2 - 12 * (cols - 1)) / cols;
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: cardW * 9 / 16 + 52,
            ),
            itemCount: posts!.length,
            itemBuilder: (context, i) => _Tile(post: posts![i]),
          );
        },
      ),
    );
  }
}

void _openPost(BuildContext context, Post post) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => PostScreen(postId: post.id, initial: post),
  ),
);

/// Big featured card (same tap as any other post).
class _Hero extends StatelessWidget {
  final Post post;
  const _Hero({required this.post});

  @override
  Widget build(BuildContext context) {
    final cover = post.cover;
    final duration = cover?.durationS;
    return Semantics(
      label: post.title,
      button: true,
      child: PressScale(
        child: GestureDetector(
          onTap: () => _openPost(context, post),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40FF6A00),
                    blurRadius: 30,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetThumb(
                      url: cover?.thumbUrl,
                      fallback: cover?.isVideo == true
                          ? Icons.movie_outlined
                          : Icons.image_outlined,
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0xE6000000)],
                          stops: [0.35, 1],
                        ),
                      ),
                    ),
                    if (post.hasPremium)
                      const Positioned(
                        top: 12,
                        right: 12,
                        child: PremiumBadge(),
                      ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 14,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  post.channelName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xCCFFFFFF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  post.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (cover?.isVideo == true)
                            Container(
                              width: 46,
                              height: 46,
                              decoration: const BoxDecoration(
                                gradient: AppColors.gradient,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (duration != null && duration > 0)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: ThumbPill(formatDuration(duration)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final Post post;
  const _Tile({required this.post});

  @override
  Widget build(BuildContext context) {
    final cover = post.cover;
    final duration = cover?.durationS;
    return Semantics(
      label: post.title,
      button: true,
      child: PressScale(
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: () => _openPost(context, post),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.card),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x80000000),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.card),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NetThumb(
                          url: cover?.thumbUrl,
                          fallback: cover?.isVideo == true
                              ? Icons.movie_outlined
                              : Icons.image_outlined,
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(gradient: AppColors.scrim),
                        ),
                        if (cover?.isVideo == true)
                          const Center(child: PlayOverlay(size: 34)),
                        if (post.hasPremium)
                          const Positioned(
                            top: 7,
                            right: 7,
                            child: PremiumBadge(compact: true),
                          ),
                        Positioned(
                          bottom: 6,
                          right: 6,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (post.items.length > 1)
                                ThumbPill(
                                  '${post.items.length}',
                                  icon: Icons.collections_outlined,
                                ),
                              if (post.items.length > 1 &&
                                  duration != null &&
                                  duration > 0)
                                const SizedBox(width: 4),
                              if (duration != null && duration > 0)
                                ThumbPill(formatDuration(duration)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
                child: Text(
                  post.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
                child: Text(
                  '${post.channelName} · ${timeAgo(post.publishedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.muted,
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
