import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../screens/login_screen.dart';
import '../screens/player_screen.dart';
import '../screens/premium_screen.dart';
import '../services/backend.dart';
import '../services/downloads.dart';
import '../services/play_billing.dart';
import '../services/play_queue.dart';
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

/// Only a premium member may create a channel (the server enforces this
/// too). A free user is sent to Premium with an explanation instead of
/// opening the create-channel form.
Future<bool> ensurePremiumForChannel(BuildContext context) async {
  if (app.isPremium) return true;
  final go = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      icon: const Icon(Icons.workspace_premium_outlined, size: 36),
      title: const Text('Premium needed to create a channel'),
      content: const Text(
        'Creating your own channel is a Premium feature. Get a plan to start uploading.',
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
/// [replace]: swap the open player for this one (Next / Previous / Skip), so
/// Back still returns to the screen the viewer started from.
Future<void> watchItem(
  BuildContext context,
  Post post,
  PostItem item, {
  bool replace = false,
}) async {
  final mine = post.createdBy != null && post.createdBy == app.userId;
  if (!mine && !await ensureLoggedIn(context, reason: 'Log in to watch')) {
    return;
  }
  if (!context.mounted) return;
  if (!canWatchFull(post, item)) {
    await openPlans(context);
    return;
  }
  await _play(
    context,
    post,
    () => item.isBunnyBacked
        ? Backend.bunnyStreamUrl(item.id)
        : Backend.mediaUrl(item.mediaKey!),
    item.isVideo,
    post.title,
    replace: replace,
  );
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
  PostItem item, {
  bool replace = false,
}) async {
  // Viewers who can already watch the full video just see the trailer.
  final full = canWatchFull(post, item);
  await _play(
    context,
    post,
    () => _trailerUrl(item),
    true,
    'Trailer · ${post.title}',
    event: 'preview_view',
    replace: replace,
    onWatchFull: full ? null : (ctx) => watchItem(ctx, post, item),
    onTrailerEnd: full ? null : (ctx) => subscribeToWatch(ctx, post, item),
  );
}

Future<String> _trailerUrl(PostItem item) => item.trailerOnBunny
    ? Backend.bunnyStreamUrl(item.id, trailer: true)
    : Backend.mediaUrl(item.trailerKey!);

/// Premium videos open on their preview first, with a Skip button, for
/// viewers who get previews: ads users and organic users approved for ads
/// access (plain organic users never get previews). Never for the creator.
/// Previews can be watched any number of times.
bool previewFirst(Post post, PostItem item) {
  final mine = post.createdBy != null && post.createdBy == app.userId;
  return !mine &&
      item.isVideo &&
      item.isPremium &&
      item.hasTrailer &&
      app.hasAdsAccess;
}

/// Preview first. Skip (shown for the first seconds) and the preview's end
/// lead to the full video for viewers with a plan; Skip takes everyone else
/// to the plans page (and on to the full video if they then subscribe).
Future<void> _watchPreviewFirst(
  BuildContext context,
  Post post,
  PostItem item, {
  bool replace = false,
}) {
  final full = canWatchFull(post, item);
  return _play(
    context,
    post,
    () => _trailerUrl(item),
    true,
    'Preview · ${post.title}',
    event: 'preview_view',
    replace: replace,
    onSkip: full
        ? (ctx) => watchItem(ctx, post, item, replace: true)
        : (ctx) async {
            await openPlans(ctx);
            if (ctx.mounted && canWatchFull(post, item)) {
              await watchItem(ctx, post, item, replace: true);
            }
          },
    onPreviewDone: full ? (ctx) => watchItem(ctx, post, item, replace: true) : null,
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

/// Tap on a post's media: preview first where that applies, the trailer
/// when that's all the user may watch, otherwise the full item (with its
/// gates).
Future<void> openItem(
  BuildContext context,
  Post post,
  PostItem item, {
  bool replace = false,
}) => previewFirst(post, item)
    ? _watchPreviewFirst(context, post, item, replace: replace)
    : canWatchTrailer(post, item)
    ? watchTrailer(context, post, item, replace: replace)
    : watchItem(context, post, item, replace: replace);

PostItem? _firstVideo(Post post) {
  for (final i in post.items) {
    if (i.isVideo) return i;
  }
  return null;
}

/// Next / Previous may only land on a video this viewer can actually play
/// (no plan wall, no login wall on the way).
bool _playableInQueue(Post post) {
  final item = _firstVideo(post);
  if (item == null) return false;
  if (previewFirst(post, item) || canWatchTrailer(post, item)) return true;
  final mine = post.createdBy != null && post.createdBy == app.userId;
  return canWatchFull(post, item) && (mine || !app.isGuest);
}

/// Next (dir 1) or previous (dir -1) video, in place of the open player.
Future<void> _playNeighbor(BuildContext context, Post post, int dir) async {
  Post? next;
  try {
    next = await PlayQueue.neighbor(post, dir, _playableInQueue);
  } catch (e) {
    if (context.mounted) showSnack(context, friendlyError(e));
    return;
  }
  if (!context.mounted) return;
  if (next == null) {
    showSnack(context, dir > 0 ? 'No more videos' : 'No earlier videos');
    return;
  }
  await openItem(context, next, _firstVideo(next)!, replace: true);
}

Future<void> _play(
  BuildContext context,
  Post post,
  Future<String> Function() urlResolver,
  bool isVideo,
  String title, {
  String? event,
  bool replace = false,
  void Function(BuildContext)? onWatchFull,
  void Function(BuildContext)? onTrailerEnd,
  void Function(BuildContext)? onSkip,
  void Function(BuildContext)? onPreviewDone,
}) async {
  try {
    final url = await urlResolver();
    Backend.logEvent(
      app.installId,
      event ?? (onWatchFull == null ? 'content_view' : 'preview_view'),
      contentId: post.id,
      viewId: const Uuid().v4(),
    );
    if (!context.mounted) return;
    final route = MaterialPageRoute<void>(
      builder: (_) => isVideo
          ? PlayerScreen(
              url: url,
              title: title,
              onWatchFull: onWatchFull,
              onTrailerEnd: onTrailerEnd,
              onSkip: onSkip,
              onPreviewDone: onPreviewDone,
              onNext: (ctx) => _playNeighbor(ctx, post, 1),
              onPrevious: (ctx) => _playNeighbor(ctx, post, -1),
            )
          : ImageViewerScreen(url: url, title: title),
    );
    final navigator = Navigator.of(context);
    if (replace) {
      await navigator.pushReplacement(route);
    } else {
      await navigator.push(route);
    }
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
  if (PlayBilling.hidesPlans) {
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
  if (item.isBunnyBacked) {
    showSnack(context, 'Downloads aren\'t available for this video yet.');
    return;
  }
  if (!await ensurePremiumForDownload(context) || !context.mounted) return;
  await _saveFrom(
    context,
    () => Backend.mediaUrl(item.mediaKey!),
    Downloads.nameFor(post.title, item.mediaKey!),
    item.isVideo ? 'video/*' : 'image/*',
  );
}

/// Download one of the user's own cloud files (premium).
Future<void> downloadCloudFile(BuildContext context, CloudFile f) async {
  if (f.storageKey == null && f.bunnyPath == null) return;
  if (!await ensurePremiumForDownload(context) || !context.mounted) return;
  await _saveFrom(context, () => Backend.cloudUrl(f), f.name, f.mime);
}
