import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';

import '../config.dart';
import '../models.dart';
import '../services/backend.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Creator posts videos/images to their approved channel.
class NewPostScreen extends StatefulWidget {
  final String channelId;
  final String channelName;
  const NewPostScreen({
    super.key,
    required this.channelId,
    required this.channelName,
  });

  @override
  State<NewPostScreen> createState() => _NewPostScreenState();
}

class _Picked {
  PlatformFile file;
  final bool isVideo;
  Uint8List? thumbnail;
  bool customThumb = false;
  PlatformFile?
  trailer; // optional short clip shown to ads users before they buy
  _Picked(this.file, this.isVideo);
}

class _NewPostScreenState extends State<NewPostScreen> {
  final _title = TextEditingController();
  final _caption = TextEditingController();
  final List<_Picked> _files = [];
  List<Folder> _folders = [];
  String? _folderId;
  bool _posting = false;
  String? _progress;

  static const _videoExt = {'mp4', 'mov', 'm4v', 'webm', '3gp', 'mkv'};

  @override
  void initState() {
    super.initState();
    Backend.folders(widget.channelId).then((f) {
      if (mounted) setState(() => _folders = f);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick(FileType type) async {
    final res = await FilePicker.pickFiles(type: type);
    if (res.isEmpty) return;
    var tooBig = 0;
    for (final f in res) {
      final size = await fileSize(f);
      if (size > Config.maxUploadBytes) {
        tooBig++;
        continue;
      }
      final picked = _Picked(
        f,
        _videoExt.contains((f.extension ?? '').toLowerCase()),
      );
      // Images double as their own thumbnail (public bucket allows up to 10 MB).
      picked.thumbnail = picked.isVideo
          ? await _videoThumb(f)
          : (size <= 9 * 1024 * 1024 ? await f.readAsBytes() : null);
      _files.add(picked);
    }
    setState(() {});
    if (tooBig > 0 && mounted) {
      showSnack(context, '$tooBig file(s) skipped: larger than 50 MB.');
    }
  }

  /// Replace the automatic thumbnail with the creator's own image.
  Future<void> _pickThumbnail(_Picked p) async {
    final f = await FilePicker.pickFile(type: FileType.image);
    if (f == null) return;
    if (await fileSize(f) > 9 * 1024 * 1024) {
      if (mounted) showSnack(context, 'Thumbnail must be under 9 MB.');
      return;
    }
    final bytes = await f.readAsBytes();
    setState(() {
      p.thumbnail = bytes;
      p.customThumb = true;
    });
  }

  /// Replace the main video of an item.
  Future<void> _replaceMain(_Picked p) async {
    final f = await FilePicker.pickFile(type: FileType.video);
    if (f == null) return;
    if (await fileSize(f) > Config.maxUploadBytes) {
      if (mounted) showSnack(context, 'Video must be under 50 MB.');
      return;
    }
    final thumb = p.customThumb ? p.thumbnail : await _videoThumb(f);
    setState(() {
      p.file = f;
      p.thumbnail = thumb;
    });
  }

  Future<Uint8List?> _videoThumb(PlatformFile f) async {
    if (kIsWeb) return null;
    try {
      final usePath = f.path != null;
      return await FcNativeVideoThumbnail().saveThumbnailToBytes(
        srcFile: usePath ? f.path! : f.uri.toString(),
        srcFileUri: !usePath,
        width: 480,
        height: 480,
        format: 'jpeg',
        quality: 75,
      );
    } catch (_) {
      return null; // The post still works without a thumbnail.
    }
  }

  Future<void> _pickTrailer(_Picked p) async {
    final f = await FilePicker.pickFile(type: FileType.video);
    if (f == null) return;
    if (await fileSize(f) > Config.maxUploadBytes) {
      if (mounted) showSnack(context, 'Trailer must be under 50 MB.');
      return;
    }
    setState(() => p.trailer = f);
  }

  Future<void> _newFolder() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Folder name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final folder = await Backend.createChannelFolder(
        widget.channelId,
        name,
        _folders.length,
      );
      setState(() {
        _folders = [..._folders, folder];
        _folderId = folder.id;
      });
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }

  String _mime(PlatformFile f, bool isVideo) {
    final ext = (f.extension ?? '').toLowerCase();
    if (isVideo) {
      return ext == 'webm'
          ? 'video/webm'
          : (ext == 'mov' ? 'video/quicktime' : 'video/mp4');
    }
    return ext == 'png'
        ? 'image/png'
        : (ext == 'webp'
              ? 'image/webp'
              : (ext == 'gif' ? 'image/gif' : 'image/jpeg'));
  }

  Future<void> _post() async {
    if (_title.text.trim().isEmpty) {
      showSnack(context, 'Add a title.');
      return;
    }
    if (_files.isEmpty) {
      showSnack(context, 'Add at least one video or image.');
      return;
    }
    final noTrailer = _files
        .where((f) => f.isVideo && f.trailer == null)
        .length;
    if (noTrailer > 0) {
      final go = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Add a trailer?'),
          content: Text(
            app.freeMode
                ? '$noTrailer video(s) have no trailer. Users from ads can '
                      'watch a trailer before they log in.'
                : '$noTrailer video(s) have no trailer. Users from ads can watch '
                      'trailers for free; without one they only see the plans.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Post anyway'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Add trailer'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    setState(() => _posting = true);
    try {
      final postId = await Backend.createPost(
        widget.channelId,
        _title.text.trim(),
        _caption.text.trim().isEmpty ? null : _caption.text.trim(),
        folderId: _folderId,
      );
      for (var i = 0; i < _files.length; i++) {
        setState(() => _progress = 'Uploading ${i + 1} of ${_files.length}…');
        final p = _files[i];
        await Backend.addPostItem(
          postId: postId,
          position: i,
          kind: p.isVideo ? 'video' : 'image',
          bytes: await p.file.readAsBytes(),
          ext: (p.file.extension ?? (p.isVideo ? 'mp4' : 'jpg')).toLowerCase(),
          mime: _mime(p.file, p.isVideo),
          thumbnail: p.thumbnail,
          trailerBytes: p.trailer == null
              ? null
              : await p.trailer!.readAsBytes(),
          trailerExt: p.trailer?.extension?.toLowerCase(),
          trailerMime: p.trailer == null ? null : _mime(p.trailer!, true),
        );
      }
      if (!mounted) return;
      showSnack(context, 'Posted to ${widget.channelName}');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) {
        setState(() {
          _posting = false;
          _progress = null;
        });
      }
    }
  }

  Widget _itemCard(int index, _Picked p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                p.isVideo ? Icons.movie_outlined : Icons.image_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${p.isVideo ? 'Video' : 'Image'} ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close, size: 20, color: AppColors.muted),
                onPressed: _posting
                    ? null
                    : () => setState(() => _files.remove(p)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Slot(
                    label: 'Thumbnail',
                    done: p.thumbnail != null,
                    hint: p.isVideo
                        ? (p.customThumb ? 'Custom' : 'Auto · tap to change')
                        : 'From image',
                    preview: p.thumbnail,
                    icon: Icons.image_outlined,
                    onTap: _posting || !p.isVideo
                        ? null
                        : () => _pickThumbnail(p),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Slot(
                    label: p.isVideo ? 'Main video' : 'Image',
                    done: true,
                    hint: p.file.name,
                    icon: p.isVideo
                        ? Icons.movie_outlined
                        : Icons.image_outlined,
                    onTap: _posting || !p.isVideo
                        ? null
                        : () => _replaceMain(p),
                  ),
                ),
                if (p.isVideo) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Slot(
                      label: 'Trailer',
                      done: p.trailer != null,
                      hint: p.trailer?.name ?? 'Tap to add',
                      icon: Icons.play_circle_outline,
                      highlight: p.trailer == null,
                      onTap: _posting ? null : () => _pickTrailer(p),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.barGradient),
          child: SizedBox.expand(),
        ),
        title: const Text('New post'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
            maxLength: 120,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _caption,
            decoration: const InputDecoration(
              labelText: 'Caption (emojis and #hashtags welcome)',
            ),
            maxLines: 3,
            maxLength: 1000,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _folderId,
                  decoration: const InputDecoration(labelText: 'Folder'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('No folder'),
                    ),
                    for (final f in _folders)
                      DropdownMenuItem(value: f.id, child: Text(f.name)),
                  ],
                  onChanged: (v) => setState(() => _folderId = v),
                ),
              ),
              IconButton(
                tooltip: 'New folder',
                icon: const Icon(Icons.create_new_folder_outlined),
                onPressed: _newFolder,
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < _files.length; i++) _itemCard(i, _files[i]),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _posting ? null : () => _pick(FileType.video),
                  icon: const Icon(Icons.video_call_outlined),
                  label: const Text('Add video'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _posting ? null : () => _pick(FileType.image),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Add image'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Each video: thumbnail (optional, auto-made if empty), main video '
            'and a short trailer. Ads users can watch the trailer for free; '
            'the full video needs a plan. Files up to 50 MB.',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _posting ? null : _post,
            child: Text(_progress ?? (_posting ? 'Posting…' : 'Post')),
          ),
        ],
      ),
    );
  }
}

/// One upload slot (thumbnail / main video / trailer).
class _Slot extends StatelessWidget {
  final String label;
  final String hint;
  final bool done;
  final bool highlight;
  final IconData icon;
  final Uint8List? preview;
  final VoidCallback? onTap;
  const _Slot({
    required this.label,
    required this.hint,
    required this.done,
    required this.icon,
    this.preview,
    this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: highlight ? AppColors.primary : AppColors.border,
                  width: highlight ? 1.4 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: preview != null
                  ? Image.memory(preview!, fit: BoxFit.cover)
                  : Icon(
                      done
                          ? Icons.check_circle
                          : (onTap == null ? icon : Icons.add),
                      color: done
                          ? AppColors.success
                          : (highlight ? AppColors.primary : AppColors.muted),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (done)
                const Padding(
                  padding: EdgeInsets.only(right: 3),
                  child: Icon(Icons.check, size: 13, color: AppColors.success),
                ),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
