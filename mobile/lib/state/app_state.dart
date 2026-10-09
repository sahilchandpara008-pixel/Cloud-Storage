import 'dart:async';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../models.dart';
import '../services/backend.dart';
import '../services/blocks.dart';
import '../services/payments.dart';
import '../services/play_billing.dart';

/// App-wide state: the session (guest or logged in), install attribution,
/// consent, and the user's status (premium, source, storage).
class AppState extends ChangeNotifier {
  AppState._();
  static final instance = AppState._();

  late SharedPreferences _prefs;
  StreamSubscription<AuthState>? _authSub;

  bool ready = false;
  String? startupError;
  UserStatus? status;
  late String installId;

  /// Bumped whenever what the user may see changes (login, logout, source
  /// recorded, plan granted). Screens reload their data when it changes.
  final contentVersion = ValueNotifier<int>(0);

  /// Set when the user opened a password-reset link; the UI asks for a new
  /// password.
  final passwordRecovery = ValueNotifier<bool>(false);

  /// Deep link that brings Google login and password-reset links back to the app.
  static const authRedirect = 'com.cloudstorage.app://login-callback';

  /// Selected bottom tab: 0 Cloud, 1 Feed, 2 Explore, 3 Channels, 4 Profile.
  final tab = ValueNotifier<int>(2);

  bool get isGuest => status?.isGuest ?? true;
  bool get isPremium => status?.isPremium ?? false;
  bool get hasAdsAccess => status?.hasAdsAccess ?? false;

  /// Free mode (set on the server): no plans, everyone logged in gets 15 GB,
  /// full access for ads users and approved organic users.
  bool get freeMode => status?.freeMode ?? false;

  /// No plans or payments in the app: free mode, or the Google Play build.
  bool get noPlans => freeMode || PlayBilling.isPlayBuild;

  /// Cloud storage: Premium, or the free 15 GB (free mode / Play build).
  bool get hasCloud => isPremium || (status?.quotaBytes ?? 0) > 0;

  /// Free mode: organic user asks for full access (admin → Approvals).
  Future<void> requestFullAccess() async {
    await Backend.requestFullAccess();
    await refreshStatus();
  }

  bool get consentGiven => _prefs.getString('consent') == Config.policyVersion;
  String? get email => sb.auth.currentUser?.email;
  String? get userId => sb.auth.currentUser?.id;

  Future<void> start() async {
    startupError = null;
    notifyListeners();
    try {
      _prefs = await SharedPreferences.getInstance();
      await Blocks.load();
      installId = _prefs.getString('install_id') ?? const Uuid().v4();
      await _prefs.setString('install_id', installId);

      // Everyone starts as a guest: create an anonymous account once.
      if (sb.auth.currentSession == null) {
        await sb.auth.signInAnonymously();
      }
      await _recordInstall();
      await refreshStatus();
      Backend.logEvent(installId, 'app_open');

      _authSub ??= sb.auth.onAuthStateChange.listen((s) async {
        if (s.event == AuthChangeEvent.passwordRecovery) {
          passwordRecovery.value = true;
        }
        if (s.event == AuthChangeEvent.signedIn ||
            s.event == AuthChangeEvent.userUpdated) {
          await refreshStatus();
          bumpContent();
        }
      });
      ready = true;
      // Saved UPI answers (also from before a crash/kill) are sent now.
      payments.start();
    } catch (e) {
      startupError = friendlyError(e);
    }
    notifyListeners();
  }

  /// Ads APK carries APK_REFERRER; the plain APK has none ("direct").
  Future<void> _recordInstall() async {
    if (_prefs.getBool('install_recorded') == true) return;
    final hasReferrer = Config.apkReferrer.isNotEmpty;
    final source = await Backend.recordInstall(
      installId,
      hasReferrer ? 'apk' : 'not_available',
      hasReferrer ? Config.apkReferrer : null,
    );
    await _prefs.setBool('install_recorded', true);
    await _prefs.setString('install_source', source ?? 'unknown');
  }

  Future<void> refreshStatus() async {
    try {
      var s = await Backend.status();
      // Google Play build: logged-in users get 15 GB of free cloud storage.
      if (PlayBilling.isPlayBuild &&
          s != null &&
          !s.isGuest &&
          !s.isPremium &&
          s.quotaBytes == 0) {
        await Backend.enablePlayFreeCloud();
        s = await Backend.status();
      }
      final changed =
          s?.isPremium != status?.isPremium ||
          s?.source != status?.source ||
          s?.isGuest != status?.isGuest ||
          s?.quotaBytes != status?.quotaBytes ||
          s?.freeMode != status?.freeMode;
      status = s;
      notifyListeners();
      if (changed && ready) bumpContent();
    } catch (_) {
      // Keep the last known status when offline.
    }
  }

  void bumpContent() => contentVersion.value++;

  Future<void> acceptConsent() async {
    await _prefs.setString('consent', Config.policyVersion);
    notifyListeners();
    try {
      await Backend.saveConsent(Config.policyVersion);
    } catch (_) {}
  }

  /// Guest → full account with the same user id (keeps everything).
  /// Returns false when the email must be confirmed first.
  Future<bool> createAccount(String email, String password) async {
    final res = await sb.auth.updateUser(
      UserAttributes(email: email, password: password),
      // If email confirmation is on, the link in the email opens the app.
      emailRedirectTo: kIsWeb ? null : authRedirect,
    );
    await refreshStatus();
    bumpContent();
    return res.user?.email == email;
  }

  Future<void> logIn(String email, String password) async {
    await sb.auth.signInWithPassword(email: email, password: password);
    try {
      await Backend.attributeUser(installId);
    } catch (_) {}
    Backend.logEvent(installId, 'login');
    await refreshStatus();
    bumpContent();
  }

  /// Google login in the browser. The session comes back through the
  /// [authRedirect] deep link (handled by supabase_flutter); the login screen
  /// then calls [afterExternalLogin].
  Future<void> signInWithGoogle() async {
    if (!await _providerEnabled('google')) {
      throw StateError(
        'Google sign-in is coming soon. Please log in with email.',
      );
    }
    await sb.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : authRedirect,
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
  }

  Future<void> afterExternalLogin() async {
    try {
      await Backend.attributeUser(installId);
    } catch (_) {}
    Backend.logEvent(installId, 'login');
    await refreshStatus();
    bumpContent();
  }

  Future<void> sendPasswordReset(String email) => sb.auth.resetPasswordForEmail(
    email,
    redirectTo: kIsWeb ? null : authRedirect,
  );

  Future<bool> _providerEnabled(String provider) async {
    try {
      final res = await http
          .get(
            Uri.parse('${Config.supabaseUrl}/auth/v1/settings'),
            headers: {'apikey': Config.supabaseKey},
          )
          .timeout(const Duration(seconds: 10));
      final external = (jsonDecode(res.body) as Map)['external'] as Map?;
      return external?[provider] == true;
    } catch (_) {
      return true; // can't tell (offline?): let the browser show the result
    }
  }

  /// Logging out (or deleting the account) starts a fresh guest session.
  Future<void> logOut() async {
    await sb.auth.signOut();
    await sb.auth.signInAnonymously();
    try {
      await Backend.attributeUser(installId);
    } catch (_) {}
    await refreshStatus();
    bumpContent();
  }

  Future<void> updateName(String name) async {
    await Backend.updateName(name);
    await refreshStatus();
  }

  Future<void> deleteAccount() async {
    await Backend.deleteAccount();
    await logOut();
  }
}

AppState get app => AppState.instance;
