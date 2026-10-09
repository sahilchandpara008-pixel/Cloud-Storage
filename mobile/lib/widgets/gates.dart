import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../screens/login_screen.dart';
import '../screens/player_screen.dart';
import '../screens/premium_screen.dart';
import '../services/backend.dart';
import '../services/downloads.dart';
import '../services/play_billing.dart';
import '../state/app_state.dart';
import 'common.dart';

/// Login gate: guests see a "Please log in" pop-up, then the login screen.
Future<bool> ensureLoggedIn(BuildContext context, {String? reason}) async {
  if (!app.isGuest) return true;
  final go = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      icon: const Icon(Icons.lock_outline, size: 36),
      title: const Text('Please log in'),
      content: Text(
        reason ?? 'Log in to continue.',
        textAlign: TextAlign.center,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Log in'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return false;
  final ok = await Navigator.of(context)
      .push<bool>(MaterialPageRoute(builder: (_) => const LoginScreen()));
  return ok == true && !app.isGuest;
}

Future<void> openPlans(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const PremiumScreen(standalone: true)),
  );
}

/// The creator always sees their own content in full; otherwise premium
/// items need a plan.
bool canWatchFull(Post post, PostItem item) {
  final mine = post.createdBy != null && post.createdBy == app.userId;
  return mine || !item.isPremium || app.isPremium;
}

/// Ads users can play a premium item's trailer without login or plan.
bool canWatchTrailer(Post post, PostItem item) =>
    item.hasTrailer && !canWatchFull(post, item) && app.hasAdsAccess;

/// Watch a post item: login → plan (for premium items) → online player.
Future<void> watchItem(BuildContext context, Post post, PostItem item) async {
  final mine = post.createdBy != null && post.createdBy == app.userId;
  if (!mine && !await ensureLoggedIn(context, reason: 'Log in to watch')) {
    return;
  }
  if (!context.mounted) return;
  if (!canWatchFull(post, item)) {
    await openPlans(context);
    return;
  }
  await _play(context, post, item.mediaKey, item.isVideo, post.title);
}

/// After a trailer: guests log in (no extra pop-up), then the normal gates
/// apply - plans for non-subscribers, the full video for subscribers.
Future<void> subscribeToWatch(
  BuildContext context,
  Post post,
  PostItem item,
) async {
  if (app.isGuest) {
    final ok = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const LoginScreen()));
    if (ok != true || app.isGuest || !context.mounted) return;
  }
  await watchItem(context, post, item);
}

/// Play the trailer; the player offers "Watch full video" (login → plan).
Future<void> watchTrailer(
  BuildContext context,
  Post post,
  PostItem item,
) async {
  // Viewers who can already watch the full video just see the trailer.
  final full = canWatchFull(post, item);
  await _play(
    context,
    post,
    item.trailerKey!,
    true,
    'Trailer · ${post.title}',
    event: 'preview_view',
    onWatchFull: full ? null : (ctx) => watchItem(ctx, post, item),
    onTrailerEnd: full ? null : (ctx) => subscribeToWatch(ctx, post, item),
  );
}

/// Whether the content page shows a "Trailer" button: ads users before they
/// subscribe (as before), and anyone who can already watch the full video.
bool showTrailerButton(Post post, PostItem item) =>
    item.isVideo &&
    item.hasTrailer &&
    (canWatchTrailer(post, item) || canWatchFull(post, item));

/// Tap on a post's media: trailer when that's all the user may watch,
/// otherwise the full item (with its gates).
Future<void> openItem(BuildContext context, Post post, PostItem item) =>
    canWatchTrailer(post, item)
    ? watchTrailer(context, post, item)
    : watchItem(context, post, item);

Future<void> _play(
  BuildContext context,
  Post post,
  String key,
  bool isVideo,
  String title, {
  String? event,
  void Function(BuildContext)? onWatchFull,
  void Function(BuildContext)? onTrailerEnd,
}) async {
  try {
    final url = await Backend.mediaUrl(key);
    Backend.logEvent(
      app.installId,
      event ?? (onWatchFull == null ? 'content_view' : 'preview_view'),
      contentId: post.id,
      viewId: const Uuid().v4(),
    );
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => isVideo
            ? PlayerScreen(
                url: url,
                title: title,
                onWatchFull: onWatchFull,
                onTrailerEnd: onTrailerEnd,
              )
            : ImageViewerScreen(url: url, title: title),
      ),
    );
  } catch (e) {
    if (context.mounted) showSnack(context, friendlyError(e));
  }
}

/// Premium members can save files to their phone. Others are invited to
/// get a plan (the normal plans screen).
Future<bool> ensurePremiumForDownload(BuildContext context) async {
  if (app.isPremium) return true;
  // Free mode: downloads come with full access (approval for organic users).
  if (app.freeMode) {
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.download_rounded, size: 36),
        title: const Text('Download needs full access'),
        content: const Text(
          'Downloads are available once your account has full access.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Get full access'),
          ),
        ],
      ),
    );
    if (go == true && context.mounted) await openPlans(context);
    return false;
  }
  // Google Play build: no plans to buy in the app, just say what it is.
  if (PlayBilling.isPlayBuild) {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.download_rounded, size: 36),
        title: const Text('Download is a Premium feature'),
        content: const Text(
          'Downloads are available to Premium members.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return false;
  }
  final go = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      icon: const Icon(Icons.download_rounded, size: 36),
      title: const Text('Download is a Premium feature'),
      content: const Text(
        'Get a Premium plan to save videos, photos and your cloud files to your phone.',
        textAlign: TextAlign.center,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('See plans'),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) await openPlans(context);
  return false;
}

Future<void> _saveFrom(
  BuildContext context,
  Future<String> Function() url,
  String name,
  String? mime,
) async {
  try {
    await Downloads.save(url: await url(), name: name, mime: mime);
    if (context.mounted) {
      showSnack(
        context,
        'Downloading "${Downloads.safeName(name)}"… See your notifications.',
      );
    }
  } catch (e) {
    if (context.mounted) showSnack(context, friendlyError(e));
  }
}

/// Download a post item (premium; the server still checks access).
Future<void> downloadItem(
  BuildContext context,
  Post post,
  PostItem item,
) async {
  if (!await ensurePremiumForDownload(context) || !context.mounted) return;
  await _saveFrom(
    context,
    () => Backend.mediaUrl(item.mediaKey),
    Downloads.nameFor(post.title, item.mediaKey),
    item.isVideo ? 'video/*' : 'image/*',
  );
}

/// Download one of the user's own cloud files (premium).
Future<void> downloadCloudFile(BuildContext context, CloudFile f) async {
  if (f.storageKey == null) return;
  if (!await ensurePremiumForDownload(context) || !context.mounted) return;
  await _saveFrom(
    context,
    () => Backend.cloudUrl(f.storageKey!),
    f.name,
    f.mime,
  );
}
