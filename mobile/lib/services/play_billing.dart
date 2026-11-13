import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Google Play "alternative billing only" — Play Store build only
/// (built with --flavor play --dart-define=PLAY_STORE=true). Before each UPI
/// payment Google shows its information screen and gives a one-time token;
/// the server reports the approved payment to Google with it. Other builds
/// never call this, so their payment flow is unchanged.
class PlayBilling {
  static const isPlayBuild = bool.fromEnvironment('PLAY_STORE');

  /// Owner's choice: the Play build also shows the plans and takes the same
  /// UPI payment as the shared APKs (--dart-define=PLAY_SELLS_UPI=true).
  static const sellsUpi = bool.fromEnvironment('PLAY_SELLS_UPI');

  /// Play build without plans (the default for a Play build).
  static const hidesPlans = isPlayBuild && !sellsUpi;
  static const _channel = MethodChannel('cloudstorage/playbilling');

  /// Returns the token, or throws [PlayBillingException].
  static Future<String> prepare() async {
    if (kIsWeb) {
      throw const PlayBillingException('error', 'Not available on web.');
    }
    final res = Map<String, dynamic>.from(
      await _channel.invokeMethod<Map>('prepare') ?? const {},
    );
    final status = res['status'] as String? ?? 'error';
    final token = res['token'] as String?;
    if (status == 'ok' && token != null && token.isNotEmpty) return token;
    throw PlayBillingException(status, res['message'] as String?);
  }
}

class PlayBillingException implements Exception {
  final String status; // unavailable | cancelled | error
  final String? detail;
  const PlayBillingException(this.status, [this.detail]);

  bool get cancelled => status == 'cancelled';

  @override
  String toString() => switch (status) {
    'unavailable' => 'Payments are not available in this version of the app yet. Please try again later.',
    'cancelled' => 'Payment cancelled.',
    _ => 'Could not start the payment. Please try again.',
  };
}
