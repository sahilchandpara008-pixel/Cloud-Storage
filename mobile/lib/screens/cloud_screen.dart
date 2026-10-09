import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models.dart';
import '../services/backend.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/gates.dart';
import '../widgets/reload.dart';
import 'player_screen.dart';

/// Personal cloud storage (premium). Free users see the upgrade prompt.
class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key});

  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends State<CloudScreen> with ContentReload {
  final List<CloudFile> _path = []; // folder breadcrumb
  List<CloudFile>? files;
  String? error;
  String? uploading;

  String? get _parentId => _path.isEmpty ? null : _path.last.id;

  @override
  Future<void> reload() async {
    if (!app.hasCloud) {
      if (mounted) setState(() => files = []);
      return;
    }
    try {
      final list = await Backend.cloudFiles(_parentId);
      if (mounted) {
        setState(() {
          files = list;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  void _open(CloudFile f) async {
    if (f.isFolder) {
      setState(() {
        _path.add(f);
        files = null;
      });
      reload();
      return;
    }
    try {
      final url = await Backend.cloudUrl(f.storageKey!);
      if (!mounted) return;
      if (f.isVideo) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlayerScreen(url: url, title: f.name),
          ),
        );
      } else if (f.isImage) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ImageViewerScreen(url: url, title: f.name),
          ),
        );
      } else {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }

  void _up() {
    setState(() {
      _path.removeLast();
      files = null;
    });
    reload();
  }

  /// No cloud yet: free mode / Play build asks guests to log in (free 15 GB);
  /// the shared APKs open the Premium plans as before.
  Future<void> _getCloud() async {
    if (!app.noPlans) {
      await openPlans(context);
      return;
    }
    if (await ensureLoggedIn(
      context,
      reason: 'Log in to get 15 GB of free cloud storage.',
    )) {
      await app.refreshStatus();
      await reload();
    }
  }

  Future<void> _add() async {
    if (!app.hasCloud) {
      await _getCloud();
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Upload files'),
              onTap: () => Navigator.pop(context, 'upload'),
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New folder'),
              onTap: () => Navigator.pop(context, 'folder'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'upload') await _upload();
    if (choice == 'folder') await _newFolder();
  }

  Future<void> _upload() async {
    final res = await FilePicker.pickFiles();
    if (res.isEmpty) return;
    var skipped = 0;
    final picked = <PlatformFile>[];
    for (final f in res) {
      if (await fileSize(f) <= Config.maxUploadBytes) {
        picked.add(f);
      } else {
        skipped++;
      }
    }
    for (var i = 0; i < picked.length; i++) {
      final f = picked[i];
      setState(
        () => uploading = 'Uploading ${i + 1} of ${picked.length}: ${f.name}',
      );
      try {
        await Backend.uploadCloudFile(
          _parentId,
          f.name,
          await f.readAsBytes(),
          _mimeFor(f.extension),
        );
      } catch (e) {
        if (mounted) showSnack(context, '${f.name}: ${friendlyError(e)}');
      }
    }
    setState(() => uploading = null);
    if (skipped > 0 && mounted) {
      showSnack(context, '$skipped file(s) skipped: larger than 50 MB.');
    }
    await reload();
    await app.refreshStatus();
  }

  String? _mimeFor(String? ext) {
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'heic': 'image/heic',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'mkv': 'video/x-matroska',
      'webm': 'video/webm',
      'mp3': 'audio/mpeg',
      'm4a': 'audio/mp4',
      'pdf': 'application/pdf',
      'txt': 'text/plain',
      'zip': 'application/zip',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'apk': 'application/vnd.android.package-archive',
    };
    return map[(ext ?? '').toLowerCase()] ?? 'application/octet-stream';
  }

  Future<String?> _askName(String title, {String initial = ''}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _newFolder() async {
    final name = await _askName('New folder');
    if (name == null || name.isEmpty) return;
    try {
      await Backend.createFolder(_parentId, name);
      await reload();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }

  Future<void> _menu(CloudFile f) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                f.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (!f.isFolder)
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text('Download to phone'),
                onTap: () => Navigator.pop(context, 'download'),
              ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: AppColors.primary,
              ),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'download') {
      if (mounted) await downloadCloudFile(context, f);
      return;
    }
    try {
      if (action == 'rename') {
        final name = await _askName('Rename', initial: f.name);
        if (name == null || name.isEmpty) return;
        await Backend.renameCloudFile(f.id, name);
      } else if (action == 'delete') {
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('Delete ${f.isFolder ? 'folder' : 'file'}?'),
            content: Text(
              f.isFolder
                  ? '"${f.name}" and everything inside it will be deleted.'
                  : '"${f.name}" will be deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (ok != true) return;
        await Backend.deleteCloudFile(f);
        await app.refreshStatus();
      } else {
        return;
      }
      await reload();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }

  IconData _icon(CloudFile f) {
    if (f.isFolder) return Icons.folder;
    if (f.isImage) return Icons.image_outlined;
    if (f.isVideo) return Icons.movie_outlined;
    if ((f.mime ?? '').startsWith('audio/')) return Icons.music_note_outlined;
    if (f.mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final premium = app.hasCloud;
        return PopScope(
          canPop: _path.isEmpty,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _path.isNotEmpty) _up();
          },
          child: Scaffold(
            appBar: AppBar(
              flexibleSpace: const DecoratedBox(
                decoration: BoxDecoration(gradient: AppColors.barGradient),
                child: SizedBox.expand(),
              ),
              leading: _path.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: _up,
                    ),
              title: Text(_path.isEmpty ? 'Cloud Storage' : _path.last.name),
              actions: [
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'Storage',
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Your storage'),
                      content: Text(
                        premium
                            ? 'Used ${formatBytes(app.status!.usedBytes)} of ${formatBytes(app.status!.quotaBytes)}.'
                            : app.noPlans
                            ? 'Log in to get 15 GB of free cloud storage for your photos, videos and files.'
                            : 'Get a Premium plan to store your photos, videos and files (2 TB).',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ),
                ),
                const CrownButton(),
              ],
            ),
            floatingActionButton: FloatingActionButton(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              tooltip: 'Add',
              onPressed: uploading == null ? _add : null,
              child: const Icon(Icons.add_rounded, size: 30),
            ),
            body: Column(
              children: [
                if (premium && app.status != null)
                  _StorageMeter(
                    used: app.status!.usedBytes,
                    quota: app.status!.quotaBytes,
                  ),
                if (uploading != null) ...[
                  const LinearProgressIndicator(),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(uploading!, overflow: TextOverflow.ellipsis),
                  ),
                ],
                Expanded(child: _body(premium)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _body(bool premium) {
    if (!premium) {
      if (app.noPlans) {
        return EmptyState(
          message: 'Store your photos, videos and files safely.\nLog in to get 15 GB of free cloud storage.',
          action: FilledButton(
            onPressed: _getCloud,
            child: const Text('Log in'),
          ),
        );
      }
      return EmptyState(
        message: 'Store your photos, videos and files safely.\nGet Premium for 2 TB of cloud storage.',
        action: FilledButton(
          onPressed: () => openPlans(context),
          child: const Text('Get Premium'),
        ),
      );
    }
    if (error != null && files == null) {
      return ErrorRetry(message: error!, onRetry: reload);
    }
    if (files == null) return const Center(child: CircularProgressIndicator());
    if (files!.isEmpty) {
      return const EmptyState(
        message: 'No Record Found\nTap + to upload your first file.',
      );
    }
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: files!.length,
        separatorBuilder: (_, _) => const SizedBox(height: 2),
        itemBuilder: (context, i) {
          final f = files![i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: f.isFolder
                    ? AppColors.warningBg
                    : const Color(0xFF2A1A10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _icon(f),
                color: f.isFolder ? AppColors.warning : AppColors.primary,
              ),
            ),
            title: Text(
              f.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              f.isFolder
                  ? 'Folder'
                  : '${formatBytes(f.size)} · ${timeAgo(f.createdAt)}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.more_vert, color: AppColors.muted),
              onPressed: () => _menu(f),
            ),
            onTap: () => _open(f),
            onLongPress: () => _menu(f),
          );
        },
      ),
    );
  }
}

class _StorageMeter extends StatelessWidget {
  final int used;
  final int quota;
  const _StorageMeter({required this.used, required this.quota});

  @override
  Widget build(BuildContext context) {
    final fraction = quota == 0 ? 0.0 : (used / quota).clamp(0.0, 1.0);
    final shown = fraction < 0.01 && used > 0 ? 0.01 : fraction;
    final pct = (fraction * 100).round();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Storage Used',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatBytes(used)} of ${formatBytes(quota)} used',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: shown,
                    minHeight: 6,
                    color: AppColors.primary,
                    backgroundColor: AppColors.surfaceHigh,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 58,
            height: 58,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: shown,
                  strokeWidth: 5,
                  strokeCap: StrokeCap.round,
                  color: AppColors.primary,
                  backgroundColor: AppColors.surfaceHigh,
                ),
                Center(
                  child: Text(
                    '$pct%',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
