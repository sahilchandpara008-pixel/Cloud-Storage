import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';

/// Notification permission. Asked once, right after the 18+ consent (ads and
/// organic users alike; also once for people who agreed in an older version).
/// Android 13+ shows its own Allow / Don't allow question; older Android
/// allows notifications unless the user turned them off.
/// The answer (and later changes made in the phone's Settings) is reported
/// to the server for the admin panel's allowed / not allowed numbers.
/// Never blocks or breaks the app.
class NotifyPermission {
  static const _ch = MethodChannel('cloudstorage/notify');
  static const _askedKey = 'notif_asked';
  static const _sentKey = 'notif_sent';

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Shows Android's question the first time; afterwards only reports the
  /// current setting if it changed.
  static Future<void> askOnce(SharedPreferences prefs, String installId) async {
    if (!_supported) return;
    try {
      String? status;
      if (prefs.getBool(_askedKey) != true) {
        await prefs.setBool(_askedKey, true);
        status = await _ch.invokeMethod<String>('request');
      }
      await _report(prefs, installId, status);
    } catch (_) {}
  }

  /// Every app start: report the setting if the user changed it in Settings.
  static Future<void> sync(SharedPreferences prefs, String installId) async {
    if (!_supported || prefs.getBool(_askedKey) != true) return;
    try {
      await _report(prefs, installId, null);
    } catch (_) {}
  }

  static Future<void> _report(
    SharedPreferences prefs,
    String installId,
    String? status,
  ) async {
    final s = status ?? await _ch.invokeMethod<String>('status');
    if (s != 'allowed' && s != 'denied') return;
    if (prefs.getString(_sentKey) == s) return;
    await Backend.recordNotifStatus(installId, s!);
    await prefs.setString(_sentKey, s);
  }
}
