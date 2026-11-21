import 'dart:io' show Platform;

import 'package:advertising_id/advertising_id.dart';
import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';

/// Meta ad measurement. The Meta SDK itself reports installs and app opens.
/// This sends our server the two IDs Meta needs to match the app's other
/// events (sign-up, checkout, purchase) to the same phone:
///  * the SDK's anonymous install ID, and
///  * the phone's advertising ID, only when the user has NOT turned off ad
///    personalisation.
/// Sent once, and again only if one of them changes. Never blocks or breaks
/// the app.
class MetaIds {
  static const _zeroId = '00000000-0000-0000-0000-000000000000';

  static Future<void> sync(SharedPreferences prefs, String installId) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final anonId = await FacebookAppEvents().getAnonymousId();
      String? adId;
      try {
        final limited = await AdvertisingId.isLimitAdTrackingEnabled ?? true;
        if (!limited) {
          final id = await AdvertisingId.id(false);
          if (id != null && id.isNotEmpty && id != _zeroId) adId = id;
        }
      } catch (_) {
        // No Google Play services: no advertising ID.
      }
      final key = '${anonId ?? ''}|${adId ?? ''}';
      if (prefs.getString('meta_ids_sent') == key) return;
      await Backend.recordAdIds(installId, anonId: anonId, adId: adId);
      await prefs.setString('meta_ids_sent', key);
    } catch (_) {
      // Measurement must never break the app; tried again next launch.
    }
  }
}
