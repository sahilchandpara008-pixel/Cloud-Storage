import 'package:flutter/material.dart';

import '../models.dart';
import '../services/backend.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/channel_photo.dart';
import '../widgets/common.dart';
import '../widgets/gates.dart';
import '../widgets/report.dart';
import '../services/blocks.dart';
import '../widgets/post_bubble.dart';
import 'new_post_screen.dart';

/// Channel page: Telegram-style stream of posts, Join bar, and (for the
/// creator of an approved channel) a button to post.
class ChannelScreen extends StatefulWidget {
  final String channelId;
  const ChannelScreen({super.key, required this.channelId});

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  Channel? channel;
  List<Post>? posts;
  List<Folder> folders = [];
  String? folderId;
  bool joined = false;
  String? error;

  bool get isCreator =>
      channel?.createdBy != null && channel!.createdBy == app.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        Backend.channel(widget.channelId),
        Backend.channelPosts(widget.channelId),
        Backend.folders(widget.channelId),
        Backend.joinedChannelIds(),
      ]);
      if (!mounted) return;
      setState(() {
        channel = results[0] as Channel?;
        posts = results[1] as List<Post>;
        folders = results[2] as List<Folder>;
        joined = (results[3] as Set<String>).contains(widget.channelId);
        error = channel == null ? 'This channel is not available.' : null;
      });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  Future<void> _join() async {
    if (!await ensureLoggedIn(context, reason: 'Log in to join channels')) {
      return;
    }
    try {
      await Backend.join(widget.channelId);
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }

  Future<void> _leave() async {
    try {
      await Backend.leave(widget.channelId);
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }

  Future<void> _deletePost(Post p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete post?'),
        content: Text('"${p.title}" will be removed from the channel.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Backend.deletePost(p.id);
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = channel;
    final approved = c?.reviewStatus == 'approved';
    final blocked = c != null && Blocks.has(c.id);
    final shown = posts == null
        ? null
        : blocked
        ? <Post>[]
        : (folderId == null
              ? posts!
              : posts!.where((p) => p.folderId == folderId).toList());

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.barGradient),
          child: SizedBox.expand(),
        ),
        titleSpacing: 0,
        toolbarHeight: 68,
        title: c == null
            ? const Text('Channel')
            : Row(
                children: [
                  if (isCreator)
                    EditableChannelAvatar(
                      channel: c,
                      size: 44,
                      onChanged: _load,
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: ChannelAvatar(
                        url: c.iconUrl,
                        name: c.name,
                        size: 44,
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          style: const TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${formatCount(c.membersCount)} followers',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          if (isCreator && c != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'photo' && await changeChannelPhoto(context, c)) {
                  _load();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'photo',
                  child: Text('Change channel photo'),
                ),
              ],
            ),
          if (!isCreator && c != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'leave') {
                  _leave();
                } else if (v == 'report') {
                  reportContent(context, channelId: c.id, title: c.name);
                } else if (v == 'block') {
                  await toggleBlockChannel(context, c.id, c.name);
                  if (mounted) setState(() {});
                }
              },
              itemBuilder: (_) => [
                if (joined)
                  const PopupMenuItem(
                    value: 'leave',
                    child: Text('Leave channel'),
                  ),
                const PopupMenuItem(
                  value: 'report',
                  child: Text('Report channel'),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: Text(
                    Blocks.has(c.id) ? 'Unblock channel' : 'Block channel',
                  ),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: isCreator && approved
          ? FloatingActionButton(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.ink,
              tooltip: 'New post',
              onPressed: () async {
                final posted = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) =>
                        NewPostScreen(channelId: c!.id, channelName: c.name),
                  ),
                );
                if (posted == true) _load();
              },
              child: const Icon(Icons.add),
            )
          : null,
      body: c == null
          ? (error != null
                ? ErrorRetry(message: error!, onRetry: _load)
                : const Center(child: CircularProgressIndicator()))
          : Column(
              children: [
                if (isCreator && !approved)
                  _ReviewBanner(status: c.reviewStatus),
                if (folders.isNotEmpty)
                  SizedBox(
                    height: 52,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      children: [
                        _folderChip(null, 'All'),
                        for (final f in folders) _folderChip(f.id, f.name),
                      ],
                    ),
                  ),
                Expanded(
                  child: shown == null
                      ? const Center(child: CircularProgressIndicator())
                      : shown.isEmpty
                      ? EmptyState(
                          message: blocked
                              ? 'You blocked this channel. Use ⋮ → Unblock channel to see its posts again.'
                              : isCreator && approved
                              ? 'Post your first video or image with the + button.'
                              : 'No posts yet.',
                          icon: Icons.video_library_outlined,
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            reverse: true, // newest at the bottom, like a chat
                            padding: const EdgeInsets.only(bottom: 8, top: 8),
                            itemCount: shown.length,
                            itemBuilder: (context, i) {
                              final p = shown[i];
                              return Column(
                                children: [
                                  PostBubble(
                                    post: p,
                                    onDelete: isCreator
                                        ? () => _deletePost(p)
                                        : null,
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                ),
                if (!joined && approved)
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      border: Border(
                        top: BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 52),
                            ),
                            onPressed: _join,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Join channel'),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _folderChip(String? id, String label) {
    final selected = folderId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: AppColors.primary,
        labelStyle: TextStyle(
          color: selected ? AppColors.ink : const Color(0xFFD4D4D8),
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
        ),
        onSelected: (_) => setState(() => folderId = id),
      ),
    );
  }
}

class _ReviewBanner extends StatelessWidget {
  final String status;
  const _ReviewBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final pending = status == 'pending';
    return Container(
      width: double.infinity,
      color: pending ? AppColors.warningBg : AppColors.dangerBg,
      padding: const EdgeInsets.all(14),
      child: Text(
        pending
            ? 'Your channel is waiting for approval. Once approved, people can find it and you can start posting.'
            : 'This channel request was not approved.',
        style: const TextStyle(fontSize: 14),
      ),
    );
  }
}
