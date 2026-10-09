import 'package:flutter/material.dart';

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
      });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  /// Server creates the order (amount from the plans table), then the UPI app
  /// opens. The result screen shows only what the server decided.
  Future<void> _next() async {
    final plan = plans?.firstWhere((p) => p.id == selected);
    if (plan == null) return;
    // Guests log in first and come back here with the plan still selected;
    // the button then reads "Continue to payment".
    if (app.isGuest) {
      await ensureLoggedIn(
        context,
        reason: 'Please log in to buy ${plan.name}.',
      );
      return;
    }
    setState(() => sending = true);
    try {
      // Play Store build only: Google's information screen + report token.
      String? playToken;
      if (PlayBilling.isPlayBuild) {
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
            icon: const Icon(Icons.account_circle_outlined, size: 32),
            tooltip: 'Profile',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
        ],
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
          final perks = plans!.isNotEmpty && plans!.first.perks.isNotEmpty
              ? plans!.first.perks
              : const [
                  'Ad-Free Experience',
                  'Access 2 TB Cloud Storage',
                  'Fast Upload & Download Speed',
                ];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (s?.isPremium == true)
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
              // Google Play build: no plans or payments in the app.
              if (PlayBilling.isPlayBuild && s?.isPremium != true)
                _PlayFreeAccount(
                  onLogIn: () async {
                    if (await ensureLoggedIn(
                      context,
                      reason: 'Log in to get 15 GB of free cloud storage.',
                    )) {
                      await app.refreshStatus();
                    }
                  },
                ),
              if (!PlayBilling.isPlayBuild) ...[
                Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.gradient,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x40FF7A1A),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.workspace_premium,
                              size: 18,
                              color: AppColors.ink,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Premium',
                              style: TextStyle(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (final perk in perks)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: const BoxDecoration(
                                  color: Color(0x33FFFFFF),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  perk,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                RadioGroup<String>(
                  groupValue: selected,
                  onChanged: (v) => setState(() => selected = v),
                  child: Column(
                    children: [
                      for (final p in plans!)
                        _PlanCard(
                          plan: p,
                          selected: p.id == selected,
                          onTap: () => setState(() => selected = p.id),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: sending || selected == null ? null : _next,
                  child: Text(
                    sending
                        ? 'Opening UPI…'
                        : selected == null
                        ? 'Select a plan'
                        : app.isGuest
                        ? 'Next'
                        : 'Continue to payment',
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final bool selected;
  final VoidCallback onTap;
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF261A10) : AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1.2,
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x26FF7A1A),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Radio<String>(value: plan.id, activeColor: AppColors.primary),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      plan.durationLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  '₹ ${plan.priceInr}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
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
        borderRadius: BorderRadius.circular(12),
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

/// Google Play build, free users: the free cloud allowance and their status.
/// No prices and no way to pay here.
class _PlayFreeAccount extends StatelessWidget {
  final VoidCallback onLogIn;
  const _PlayFreeAccount({required this.onLogIn});

  @override
  Widget build(BuildContext context) {
    final s = app.status;
    final loggedIn = !app.isGuest;
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
          const Row(
            children: [
              Icon(Icons.cloud_done_outlined, color: AppColors.primary),
              SizedBox(width: 10),
              Text(
                'Free account',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            loggedIn && s != null && s.quotaBytes > 0
                ? 'You have ${formatBytes(s.quotaBytes)} of free cloud storage. '
                      '${formatBytes(s.usedBytes)} used.'
                : 'Log in to get 15 GB of free cloud storage for your photos, videos and files.',
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 8),
          const Text(
            'Premium plans are not available in this version of the app.',
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          if (!loggedIn) ...[
            const SizedBox(height: 14),
            FilledButton(onPressed: onLogIn, child: const Text('Log in')),
          ],
        ],
      ),
    );
  }
}
