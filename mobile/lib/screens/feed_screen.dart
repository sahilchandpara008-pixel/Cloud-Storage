import 'package:flutter/material.dart';

import '../models.dart';
import '../services/backend.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/post_bubble.dart';
import '../widgets/reload.dart';
import '../theme.dart';

/// Feed: newest posts from the channels the user joined.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with ContentReload {
  List<Post>? posts;
  String? error;

  @override
  Future<void> reload() async {
    try {
      final list = await Backend.feed();
      if (mounted) {
        setState(() {
          posts = list;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    // The feed changes when the user joins channels elsewhere: reload on tab switch.
    return ValueListenableBuilder<int>(
      valueListenable: app.tab,
      builder: (context, tab, child) {
        if (tab == 1 && posts != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _refreshIfStale(),
          );
        }
        return child!;
      },
      child: Scaffold(
        appBar: AppBar(
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.barGradient),
            child: SizedBox.expand(),
          ),
          title: const Text('Feed'),
          actions: const [CrownButton()],
        ),
        body: _body(),
      ),
    );
  }

  DateTime _lastLoad = DateTime.fromMillisecondsSinceEpoch(0);
  void _refreshIfStale() {
    if (DateTime.now().difference(_lastLoad).inSeconds < 10) return;
    _lastLoad = DateTime.now();
    reload();
  }

  Widget _body() {
    if (error != null && posts == null) {
      return ErrorRetry(message: error!, onRetry: reload);
    }
    if (posts == null) return const LoadingSkeleton();
    if (posts!.isEmpty) {
      return RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          children: [
            const SizedBox(height: 100),
            EmptyState(
              message: 'Join channels to get content here!',
              action: FilledButton(
                onPressed: () => app.tab.value = 3,
                child: const Text('Discover channels'),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: posts!.length,
        itemBuilder: (context, i) =>
            PostBubble(post: posts![i], showChannel: true),
      ),
    );
  }
}
