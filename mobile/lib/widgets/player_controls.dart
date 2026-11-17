import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';

import '../theme.dart';

/// Player overlay in the style of MX Player / VLC, drawn on top of the
/// existing Chewie + video_player playback (no playback changes):
/// tap to show/hide, auto-hide while playing, double-tap left/right to seek
/// 10 s, swipe up/down on the left for brightness and on the right for
/// volume, swipe left/right to seek, previous/next video, big centre
/// controls, thin seek bar with times, fullscreen toggle.
class PremiumPlayerControls extends StatefulWidget {
  final String title;

  /// Rotate button (MX Player style); without it the button uses Chewie's
  /// fullscreen.
  final VoidCallback? onRotate;

  /// Previous / next video; the buttons are hidden when null.
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  const PremiumPlayerControls({
    super.key,
    required this.title,
    this.onRotate,
    this.onNext,
    this.onPrevious,
  });

  @override
  State<PremiumPlayerControls> createState() => _PremiumPlayerControlsState();
}

class _PremiumPlayerControlsState extends State<PremiumPlayerControls> {
  static const _seekStep = Duration(seconds: 10);
  static const _hideAfter = Duration(seconds: 3);

  ChewieController? _chewie;
  VideoPlayerController? _video;
  bool _visible = true;
  Timer? _hideTimer;
  double? _dragValue; // seek bar position while dragging (ms)
  String? _seekFlash; // "+10s" / "-10s" feedback
  Timer? _flashTimer;

  // Swipe gestures (MX Player style).
  static const _edge = 40.0; // leave the screen edges to Android's gestures
  _Swipe? _swipe; // what the current drag changes
  double _brightness = 0.5;
  double _volume = 0.5;
  Duration? _seekTarget; // horizontal swipe: where the video will jump to
  double _swipeDx = 0;

  @override
  void initState() {
    super.initState();
    // Swipe changes the media volume quietly (no system volume pop-up).
    VolumeController.instance.showSystemUI = false;
    ScreenBrightness.instance.application
        .then((b) => _brightness = b)
        .catchError((_) => _brightness);
    VolumeController.instance
        .getVolume()
        .then((v) => _volume = v)
        .catchError((_) => _volume);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = ChewieController.of(context);
    if (c != _chewie) {
      _video?.removeListener(_onVideo);
      _chewie = c;
      _video = c.videoPlayerController..addListener(_onVideo);
      _scheduleHide();
    }
  }

  @override
  void dispose() {
    _video?.removeListener(_onVideo);
    _hideTimer?.cancel();
    _flashTimer?.cancel();
    super.dispose();
  }

