import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

import '../services/backend.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../theme.dart';
import 'policy_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  String? _version;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = 'Version ${info.version} (${info.buildNumber})');
      }
    });
  }

  Future<void> _logout() async {
    setState(() => _busy = true);
    try {
      await app.logOut();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account, your cloud files and your channel memberships. This can\'t be undone.',
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
    setState(() => _busy = true);
    try {
      await app.deleteAccount();
      if (!mounted) return;
      showSnack(context, 'Your account was deleted.');
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    void open(String key) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PolicyScreen(policyKey: key)));
    final registered = !app.isGuest;
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.barGradient),
          child: SizedBox.expand(),
        ),
        title: const Text('App Setting'),
      ),
      body: Column(
        children: [
          for (final (key, title) in const [
            ('privacy', 'Privacy Policy'),
            ('terms', 'Terms & Conditions'),
            ('community', 'Community Guidelines'),
            ('refund', 'Refund Policy'),
          ])
            ListTile(
              title: Text(title, style: const TextStyle(fontSize: 17)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => open(key),
            ),
          ListTile(
            title: const Text(
              'Contact support',
              style: TextStyle(fontSize: 17),
            ),
            subtitle: const Text(Config.supportEmail),
            trailing: const Icon(Icons.mail_outline),
            onTap: () => launchUrl(
              Uri(
                scheme: 'mailto',
                path: Config.supportEmail,
                query:
                    'subject=${Uri.encodeComponent('${Config.appName} support')}',
              ),
            ),
          ),
          const Spacer(),
          if (_version != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _version!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          if (registered)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _logout,
                        child: const Text('Logout'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: Color(0x66FF5A67)),
                          minimumSize: const Size(0, 52),
                        ),
                        onPressed: _busy ? null : _delete,
                        child: const Text('Delete Account'),
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
}
