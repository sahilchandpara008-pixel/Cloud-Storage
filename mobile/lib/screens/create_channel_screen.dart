import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/backend.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Create a channel. It's sent to the owner for approval; the owner also
/// decides who can see it.
class CreateChannelScreen extends StatefulWidget {
  const CreateChannelScreen({super.key});

  @override
  State<CreateChannelScreen> createState() => _CreateChannelScreenState();
}

class _CreateChannelScreenState extends State<CreateChannelScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _category = TextEditingController();
  Uint8List? _icon;
  String _iconExt = 'jpg';
  String _iconMime = 'image/jpeg';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    final f = await FilePicker.pickFile(type: FileType.image);
    if (f == null) return;
    if (await fileSize(f) > 5 * 1024 * 1024) {
      if (mounted) showSnack(context, 'Please choose an image under 5 MB.');
      return;
    }
    final bytes = await f.readAsBytes();
    setState(() {
      _icon = bytes;
      _iconExt = (f.extension ?? 'jpg').toLowerCase();
      _iconMime = _iconExt == 'png'
          ? 'image/png'
          : (_iconExt == 'webp' ? 'image/webp' : 'image/jpeg');
    });
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      String? iconUrl;
      if (_icon != null) {
        iconUrl = await Backend.uploadChannelIcon(_icon!, _iconExt, _iconMime);
      }
      await Backend.createChannel(
        name: _name.text.trim(),
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        category: _category.text.trim().isEmpty ? null : _category.text.trim(),
        iconUrl: iconUrl,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Request sent'),
          content: const Text(
            'Your channel has been sent for approval. You\'ll find it under Profile → My Channels. '
            'Once it\'s approved, you can start posting.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.barGradient),
          child: SizedBox.expand(),
        ),
        title: const Text('Create channel'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickIcon,
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: AppColors.bubble,
                  backgroundImage: _icon == null ? null : MemoryImage(_icon!),
                  child: _icon == null
                      ? const Icon(
                          Icons.add_a_photo_outlined,
                          color: AppColors.primary,
                          size: 32,
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Channel picture',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Channel name'),
              textCapitalization: TextCapitalization.words,
              maxLength: 60,
              validator: (v) => (v == null || v.trim().length < 3)
                  ? 'At least 3 characters'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _category,
              decoration: const InputDecoration(
                labelText: 'Category (e.g. Entertainment)',
              ),
              maxLength: 40,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
              maxLength: 300,
            ),
            const SizedBox(height: 8),
            const Text(
              'New channels are reviewed before they appear in the app.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}