  void _onVideo() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideAfter, () {
      if (mounted && (_video?.value.isPlaying ?? false) && _dragValue == null) {
        setState(() => _visible = false);
      }
    });
  }

  void _toggleVisible() {
    setState(() => _visible = !_visible);
    if (_visible) _scheduleHide();
  }

  void _poke() {
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  void _playPause() {
    final v = _video!;
    if (v.value.isPlaying) {
      v.pause();
      _hideTimer?.cancel();
      setState(() => _visible = true);
    } else {
      if (v.value.position >= v.value.duration &&
          v.value.duration > Duration.zero) {
        v.seekTo(Duration.zero);
      }
      v.play();
      _scheduleHide();
    }
  }

  void _seekBy(Duration d) {
    final v = _video!;
    final dur = v.value.duration;
    var target = v.value.position + d;
    if (target < Duration.zero) target = Duration.zero;
    if (dur > Duration.zero && target > dur) target = dur;
    v.seekTo(target);
    _flashTimer?.cancel();
    setState(() => _seekFlash = d.isNegative ? '-10s' : '+10s');
    _flashTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _seekFlash = null);
    });
    _poke();
  }

  bool _nearEdge(Offset p, Size size) =>
      p.dx < _edge || p.dx > size.width - _edge || p.dy < _edge;

  void _verticalStart(DragStartDetails d, Size size) {
    if (_nearEdge(d.globalPosition, size)) return;
    final left = d.globalPosition.dx < size.width / 2;
    _swipe = left ? _Swipe.brightness : _Swipe.volume;
    if (!left) {
      VolumeController.instance.getVolume().then((v) => _volume = v).catchError((_) => _volume);
    }
    setState(() {});
  }

  void _verticalUpdate(DragUpdateDetails d, Size size) {
    if (_swipe == null) return;
    final change = -d.delta.dy / (size.height * 0.7);
    setState(() {
      if (_swipe == _Swipe.brightness) {
        _brightness = (_brightness + change).clamp(0.02, 1.0);
        ScreenBrightness.instance
            .setApplicationScreenBrightness(_brightness)
            .catchError((_) {});
      } else {
        _volume = (_volume + change).clamp(0.0, 1.0);
        VolumeController.instance.setVolume(_volume).catchError((_) {});
      }
    });
  }

  void _horizontalStart(DragStartDetails d, Size size) {
    final v = _video;
    if (v == null || _nearEdge(d.globalPosition, size)) return;
    if (v.value.duration <= Duration.zero) return;
    _swipe = _Swipe.seek;
    _swipeDx = 0;
    _hideTimer?.cancel();
    setState(() => _seekTarget = v.value.position);
  }

  void _horizontalUpdate(DragUpdateDetails d, Size size) {
    final v = _video;
    if (_swipe != _Swipe.seek || v == null) return;
    _swipeDx += d.delta.dx;
    // A full-width swipe moves 90 seconds (shorter videos: their length).
    final span = v.value.duration < const Duration(seconds: 90)
        ? v.value.duration
        : const Duration(seconds: 90);
    final delta = span * (_swipeDx / size.width);
    var target = v.value.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (target > v.value.duration) target = v.value.duration;
    setState(() => _seekTarget = target);
  }

  void _dragEnd([DragEndDetails? _]) {
    final target = _seekTarget;
    if (_swipe == _Swipe.seek && target != null) _video?.seekTo(target);
    setState(() {
      _swipe = null;
      _seekTarget = null;
    });
    if (_visible) _scheduleHide();
  }

  void _back() {
    final c = _chewie!;
    if (c.isFullScreen) {
      c.exitFullScreen();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    if (v == null) return const SizedBox.shrink();
    final value = v.value;

    if (value.hasError) {
      return _ErrorView(
        onRetry: () {
          v.initialize().then((_) => v.play()).catchError((_) {});
        },
      );
    }

    final total = value.duration;
    final pos = value.position;
    final maxMs = total.inMilliseconds.toDouble().clamp(1, double.infinity);
    final shownMs = (_dragValue ?? pos.inMilliseconds.toDouble()).clamp(
      0.0,
      maxMs.toDouble(),
    );
    final buffering =
        value.isBuffering && !value.isPlaying ||
        (value.isBuffering && value.isPlaying && pos == Duration.zero);
    final fullscreen = widget.onRotate != null
        ? MediaQuery.orientationOf(context) == Orientation.landscape
        : _chewie!.isFullScreen;

    return LayoutBuilder(
      builder: (context, box) => Stack(
        fit: StackFit.expand,
        children: [
          // Gestures: tap toggles controls, double-tap sides seeks.
          Row(
            children: [
              for (final dir in [-1, 1])
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleVisible,
                    onDoubleTap: () =>
                        _seekBy(dir < 0 ? -_seekStep : _seekStep),
                    onVerticalDragStart: (d) =>
                        _verticalStart(d, box.biggest),
                    onVerticalDragUpdate: (d) =>
                        _verticalUpdate(d, box.biggest),
                    onVerticalDragEnd: _dragEnd,
                    onVerticalDragCancel: _dragEnd,
                    onHorizontalDragStart: (d) =>
                        _horizontalStart(d, box.biggest),
                    onHorizontalDragUpdate: (d) =>
                        _horizontalUpdate(d, box.biggest),
                    onHorizontalDragEnd: _dragEnd,
                    onHorizontalDragCancel: _dragEnd,
                  ),
                ),
            ],
          ),

          // Seek feedback
          if (_seekFlash != null)
            Align(
              alignment: _seekFlash!.startsWith('-')
                  ? const Alignment(-0.6, 0)
                  : const Alignment(0.6, 0),
              child: _Pill(
                icon: _seekFlash!.startsWith('-')
                    ? Icons.fast_rewind_rounded
                    : Icons.fast_forward_rounded,
                text: _seekFlash!,
              ),
            ),

          // Swipe feedback
          if (_swipe == _Swipe.brightness || _swipe == _Swipe.volume)
            Align(
              alignment: const Alignment(0, -0.45),
              child: _Pill(
                icon: _swipe == _Swipe.brightness
                    ? Icons.brightness_6_rounded
                    : _volume == 0
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                text:
                    '${_swipe == _Swipe.brightness ? 'Brightness' : 'Volume'} '
                    '${((_swipe == _Swipe.brightness ? _brightness : _volume) * 100).round()}%',
              ),
            ),
          if (_swipe == _Swipe.seek && _seekTarget != null)
            Align(
              alignment: const Alignment(0, -0.45),
              child: _Pill(
                icon: _seekTarget! < value.position
                    ? Icons.fast_rewind_rounded
                    : Icons.fast_forward_rounded,
                text:
                    '${_fmt(_seekTarget!)} / ${_fmt(value.duration)}',
              ),
            ),

          // Buffering (does not block the controls)
          if (buffering)
            const Center(
              child: SizedBox(
                width: 54,
                height: 54,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              ),
            ),

          // Controls
          IgnorePointer(
            ignoring: !_visible,
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Light dim so controls read on bright video
                  const ColoredBox(color: Color(0x33000000)),
                  // Top and bottom scrims
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xAA000000),
                          Color(0x00000000),
                          Color(0x00000000),
                          Color(0xCC000000),
                        ],
                        stops: [0, 0.28, 0.62, 1],
                      ),
                    ),
                  ),
                  // Top bar
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Back',
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                              ),
                              onPressed: _back,
                            ),
                            Expanded(
                              child: Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: value.volume == 0 ? 'Unmute' : 'Mute',
                              icon: Icon(
                                value.volume == 0
                                    ? Icons.volume_off_rounded
                                    : Icons.volume_up_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                v.setVolume(value.volume == 0 ? 1 : 0);
                                _poke();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Centre controls
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.onPrevious != null) ...[
                          _RoundButton(
                            icon: Icons.skip_previous_rounded,
                            size: 44,
                            tooltip: 'Previous video',
                            onTap: widget.onPrevious!,
                          ),
                          SizedBox(width: box.maxWidth > 500 ? 32 : 14),
                        ],
                        _RoundButton(
                          icon: Icons.replay_10_rounded,
                          size: 52,
                          tooltip: 'Back 10 seconds',
                          onTap: () => _seekBy(-_seekStep),
                        ),
                        SizedBox(
                          width: box.maxWidth > 500
                              ? 48
                              : (widget.onNext != null ? 16 : 28),
                        ),
                        if (!buffering)
                          _RoundButton(
                            icon: value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 74,
                            filled: true,
                            tooltip: value.isPlaying ? 'Pause' : 'Play',
                            onTap: _playPause,
                          )
                        else
                          const SizedBox(width: 74, height: 74),
                        SizedBox(
                          width: box.maxWidth > 500
                              ? 48
                              : (widget.onNext != null ? 16 : 28),
                        ),
                        _RoundButton(
                          icon: Icons.forward_10_rounded,
                          size: 52,
                          tooltip: 'Forward 10 seconds',
                          onTap: () => _seekBy(_seekStep),
                        ),
                        if (widget.onNext != null) ...[
                          SizedBox(width: box.maxWidth > 500 ? 32 : 14),
                          _RoundButton(
                            icon: Icons.skip_next_rounded,
                            size: 44,
                            tooltip: 'Next video',
                            onTap: widget.onNext!,
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Bottom bar
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 6, 6),
                        child: Row(
                          children: [
                            Text(
                              _fmt(Duration(milliseconds: shownMs.round())),
                              style: _timeStyle,
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  activeTrackColor: AppColors.primary,
                                  inactiveTrackColor: const Color(0x40FFFFFF),
                                  secondaryActiveTrackColor: const Color(
                                    0x66FFFFFF,
                                  ),
                                  thumbColor: Colors.white,
                                  overlayColor: const Color(0x33FF7A1A),
                                  thumbShape: RoundSliderThumbShape(
                                    enabledThumbRadius: _dragValue != null
                                        ? 8
                                        : 6,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 18,
                                  ),
                                ),
                                child: Slider(
                                  min: 0,
                                  max: maxMs.toDouble(),
                                  value: shownMs.toDouble(),
                                  secondaryTrackValue: _bufferedMs(value)
                                      .clamp(0, maxMs.toDouble())
                                      .toDouble(),
                                  onChangeStart: (x) {
                                    _hideTimer?.cancel();
                                    setState(() => _dragValue = x);
                                  },
                                  onChanged: (x) =>
                                      setState(() => _dragValue = x),
                                  onChangeEnd: (x) {
                                    v.seekTo(Duration(milliseconds: x.round()));
                                    setState(() => _dragValue = null);
                                    _scheduleHide();
                                  },
                                ),
                              ),
                            ),
                            Text(_fmt(total), style: _timeStyle),
                            IconButton(
                              tooltip: fullscreen
                                  ? 'Exit fullscreen'
                                  : 'Fullscreen',
                              icon: Icon(
                                fullscreen
                                    ? Icons.fullscreen_exit_rounded
                                    : Icons.fullscreen_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                              onPressed: () {
                                if (widget.onRotate != null) {
                                  widget.onRotate!();
                                } else {
                                  _chewie!.toggleFullScreen();
                                }
                                _poke();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static double _bufferedMs(VideoPlayerValue v) =>
      v.buffered.isEmpty ? 0 : v.buffered.last.end.inMilliseconds.toDouble();

  static const _timeStyle = TextStyle(
    color: Colors.white,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool filled;
  final String tooltip;
  final VoidCallback onTap;
  const _RoundButton({
    required this.icon,
    required this.size,
    required this.tooltip,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      child: Material(
        color: filled ? const Color(0x80000000) : const Color(0x66000000),
        shape: CircleBorder(
          side: BorderSide(
            color: filled ? const Color(0x99FFFFFF) : const Color(0x55FFFFFF),
            width: filled ? 1.6 : 1.2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: Colors.white, size: size * 0.55),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Pill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.danger,
            size: 44,
          ),
          const SizedBox(height: 12),
          const Text(
            "This video can't be played right now.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

enum _Swipe { brightness, volume, seek }
