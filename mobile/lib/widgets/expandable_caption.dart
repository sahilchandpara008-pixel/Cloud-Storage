import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// A video's description: the first few words, then "… see more". Tapping
/// "see more" shows the whole text, with "see less" to fold it again.
class ExpandableCaption extends StatefulWidget {
  final String text;
  final TextStyle style;
  final int words;

  const ExpandableCaption({
    super.key,
    required this.text,
    required this.style,
    this.words = 8,
  });

  @override
  State<ExpandableCaption> createState() => _ExpandableCaptionState();
}

class _ExpandableCaptionState extends State<ExpandableCaption> {
  bool _open = false;
  late final TapGestureRecognizer _toggle = TapGestureRecognizer()
    ..onTap = () => setState(() => _open = !_open);

  @override
  void dispose() {
    _toggle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text.trim();
    final parts = text.split(RegExp(r'\s+'));
    final long = parts.length > widget.words;
    const link = TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600);

    if (!long) return Text(text, style: widget.style);

    return Text.rich(
      TextSpan(
        style: widget.style,
        children: [
          TextSpan(text: _open ? text : '${parts.take(widget.words).join(' ')}… '),
          if (_open) const TextSpan(text: ' '),
          TextSpan(
            text: _open ? 'see less' : 'see more',
            style: link,
            recognizer: _toggle,
            semanticsLabel: _open ? 'Show less of the description' : 'Show the full description',
          ),
        ],
      ),
    );
  }
}
