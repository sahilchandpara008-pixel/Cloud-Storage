import '../models.dart';
import 'backend.dart';
import 'blocks.dart';

/// Next / previous video for the player.
///
/// Order is the channel page's order (newest first): "next" is the post
/// below the current one. At the end of a channel it moves to the next
/// channel (and "previous" to the channel before), skipping blocked channels
/// and anything this viewer can't play, and stops after a few channels
/// instead of looping.
class PlayQueue {
  static const maxChannels = 6;

  /// The first post in [posts] after (dir = 1) or before (dir = -1) the post
  /// [currentId] that [playable] accepts. When [currentId] is not in the
  /// list (a different channel), searching starts at the list's start
  /// (dir = 1) or end (dir = -1).
  static Post? pickInList(
    List<Post> posts,
    String? currentId,
    int dir,
    bool Function(Post) playable,
  ) {
    assert(dir == 1 || dir == -1);
    final at = currentId == null ? -1 : posts.indexWhere((p) => p.id == currentId);
    var i = at >= 0 ? at + dir : (dir == 1 ? 0 : posts.length - 1);
    for (; i >= 0 && i < posts.length; i += dir) {
      if (playable(posts[i])) return posts[i];
    }
    return null;
  }

  /// Channel ids to try after [currentChannelId] in direction [dir], in
  /// order, at most [limit]; the current channel itself is never returned.
  static List<String> channelsAfter(
    List<String> order,
    String currentChannelId,
    int dir, {
    int limit = maxChannels,
  }) {
    final at = order.indexOf(currentChannelId);
    final out = <String>[];
    var i = at >= 0 ? at + dir : (dir == 1 ? 0 : order.length - 1);
    for (; i >= 0 && i < order.length && out.length < limit; i += dir) {
      if (order[i] != currentChannelId) out.add(order[i]);
    }
    return out;
  }

  /// The neighbouring playable post, or null when there is none nearby.
  static Future<Post?> neighbor(
    Post current,
    int dir,
    bool Function(Post) playable,
  ) async {
    final same = await Backend.channelPosts(current.channelId);
    final inChannel = pickInList(same, current.id, dir, playable);
    if (inChannel != null) return inChannel;

    final channels = await Backend.channels(sort: 'latest');
    final order = channels.map((c) => c.id).toList();
    for (final id in channelsAfter(order, current.channelId, dir)) {
      if (Blocks.has(id)) continue;
      final posts = await Backend.channelPosts(id);
      final found = pickInList(posts, null, dir, playable);
      if (found != null) return found;
    }
    return null;
  }
}
