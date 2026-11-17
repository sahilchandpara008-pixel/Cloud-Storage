import 'package:cloud_storage/models.dart';
import 'package:cloud_storage/services/play_queue.dart';
import 'package:flutter_test/flutter_test.dart';

Post post(String id, {String channel = 'c1'}) => Post(
  id: id,
  channelId: channel,
  channelName: channel,
  title: id,
  publishedAt: DateTime(2026),
);

void main() {
  // Channel page order: newest first.
  final list = [post('a'), post('b'), post('c'), post('d'), post('e')];
  bool all(Post _) => true;

  test('next and previous inside a channel', () {
    expect(PlayQueue.pickInList(list, 'b', 1, all)?.id, 'c');
    expect(PlayQueue.pickInList(list, 'b', -1, all)?.id, 'a');
  });

  test('nothing past the ends of a channel', () {
    expect(PlayQueue.pickInList(list, 'e', 1, all), isNull);
    expect(PlayQueue.pickInList(list, 'a', -1, all), isNull);
  });

  test('skips posts the viewer cannot play', () {
    bool playable(Post p) => p.id != 'c' && p.id != 'd';
    expect(PlayQueue.pickInList(list, 'b', 1, playable)?.id, 'e');
    expect(PlayQueue.pickInList(list, 'e', -1, playable)?.id, 'b');
    expect(PlayQueue.pickInList(list, 'd', 1, (p) => false), isNull);
  });

  test('another channel starts at its first (next) or last (previous) post', () {
    expect(PlayQueue.pickInList(list, null, 1, all)?.id, 'a');
    expect(PlayQueue.pickInList(list, null, -1, all)?.id, 'e');
    expect(PlayQueue.pickInList(list, 'not-here', 1, all)?.id, 'a');
    expect(PlayQueue.pickInList(const [], null, 1, all), isNull);
  });

  test('channels to try after the current one, in order, never looping', () {
    final order = ['x', 'c1', 'y', 'z'];
    expect(PlayQueue.channelsAfter(order, 'c1', 1), ['y', 'z']);
    expect(PlayQueue.channelsAfter(order, 'c1', -1), ['x']);
    expect(PlayQueue.channelsAfter(order, 'z', 1), isEmpty);
    expect(PlayQueue.channelsAfter(order, 'c1', 1, limit: 1), ['y']);
    // Current channel not listed (e.g. hidden): try them all from the start.
    expect(PlayQueue.channelsAfter(order, 'gone', 1), order);
  });
}
