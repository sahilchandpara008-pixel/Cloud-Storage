import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/channel_screen.dart';
import '../screens/post_screen.dart';
import '../screens/premium_screen.dart';
import 'backend.dart';

/// Push notifications (Firebase Cloud Messaging), Android only.
///
/// * Registers this phone's push token with our server (again when the token
///   changes or a different account logs in). Whether a phone gets messages
///   is decided on the server from the user's notification answer.
/// * The permission question itself is asked by NotifyPermission (once, right
///   after the 18+ consent); nothing here asks.
/// * A tapped message opens what it points to (a video, a channel, the
///   Premium page or a link) and is reported once for the admin's "Tapped".
/// * While the app is open, Android shows nothing, so a small bar with an
///   "Open" button is shown at the bottom instead.
/// Never blocks or breaks the app.
class Push {
  static final navigatorKey = GlobalKey<NavigatorState>();
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  static bool _ready = false;
  static bool _listening = false;
  static String? _installId;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static Future<bool> _init() async {
    if (!_supported) return false;
    if (_ready) return true;
    try {
      await Firebase.initializeApp();
      _ready = true;
    } catch (_) {}
    return _ready;
  }

  /// App start, after login and after the permission answer: sends the token
  /// when it (or the logged-in account) changed.
  static Future<void> register(
    SharedPreferences prefs,
    String installId,
  ) async {
    _installId = installId;
    if (!await _init()) return;
    try {
      final m = FirebaseMessaging.instance;
      if (!_listening) {
        _listening = true;
        // Registration tokens (not the newer installation IDs): what the
        // server's FCM HTTP v1 "token" target expects.
        // ignore: deprecated_member_use
        m.onTokenRefresh.listen((t) => _send(prefs, installId, t));
        FirebaseMessaging.onMessageOpenedApp.listen(_open);
        FirebaseMessaging.onMessage.listen(_foreground);
      }
      // ignore: deprecated_member_use
      final token = await m.getToken();
      if (token != null) await _send(prefs, installId, token);
    } catch (_) {
      // Tried again on the next app start.
    }
  }

  static Future<void> _send(
    SharedPreferences prefs,
    String installId,
    String token,
  ) async {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    final key = '$token|$uid';
    if (prefs.getString('push_token_sent') == key) return;
    await Backend.registerPushToken(installId, token);
    await prefs.setString('push_token_sent', key);
  }

  /// The message that opened the app from closed, if any. Called by the home
  /// screen once start-up and the consent dialog are done.
  static Future<void> openInitialMessage() async {
    if (!await _init()) return;
    try {
      final msg = await FirebaseMessaging.instance.getInitialMessage();
      if (msg != null) _open(msg);
    } catch (_) {}
  }

  static void _foreground(RemoteMessage msg) {
    final n = msg.notification;
    final title = n?.title ?? '';
    if (title.isEmpty) return;
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          n?.body?.isNotEmpty == true ? '$title\n${n!.body}' : title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        duration: const Duration(seconds: 6),
        action: _hasTarget(msg.data)
            ? SnackBarAction(label: 'Open', onPressed: () => _open(msg))
            : null,
      ),
    );
  }

  static bool _hasTarget(Map<String, dynamic> d) =>
      ['post', 'channel', 'premium', 'url'].contains(d['type']);

  static void _open(RemoteMessage msg) {
    final d = msg.data;
    final mid = d['mid'] as String?;
    if (mid != null && _installId != null) {
      unawaited(Backend.pushOpened(mid, _installId!).catchError((Object _) {}));
    }
    final nav = navigatorKey.currentState;
    final id = (d['id'] as String?) ?? '';
    switch (d['type']) {
      case 'post' when id.isNotEmpty:
        nav?.push(MaterialPageRoute(builder: (_) => PostScreen(postId: id)));
      case 'channel' when id.isNotEmpty:
        nav?.push(
          MaterialPageRoute(builder: (_) => ChannelScreen(channelId: id)),
        );
      case 'premium':
        nav?.push(
          MaterialPageRoute(
            builder: (_) => const PremiumScreen(standalone: true),
          ),
        );
      case 'url':
        final uri = Uri.tryParse((d['url'] as String?) ?? '');
        if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
          unawaited(
            launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
            ).catchError((Object _) => false),
          );
        }
    }
  }
}
