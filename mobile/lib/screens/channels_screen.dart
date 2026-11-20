import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/backend.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/gates.dart';
import '../widgets/reload.dart';
import 'channel_screen.dart';
import 'create_channel_screen.dart';

/// Channels: search, Discover / Joined, Trending · Latest · Top Rated, Join.
class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> with ContentReload {
  String sort = 'trending';
  String search = '';
  Timer? _debounce;
  List<Channel>? discover;
  List<Channel>? joined;
  Set<String> joinedIds = {};
  String? error;

  @override
  Future<void> reload() async {
    try {
      final results = await Future.wait([
        Backend.channels(sort: sort, search: search),
        Backend.joinedChannels(),
      ]);
      if (!mounted) return;
      setState(() {
        discover = results[0];
        joined = results[1];
        joinedIds = joined!.map((c) => c.id).toSet();
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _join(Channel c) async {
    if (!await ensureLoggedIn(context, reason: 'Log in to join channels')) {
      return;
    }
    try {
      await Backend.join(c.id);
      await reload();
      if (mounted) showSnack(context, 'Joined ${c.name}');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.barGradient),
            child: SizedBox.expand(),
          ),
          title: const Text('Channels'),
          actions: const [CrownButton()],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(118),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search channels by name or topic',
                      prefixIcon: Icon(Icons.search_rounded),
                      fillColor: AppColors.surface,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                    ),
                    onChanged: (v) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 400), () {
                        search = v;
                        reload();
                      });
                    },
                  ),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TabBar(
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: AppColors.background,
                    unselectedLabelColor: AppColors.muted,
                    splashBorderRadius: BorderRadius.circular(10),
                    indicator: BoxDecoration(
                      color: AppColors.text,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    labelStyle: const TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    tabs: const [
                      Tab(height: 38, text: 'Discover'),
                      Tab(height: 38, text: 'Joined'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.ink,
          icon: const Icon(Icons.add),
          label: const Text('Create'),
          onPressed: () async {
            if (!await ensureLoggedIn(
              context,
              reason: 'Log in to create a channel',
            )) {
              return;
            }
            if (!context.mounted) return;
            if (!await ensurePremiumForChannel(context)) return;
            if (!context.mounted) return;
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CreateChannelScreen()),
            );
          },
        ),
        body: error != null && discover == null
            ? ErrorRetry(message: error!, onRetry: reload)
            : TabBarView(
                children: [
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                        child: Row(
                          children: [
                            for (final s in const [
                              ('trending', 'Trending'),
                              ('latest', 'Latest'),
                              ('top', 'Top Rated'),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(s.$2),
                                  selected: sort == s.$1,
                                  selectedColor: AppColors.primary,
                                  labelStyle: TextStyle(
                                    color: sort == s.$1
                                        ? AppColors.ink
                                        : const Color(0xFFD4D4D8),
                                    fontWeight: sort == s.$1
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                  side: BorderSide(
                                    color: sort == s.$1
                                        ? AppColors.primary
                                        : AppColors.border,
                                  ),
                                  showCheckmark: false,
                                  onSelected: (_) {
                                    setState(() => sort = s.$1);
                                    reload();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _list(
                          discover,
                          search.trim().isEmpty
                              ? 'No channels found.'
                              : 'No channels match "${search.trim()}".\nLooking for a video? Search in the Explore tab.',
                        ),
                      ),
                    ],
                  ),
                  _list(joined, 'You haven\'t joined any channels yet.'),
                ],
              ),
      ),
    );
  }

  Widget _list(List<Channel>? channels, String empty) {
    if (channels == null) {
      return const LoadingSkeleton(tiles: true);
    }
    if (channels.isEmpty) {
      return RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            EmptyState(message: empty, icon: Icons.live_tv_outlined),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
        itemCount: channels.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final c = channels[i];
          final isJoined = joinedIds.contains(c.id);
          return Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.borderSoft),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChannelScreen(channelId: c.id),
                  ),
                );
                reload();
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    ChannelAvatar(url: c.iconUrl, name: c.name, size: 52),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${formatCount(c.membersCount)} followers',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    isJoined
                        ? OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(80, 38),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              disabledForegroundColor: const Color(0xFFD4D4D8),
                              side: const BorderSide(color: Color(0xFF3A3A44)),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: null,
                            child: const Text('Joined'),
                          )
                        : FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(72, 38),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: () => _join(c),
                            child: const Text('Join'),
                          ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
