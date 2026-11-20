import 'package:flutter/material.dart';

import '../config.dart';
import '../services/payments.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'channels_screen.dart';
import 'cloud_screen.dart';
import 'explore_screen.dart';
import 'feed_screen.dart';
import 'login_screen.dart';
import 'payment_status_screen.dart';
import 'policy_screen.dart';
import 'premium_screen.dart';

/// Bottom navigation: Cloud · Feed · Explore (default) · Channels · Profile.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  /// The app opens on Explore every time -- for ads and organic users alike.
  /// A cold start already does (app.tab starts at Explore); this also covers
  /// coming back from the background. Short trips away (file picker, UPI
  /// payment app, share sheet) keep the current tab, so those flows aren't
  /// interrupted. Screens open on top (player, payment status) stay open.
  static const _exploreTab = 2;
  static const _awayBeforeReset = Duration(minutes: 1);
  DateTime? _backgroundedAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = _backgroundedAt;
      _backgroundedAt = null;
      if (away != null && DateTime.now().difference(away) >= _awayBeforeReset) {
        _goToExplore();
      }
    }
  }

  /// Not while a UPI payment is still open: paying can take more than a
  /// minute and the person must come back to it, not to Explore.
  Future<void> _goToExplore() async {
    if (await payments.hasUnfinishedPayment()) return;
    if (mounted) app.tab.value = _exploreTab;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _maybeAskConsent();
      await _resumePayment();
    });
    app.passwordRecovery.addListener(_onPasswordRecovery);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    app.passwordRecovery.removeListener(_onPasswordRecovery);
    super.dispose();
  }

  /// Opened a password-reset link from the email: ask for the new password.
  Future<void> _onPasswordRecovery() async {
    if (!app.passwordRecovery.value || !mounted) return;
    app.passwordRecovery.value = false;
    await showNewPasswordDialog(context);
  }

  /// The app was closed or killed while the UPI app was open: show the
  /// payment's status again (the saved answer is being sent meanwhile).
  Future<void> _resumePayment() async {
    if (!await payments.hasUnfinishedPayment()) return;
    final order = await payments.openOrder();
    if (order == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PaymentStatusScreen(order: order)),
    );
  }

  Future<void> _maybeAskConsent() async {
    if (app.consentGiven || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ConsentDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: app.tab,
      builder: (context, index, _) => Scaffold(
        body: IndexedStack(
          index: index,
          children: const [
            CloudScreen(),
            FeedScreen(),
            ExploreScreen(),
            ChannelsScreen(),
            PremiumScreen(),
          ],
        ),
        bottomNavigationBar: _FloatingNav(
          index: index,
          onSelect: (i) => app.tab.value = i,
        ),
      ),
    );
  }
}

/// Floating bottom bar: Cloud · Feed · Explore (centre pill) · Channels ·
/// Profile. Same five tabs and indices as before; only the look changed.
class _FloatingNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _FloatingNav({required this.index, required this.onSelect});

  static const _items = [
    (Icons.cloud_outlined, Icons.cloud_rounded, 'Cloud'),
    (Icons.public_outlined, Icons.public, 'Feed'),
    (Icons.search_rounded, Icons.search_rounded, 'Explore'),
    (Icons.live_tv_outlined, Icons.live_tv_rounded, 'Channels'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(child: _navItem(i)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int i) {
    final (icon, activeIcon, label) = _items[i];
    final selected = i == index;
    final centre = i == 2;
    final color = centre
        ? (selected ? AppColors.ink : const Color(0xFFD4D4D8))
        : (selected ? AppColors.primary : AppColors.subtle);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(selected ? activeIcon : icon, size: 23, color: color),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: InkResponse(
        onTap: () => onSelect(i),
        radius: 34,
        child: Center(
          child: centre
              ? AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 66,
                  height: 52,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary
                        : AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(child: content),
                )
              : content,
        ),
      ),
    );
  }
}

/// First-launch Terms & Privacy dialog.
class ConsentDialog extends StatelessWidget {
  const ConsentDialog({super.key});

  @override
  Widget build(BuildContext context) {
    void open(String key) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PolicyScreen(policyKey: key)));
    return PopScope(
      canPop: false,
      child: Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: const BoxDecoration(gradient: AppColors.gradient),
              padding: const EdgeInsets.all(24),
              child: const Row(
                children: [
                  Icon(
                    Icons.cloud_upload_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                  SizedBox(width: 16),
                  Text(
                    Config.appName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Column(
                children: [
                  const Text(
                    'Terms of Service and Privacy Policy',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Welcome! By using this app, you agree to how we collect, use and protect your data, '
                    'and to your rights and responsibilities as a user. Please review:',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => open('privacy'),
                        child: const Text('Privacy Policy'),
                      ),
                      TextButton(
                        onPressed: () => open('terms'),
                        child: const Text('Terms & Conditions'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await app.acceptConsent();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('Agree'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
