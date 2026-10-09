import 'package:flutter/material.dart';

import '../models.dart';
import '../services/backend.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/channel_photo.dart';
import '../widgets/common.dart';
import '../widgets/gates.dart';
import 'channel_screen.dart';
import 'create_channel_screen.dart';
import 'login_screen.dart';
import 'new_post_screen.dart';
import 'payment_history_screen.dart';
import 'settings_screen.dart';

/// Profile: name (editable), settings, account, My Channels (created + joined).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Channel>? created;
  List<Channel>? joined;

  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = sb.auth.currentUser?.id;
    app.addListener(_onApp);
    app.contentVersion.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    app.removeListener(_onApp);
    app.contentVersion.removeListener(_load);
    super.dispose();
  }

  /// Logging in (or out) switches the user: show that user's channels.
  void _onApp() {
    final uid = sb.auth.currentUser?.id;
    if (uid == _uid) return;
    _uid = uid;
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        Backend.myCreatedChannels(),
        Backend.joinedChannels(),
      ]);
      if (!mounted) return;
      final createdIds = r[0].map((c) => c.id).toSet();
      setState(() {
        created = r[0];
        joined = r[1].where((c) => !createdIds.contains(c.id)).toList();
      });
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: app.status?.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await app.updateName(name);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }

  Future<void> _createChannel() async {
    if (!await ensureLoggedIn(context, reason: 'Log in to create a channel')) {
      return;
    }
    if (!mounted) return;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateChannelScreen()),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final s = app.status;
        return Scaffold(
          body: RefreshIndicator(
            onRefresh: _load,
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 168,
                  backgroundColor: AppColors.background,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                              colors: [
                                Color(0xFFFF7A1A),
                                Color(0xFF8A2D05),
                                Color(0xFF2A1408),
                              ],
                            ),
                          ),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x00000000),
                                Color(0x660B0B0D),
                                AppColors.background,
                              ],
                              stops: [0.3, 0.7, 1],
                            ),
                          ),
                        ),
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 50, 8, 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    gradient: AppColors.gradient,
                                    shape: BoxShape.circle,
                                  ),
                                  child: CircleAvatar(
                                    radius: 34,
                                    backgroundColor: AppColors.surfaceHigh,
                                    child: Text(
                                      (s?.displayName ?? 'U').characters.first
                                          .toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 28,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s?.displayName ?? '',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (s?.isPremium == true) ...[
                                        const SizedBox(height: 4),
                                        const PremiumBadge(),
                                      ],
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    color: Colors.white,
                                  ),
                                  tooltip: 'Edit name',
                                  onPressed: _editName,
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.settings_outlined,
                                    color: Colors.white,
                                  ),
                                  tooltip: 'Settings',
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const SettingsScreen(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _account(s)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'My Channels',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _createChannel,
                          child: const Text(
                            'Add Channel',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (created == null)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (created!.isEmpty && joined!.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: EmptyState(
                        message: 'No Record Found',
                        icon: Icons.live_tv_outlined,
                      ),
                    ),
                  )
                else
                  SliverList.list(
                    children: [
                      for (final c in created!) _channelTile(c, mine: true),
                      for (final c in joined!) _channelTile(c),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _account(UserStatus? s) {
    if (s == null) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.isGuest) ...[
              const Text(
                'You\'re using the app as a guest.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
                child: const Text('Log in / Create account'),
              ),
            ] else ...[
              Row(
                children: [
                  const Icon(Icons.email_outlined, color: AppColors.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      app.email ?? '',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    s.isPremium
                        ? Icons.workspace_premium
                        : Icons.person_outline,
                    color: s.isPremium ? AppColors.gold : AppColors.muted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    s.planName != null
                        ? '${s.planName} active'
                        : s.isPremium
                        ? 'Full access'
                        : 'Free account',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (_uploadable.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _uploadPicker,
                    icon: const Icon(Icons.cloud_upload_rounded),
                    label: const Text('Upload content'),
                  ),
                ),
              ],
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                icon: const Icon(Icons.receipt_long),
                label: const Text('Payment history'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PaymentHistoryScreen(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Channel> get _uploadable =>
      (created ?? []).where((c) => c.reviewStatus == 'approved').toList();

  Future<void> _upload(Channel c) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewPostScreen(channelId: c.id, channelName: c.name),
      ),
    );
    if (ok == true) _load();
  }

  /// One channel → straight to the upload screen; several → pick one.
  Future<void> _uploadPicker() async {
    final list = _uploadable;
    if (list.length == 1) return _upload(list.first);
    final pick = await showModalBottomSheet<Channel>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Upload to which channel?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            for (final c in list)
              ListTile(
                leading: ChannelAvatar(url: c.iconUrl, name: c.name, size: 36),
                title: Text(c.name),
                onTap: () => Navigator.pop(context, c),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (pick != null) await _upload(pick);
  }

  Widget _channelTile(Channel c, {bool mine = false}) {
    Widget? badge;
    if (mine) {
      badge = switch (c.reviewStatus) {
        'pending' => const Chip(
          label: Text('Waiting for approval'),
          backgroundColor: AppColors.warningBg,
        ),
        'rejected' => const Chip(
          label: Text('Not approved'),
          backgroundColor: AppColors.dangerBg,
        ),
        _ => FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => _upload(c),
          icon: const Icon(Icons.upload_rounded, size: 18),
          label: const Text('Upload'),
        ),
      };
    }
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: mine
          ? EditableChannelAvatar(channel: c, size: 52, onChanged: _load)
          : ChannelAvatar(url: c.iconUrl, name: c.name, size: 52),
      title: Text(
        c.name,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
      subtitle: Text('${c.membersCount} members'),
      trailing: badge,
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChannelScreen(channelId: c.id)),
        );
        _load();
      },
    );
  }
}
