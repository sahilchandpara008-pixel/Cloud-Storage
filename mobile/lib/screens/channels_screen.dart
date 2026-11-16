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
            preferredSize: const Size.fromHeight(100),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search',
                      prefixIcon: Icon(Icons.search_rounded),
                      fillColor: AppColors.surfaceHigh,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
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
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TabBar(
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.white,
                    unselectedLabelColor: AppColors.muted,
                    splashBorderRadius: BorderRadius.circular(10),
                    indicator: BoxDecoration(
                      gradient: AppColors.gradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    labelStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                    tabs: const [
                      Tab(height: 32, text: 'Discover'),
                      Tab(height: 32, text: 'Joined'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
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
                                        ? Colors.white
                                        : AppColors.text,
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
                      Expanded(child: _list(discover, 'No channels found.')),
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
      return const Center(child: CircularProgressIndicator());
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
        padding: const EdgeInsets.only(top: 4, bottom: 80),
        itemCount: channels.length,
        separatorBuilder: (_, _) => const SizedBox(height: 0),
        itemBuilder: (context, i) {
          final c = channels[i];
          final isJoined = joinedIds.contains(c.id);
          return ListTile(
            dense: true,
            minVerticalPadding: 6,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: ChannelAvatar(url: c.iconUrl, name: c.name, size: 42),
            title: Text(
              c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            subtitle: DefaultTextStyle.merge(
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
              child: Row(
                children: [
                  const Icon(
                    Icons.people_outline,
                    size: 14,
                    color: AppColors.muted,
                  ),
                  Text(' ${c.membersCount}   '),
                  const Icon(
                    Icons.folder_outlined,
                    size: 14,
                    color: AppColors.muted,
                  ),
                  Text(' ${c.foldersCount}'),
                ],
              ),
            ),
            trailing: isJoined
                ? OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(76, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: const StadiumBorder(),
                      disabledForegroundColor: AppColors.muted,
                      side: const BorderSide(color: AppColors.border),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: null,
                    child: const Text('Joined'),
                  )
                : OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(76, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: const StadiumBorder(),
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () => _join(c),
                    child: const Text('Join'),
                  ),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChannelScreen(channelId: c.id),
                ),
              );
              reload();
            },
          );
        },
      ),
    );
  }
}
