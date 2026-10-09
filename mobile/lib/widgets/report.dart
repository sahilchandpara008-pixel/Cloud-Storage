import 'package:flutter/material.dart';

import '../services/backend.dart';
import '../services/blocks.dart';
import '../state/app_state.dart';
import 'common.dart';

const _reasons = [
  'Sexual or nude content',
  'Violence or dangerous content',
  'Hate speech or harassment',
  'Copyright — this is my content',
  'Spam, scam or misleading',
  'Other',
];

/// Report a post or a channel. Reports reach the Flixvault team (admin panel).
Future<void> reportContent(
  BuildContext context, {
  String? postId,
  String? channelId,
  required String title,
}) async {
  String? reason;
  final details = TextEditingController();
  final send = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Report $title'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in _reasons)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    reason == r
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(r),
                  onTap: () => setState(() => reason = r),
                ),
              TextField(
                controller: details,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  hintText: 'More details (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: reason == null
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('Send report'),
          ),
        ],
      ),
    ),
  );
  if (send != true || reason == null || !context.mounted) return;
  try {
    await Backend.reportContent(
      postId: postId,
      channelId: channelId,
      reason: reason!,
      details: details.text,
    );
    if (context.mounted) {
      showSnack(context, 'Thanks — our team will review this report.');
    }
  } catch (e) {
    if (context.mounted) showSnack(context, friendlyError(e));
  }
}

/// Block or unblock a channel for this user. Returns the new state.
Future<bool> toggleBlockChannel(
  BuildContext context,
  String channelId,
  String name,
) async {
  final blocked = Blocks.has(channelId);
  if (!blocked) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Block $name?'),
        content: const Text(
          'You won\'t see posts from this channel in Explore, Feed or the channel list. You can unblock it any time from the channel page.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (ok != true) return blocked;
  }
  await Blocks.set(channelId, !blocked);
  app.bumpContent();
  if (context.mounted) {
    showSnack(context, blocked ? '$name unblocked.' : '$name blocked.');
  }
  return !blocked;
}
