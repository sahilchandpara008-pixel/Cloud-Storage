import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../services/screen_rotation.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/player_controls.dart';

/// Online video player (streams from a short-lived signed link; no downloads).
class PlayerScreen extends StatefulWidget {
  final String url;
  final String title;

  /// Set when playing a trailer: shows a "Watch full video" button.
  final void Function(BuildContext)? onWatchFull;

  /// Set when playing a trailer: called from the pop-up shown when it ends.
  final void Function(BuildContext)? onTrailerEnd;
  const PlayerScreen({
    super.key,
    required this.url,
    required this.title,
    this.onWatchFull,
    this.onTrailerEnd,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late VideoPlayerController _video;
  ChewieController? _chewie;
  String? _error;
  bool _endShown = false;
  bool? _landscape;

  @override
  void initState() {
    super.initState();
    // Turn with the phone, like MX Player / VLC.
    ScreenRotation.follow();
    _open();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (landscape == _landscape) return;
    _landscape = landscape;
    // Landscape = full screen video: hide the status and navigation bars.
    SystemChrome.setEnabledSystemUIMode(
      landscape ? SystemUiMode.immersiveSticky : SystemUiMode.manual,
      overlays: landscape ? null : SystemUiOverlay.values,
    );
  }

  /// Rotate button: switch between portrait and landscape.
  void _rotate() {
    if (_landscape ?? false) {
      ScreenRotation.portrait();
    } else {
      ScreenRotation.landscape();
    }
  }

  void _open() {
    _video = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _video
        .initialize()
        .then((_) {
          if (!mounted) return;
          if (widget.onTrailerEnd != null) _video.addListener(_watchEnd);
          setState(() {
            _chewie = ChewieController(
              videoPlayerController: _video,
              autoPlay: true,
              allowFullScreen: true,
              allowMuting: true,
              showOptions: false,
              customControls: PremiumPlayerControls(
                title: widget.title,
                onRotate: _rotate,
              ),
              materialProgressColors: ChewieProgressColors(
                playedColor: AppColors.primary,
                handleColor: Colors.white,
                bufferedColor: const Color(0x66FFFFFF),
                backgroundColor: const Color(0x33FFFFFF),
              ),
            );
          });
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = "This video can't be played.");
        });
  }

  /// Trailer finished → invite the viewer to subscribe (once per playback).
  void _watchEnd() {
    final v = _video.value;
    final ended =
        v.isInitialized &&
        v.duration > Duration.zero &&
        !v.isPlaying &&
        v.position >= v.duration - const Duration(milliseconds: 400);
    if (!ended) {
      if (v.isPlaying) _endShown = false; // replayed: may show again
      return;
    }
    if (_endShown || !mounted) return;
    _endShown = true;
    _showSubscribe();
  }

  Future<void> _showSubscribe() async {
    if (_chewie?.isFullScreen ?? false) _chewie!.exitFullScreen();
    final navigator = Navigator.of(context);
    final guest = app.isGuest;
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(
          Icons.workspace_premium_rounded,
          color: AppColors.gold,
          size: 40,
        ),
        title: const Text('Enjoyed the trailer?'),
        content: Text(
          app.freeMode
              ? (guest
                    ? 'Log in to watch the full video for free.'
                    : 'Get full access to watch the full video.')
              : guest
              ? 'Please subscribe to watch the full content seamlessly. '
                    'Log in and choose a plan to continue.'
              : 'Please subscribe to watch the full content seamlessly.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              app.freeMode
                  ? (guest ? 'Log in' : 'Get full access')
                  : guest
                  ? 'Log in & subscribe'
                  : 'Subscribe now',
            ),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    _leaveFor(navigator, widget.onTrailerEnd!);
  }

  /// Close the player and continue on the screen below it.
  void _leaveFor(NavigatorState navigator, void Function(BuildContext) next) {
    final parent = navigator.context;
    navigator.pop();
    next(parent);
  }

  void _retry() {
    _chewie?.dispose();
    _video.dispose();
    setState(() {
      _chewie = null;
      _error = null;
    });
    _open();
  }

  @override
  void dispose() {
    _video.removeListener(_watchEnd);
    _chewie?.dispose();
    _video.dispose();
    ScreenRotation.reset();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _chewie != null && _error == null;
    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: widget.onWatchFull == null || (_landscape ?? false)
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "You're watching the trailer",
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppColors.gradient,
                        borderRadius: BorderRadius.circular(Radii.button),
                      ),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          minimumSize: const Size.fromHeight(52),
                        ),
                        icon: const Icon(Icons.workspace_premium_rounded),
                        label: const Text('Watch full video'),
                        onPressed: () {
                          final navigator = Navigator.of(context);
                          final parent = navigator.context;
                          navigator.pop();
                          widget.onWatchFull!(parent);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: _error != null
                  ? _PlayerMessage(
                      icon: Icons.error_outline_rounded,
                      text: _error!,
                      action: FilledButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    )
                  : !ready
                  ? const _PlayerMessage(loading: true, text: 'Loading video…')
                  // Full-screen surface: Chewie keeps the video's aspect
                  // ratio inside; controls and gestures cover the screen.
                  : Chewie(controller: _chewie!),
            ),
            // Before the controls exist, keep a way back + the title.
            if (!ready)
              Positioned(
                top: 4,
                left: 4,
                right: 12,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
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
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlayerMessage extends StatelessWidget {
  final IconData? icon;
  final String text;
  final bool loading;
  final Widget? action;
  const _PlayerMessage({
    required this.text,
    this.icon,
    this.loading = false,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(
              width: 46,
              height: 46,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.primary,
              ),
            )
          else if (icon != null)
            Icon(icon, color: AppColors.danger, size: 44),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14.5),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class ImageViewerScreen extends StatelessWidget {
  final String url;
  final String title;
  const ImageViewerScreen({super.key, required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: const Color(0x66000000),
        foregroundColor: Colors.white,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ),
      ),
      body: InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: NetThumb(url: url, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
