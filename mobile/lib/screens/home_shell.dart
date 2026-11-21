import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    if (!mounted) return;
    if (!app.consentGiven) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const ConsentDialog(),
      );
    }
    // Right after "Agree" (or once for people who agreed in an older
    // version): Android's Allow / Don't allow notifications question.
    if (mounted && app.consentGiven) await app.askNotificationsOnce();
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

/// First-launch 18+ disclaimer: age, guidelines, content ownership and the
/// Terms & Privacy links. "Agree" saves consent; "Not agree" closes the app.
class ConsentDialog extends StatelessWidget {
  const ConsentDialog({super.key});

  static const _points = [
    'You must be at least 18 years old to install and use ${Config.appName}.',
    'You are responsible for everything done with your account.',
    'Follow our Community Guidelines. If you don\'t, your content may be '
        'removed and your account may be limited or suspended.',
    'Videos are posted by channels on ${Config.appName}. Copyrights belong to '
        'their owners. If you own content that was posted without your '
        'permission, use Report in the app or email us with proof of '
        'ownership and we will remove it.',
  ];

  @override
  Widget build(BuildContext context) {
    void open(String key) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PolicyScreen(policyKey: key)));
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        clipBehavior: Clip.antiAlias,
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '18+',
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Disclaimer',
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Please read before you continue',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final p in _points)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(top: 8, right: 12),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                p,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  height: 1.5,
                                  color: Color(0xFFD4D4D8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Text(
                      'Contact: ${Config.supportEmail}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final (i, l) in const [
                          ('terms', 'Terms'),
                          ('privacy', 'Privacy'),
                          ('community', 'Guidelines'),
                        ].indexed) ...[
                          if (i > 0)
                            const Text('·', style: TextStyle(color: AppColors.subtle)),
                          InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => open(l.$1),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                              child: Text(
                                l.$2,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                      icon: const Icon(Icons.verified_user_rounded, size: 20),
                      onPressed: () async {
                        await app.acceptConsent();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      label: const Text(
                        "I'm 18 or older — Agree",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 46,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.muted,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      // Under 18 or doesn't accept: leave the app.
                      onPressed: () => SystemNavigator.pop(),
                      child: const Text("I don't agree — Exit", maxLines: 1),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'By tapping Agree you confirm you are 18 or older and accept '
                    'the Terms and Privacy Policy.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.subtle),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
