import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models.dart';
import '../services/backend.dart';
import '../services/payments.dart';
import '../services/play_billing.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/gates.dart';
import '../widgets/reload.dart';
import 'payment_status_screen.dart';
import 'login_screen.dart';
import 'policy_screen.dart';
import 'profile_screen.dart';

/// Premium plans. Also the Profile tab; the person icon opens the profile.
class PremiumScreen extends StatefulWidget {
  final bool standalone;
  const PremiumScreen({super.key, this.standalone = false});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> with ContentReload {
  List<Plan>? plans;
  String? selected;
  String? error;
  bool sending = false;
  OpenOrder? openOrder;

  @override
  Future<void> reload() async {
    try {
      final list = await Backend.plans();
      await app.refreshStatus();
      await _loadOpenOrder();
      if (!mounted) return;
      setState(() {
        plans = list;
        error = null;
        // Start with the first plan picked, so one tap continues.
        if (selected == null || !list.any((p) => p.id == selected)) {
          selected = list.isEmpty ? null : list.first.id;
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  /// Server creates the order (amount from the plans table), then the UPI app
  /// opens. The result screen shows only what the server decided. Guests can
  /// buy a plan without logging in first -- it stays tied to their current
  /// (anonymous) account, which they can later turn into a real one from
  /// Profile without losing it.
  Future<void> _next() async {
    final plan = plans?.firstWhere((p) => p.id == selected);
    if (plan == null) return;
    // Terms first; "OK, continue" goes on to the payment as before.
    if (!await showPlanTerms(context, plan) || !mounted) return;
    setState(() => sending = true);
    try {
      // Play Store build only: Google's information screen + report token.
      String? playToken;
      if (PlayBilling.hidesPlans) {
        try {
          playToken = await PlayBilling.prepare();
        } on PlayBillingException catch (e) {
          if (mounted && !e.cancelled) _alert('Payment', e.toString());
          return;
        }
      }
      final order = await payments.createOrder(plan);
      if (playToken != null) await Backend.attachPlayToken(order.id, playToken);
      final payee = await payments.savedPayee();
      try {
        await payments.launch(order, upiId: payee!.$1, payee: payee.$2);
      } on NoUpiAppException catch (e) {
        if (mounted) _alert('No UPI app found', e.toString());
        return;
      } on UnsupportedError catch (e) {
        // Web test builds: the order exists, but no UPI app can be opened.
        if (mounted) {
          showSnack(context, e.message ?? 'UPI is not available here.');
        }
      }
      if (!mounted) return;
      await _openStatus(order);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _openStatus(OpenOrder order) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PaymentStatusScreen(order: order)),
    );
    await _loadOpenOrder();
    await app.refreshStatus();
  }

  Future<void> _loadOpenOrder() async {
    final o = await payments.openOrder();
    if (mounted) setState(() => openOrder = o);
  }

  void _alert(String title, String text) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _continueBar() {
    final plan = plans!.where((p) => p.id == selected).firstOrNull;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          onPressed: sending || plan == null ? null : _next,
          child: Text(
            sending
                ? 'Opening UPI…'
                : plan == null
                ? 'Select a plan'
                : 'Continue with ${plan.name} · ₹${plan.priceInr}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  List<Widget> _plansSection() {
    final list = plans!;
    final deals = PlanDeals(list);
    return [
      const Text(
        'Go Premium',
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        'One-time UPI payment · No auto-renewal',
        style: TextStyle(fontSize: 13.5, color: AppColors.muted),
      ),
      const SizedBox(height: 14),
      const Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _Chip(icon: Icons.bolt_rounded, text: 'Fast upload & download'),
          _Chip(icon: Icons.cloud_outlined, text: '2 TB storage'),
        ],
      ),
      const SizedBox(height: 20),
      for (final p in list)
        _PlanCard(
          plan: p,
          badge: deals.badge(p),
          bestValue: deals.isBest(p),
          selected: p.id == selected,
          onTap: () => setState(() => selected = p.id),
        ),
      const SizedBox(height: 2),
      Center(
        child: TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: AppColors.muted),
          onPressed: () => emailSupport(subject: 'Question about plans'),
          icon: const Icon(Icons.mail_outline_rounded, size: 18),
          label: const Text.rich(
            TextSpan(
              text: 'Questions? ',
              children: [
                TextSpan(
                  text: 'Email us',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.barGradient),
          child: SizedBox.expand(),
        ),
        automaticallyImplyLeading: widget.standalone,
        title: const Text('Premium'),
        actions: [
          IconButton(
            icon: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.chip,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.person_outline_rounded, size: 24),
            ),
            tooltip: 'Profile',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
        ],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: app,
        builder: (context, _) => plans == null || app.noPlans
            ? const SizedBox.shrink()
            : _continueBar(),
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          if (error != null && plans == null) {
            return ErrorRetry(message: error!, onRetry: reload);
          }
          if (plans == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final s = app.status;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (s?.isPremium == true && s?.planName != null)
                _Banner(
                  color: AppColors.successBg,
                  icon: Icons.verified,
                  text:
                      'You have ${s!.planName}${s.planEndsAt != null ? ' until ${s.planEndsAt!.toLocal().toString().substring(0, 10)}' : ''}.',
                )
              else if (openOrder != null)
                InkWell(
                  onTap: () => _openStatus(openOrder!),
                  child: _Banner(
                    color: AppColors.warningBg,
                    icon: Icons.hourglass_top,
                    text:
                        'Payment for ${openOrder!.planName} (order ${openOrder!.reference}) is being checked. Tap to see the status.',
                  ),
                )
              else if (s?.openRequest != null)
                _Banner(
                  color: AppColors.warningBg,
                  icon: Icons.hourglass_top,
                  text: 'Your ${s!.openRequest} request is being processed.',
                ),
              // Free mode / Google Play build: no plans or payments.
              if (app.noPlans && (app.freeMode || s?.isPremium != true))
                _FreeAccount(
                  onLogIn: () async {
                    if (await ensureLoggedIn(
                      context,
                      reason: 'Log in to get 15 GB of free cloud storage.',
                    )) {
                      await app.refreshStatus();
                    }
                  },
                  onRequest: () async {
                    try {
                      await app.requestFullAccess();
                    } catch (e) {
                      if (context.mounted) showSnack(context, friendlyError(e));
                    }
                  },
                ),
              if (!app.noPlans) ..._plansSection(),
            ],
          );
        },
      ),
    );
  }
}

/// Per-day price, "Save %" against the shortest plan, and the best value.
class PlanDeals {
  final List<Plan> plans;
  late final double _base;
  late final String? _bestId;
  PlanDeals(this.plans) {
    final valid = plans.where((p) => p.durationDays > 0).toList();
    if (valid.isEmpty) {
      _base = 0;
      _bestId = null;
      return;
    }
    valid.sort((a, b) => a.durationDays.compareTo(b.durationDays));
    _base = perDay(valid.first);
    valid.sort((a, b) => perDay(a).compareTo(perDay(b)));
    _bestId = valid.length > 2 ? valid.first.id : null;
  }

  static double perDay(Plan p) =>
      p.durationDays > 0 ? p.priceInr / p.durationDays : double.infinity;

  static String perDayLabel(Plan p) {
    final d = perDay(p);
    if (!d.isFinite) return '';
    return d < 10 ? '₹${d.toStringAsFixed(1)}/day' : '₹${d.round()}/day';
  }

  int save(Plan p) => _base > 0 ? ((1 - perDay(p) / _base) * 100).round() : 0;

  bool isBest(Plan p) => p.id == _bestId;

  String? badge(Plan p) {
    final s = save(p);
    if (isBest(p)) return s >= 5 ? 'BEST VALUE · SAVE $s%' : 'BEST VALUE';
    return s >= 5 ? 'SAVE $s%' : null;
  }
}

/// Opens the user's email app to write to support.
Future<void> emailSupport({String? subject, String? body}) async {
  final q = <String>[
    'subject=${Uri.encodeComponent(subject ?? '${Config.appName} support')}',
    if (body != null) 'body=${Uri.encodeComponent(body)}',
  ].join('&');
  try {
    await launchUrl(Uri(scheme: 'mailto', path: Config.supportEmail, query: q));
  } catch (_) {}
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Chip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final String? badge;
  final bool bestValue;
  final bool selected;
  final VoidCallback onTap;
  const _PlanCard({
    required this.plan,
    required this.badge,
    required this.bestValue,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.fromLTRB(14, 15, 16, 13),
                decoration: BoxDecoration(
                  color: selected ? const Color(0x1AFF7A1A) : AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border,
                    width: 1.6,
                  ),
                  boxShadow: selected
                      ? const [
                          BoxShadow(
                            color: Color(0x33FF7A1A),
                            blurRadius: 20,
                            offset: Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? AppColors.primary : AppColors.muted,
                          width: selected ? 7 : 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            plan.durationLabel,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${plan.priceInr}',
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? AppColors.primary
                                : AppColors.text,
                          ),
                        ),
                        Text(
                          PlanDeals.perDayLabel(plan),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (badge != null)
            Positioned(
              top: -10,
              left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: bestValue
                      ? AppColors.primary
                      : const Color(0xFF13301F),
                  borderRadius: BorderRadius.circular(999),
                  border: bestValue
                      ? null
                      : Border.all(color: const Color(0xFF1F6B3E)),
                ),
                child: Text(
                  bestValue ? '★ $badge' : badge!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: bestValue ? AppColors.ink : const Color(0xFF4ADE80),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _Banner({required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }
}

/// Free mode / Google Play build: cloud allowance, full-access status and
/// (free mode) the request for full access. No prices and no way to pay.
class _FreeAccount extends StatelessWidget {
  final VoidCallback onLogIn;
  final VoidCallback onRequest;
  const _FreeAccount({required this.onLogIn, required this.onRequest});

  @override
  Widget build(BuildContext context) {
    final s = app.status;
    final loggedIn = !app.isGuest;
    final free = app.freeMode;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_done_outlined, color: AppColors.primary),
              const SizedBox(width: 10),
              Text(
                free ? '${Config.appName} is free' : 'Free account',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            loggedIn && s != null && s.quotaBytes > 0
                ? 'You have ${formatBytes(s.quotaBytes)} of cloud storage. '
                      '${formatBytes(s.usedBytes)} used.'
                : 'Log in to get 15 GB of free cloud storage for your photos, videos and files.',
            style: const TextStyle(fontSize: 15),
          ),
          if (free && loggedIn) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            if (app.isPremium)
              const Row(
                children: [
                  Icon(Icons.verified, color: AppColors.gold),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Full access: all videos and downloads are unlocked.',
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                ],
              )
            else if (s?.accessStatus == 'pending')
              const Row(
                children: [
                  Icon(Icons.hourglass_top),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your request for full access is being reviewed.',
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                ],
              )
            else if (s?.accessStatus == 'rejected')
              const Text(
                'Full access was not approved for this account.',
                style: TextStyle(fontSize: 15),
              )
            else ...[
              const Text(
                'Some videos and downloads need approval from our team.',
                style: TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onRequest,
                child: const Text('Request full access'),
              ),
            ],
          ],
          if (!free) ...[
            const SizedBox(height: 8),
            const Text(
              'Premium plans are not available in this version of the app.',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ],
          if (!loggedIn) ...[
            const SizedBox(height: 14),
            FilledButton(onPressed: onLogIn, child: const Text('Log in')),
          ],
        ],
      ),
    );
  }
}

/// The one popup before payment (after "Continue"): plan, price, what they
/// get, who they pay, what to do if money is debited, and - for guests - a
/// small "save your plan" log-in line. Returns true on "Pay securely"; the
/// payment then goes on exactly as before.
Future<bool> showPlanTerms(BuildContext context, Plan plan) async {
  void open(String key) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => PolicyScreen(policyKey: key)));
  const muted = TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.muted);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      clipBehavior: Clip.antiAlias,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: AppColors.ink,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.name,
                          style: const TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${plan.durationLabel} of Premium · ${PlanDeals.perDayLabel(plan)}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₹${plan.priceInr}',
                    style: const TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Column(
                  children: [
                    _Tick('Fast upload & download speed'),
                    _Tick('2 TB cloud storage'),
                    _Tick('Starts instantly after payment'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F2A1A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF1F6B3E)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lock_rounded,
                      size: 18,
                      color: Color(0xFF4ADE80),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: "You'll pay ",
                          children: [
                            TextSpan(
                              text: '₹${plan.priceInr} to ${Config.appName}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const TextSpan(
                              text: ' securely in your UPI app (Google Pay, PhonePe, Paytm…).',
                            ),
                          ],
                        ),
                        style: const TextStyle(fontSize: 13.5, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Money debited but plan not active? Don't pay again. Email us "
                "with your order number and we'll activate it or refund within "
                "24 hours. Plans aren't refundable once active, except as in "
                'the Refund Policy.',
                style: muted,
              ),
              if (app.isGuest) ...[
                const SizedBox(height: 12),
                Material(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            color: AppColors.primary,
                            size: 22,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                text: 'Save your plan to your account\n',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                                children: [
                                  TextSpan(
                                    text: "As a guest it's saved only on this phone. ",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w400,
                                      color: AppColors.muted,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  TextSpan(
                                    text: 'Log in',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 54,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('Pay ₹${plan.priceInr} securely'),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'One-time payment · No auto-renewal',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'By paying you accept the ',
                    style: TextStyle(fontSize: 11.5, color: AppColors.subtle),
                  ),
                  _MiniLink('Terms', () => open('terms')),
                  const Text(
                    ' & ',
                    style: TextStyle(fontSize: 11.5, color: AppColors.subtle),
                  ),
                  _MiniLink('Refund Policy', () => open('refund')),
                ],
              ),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Need help? ',
                    style: TextStyle(fontSize: 11.5, color: AppColors.subtle),
                  ),
                  _MiniLink(
                    'Email us',
                    () => emailSupport(subject: 'Question about ${plan.name}'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return ok == true;
}

class _Tick extends StatelessWidget {
  final String text;
  const _Tick(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: Color(0xFF4ADE80),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniLink extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _MiniLink(this.text, this.onTap);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}
