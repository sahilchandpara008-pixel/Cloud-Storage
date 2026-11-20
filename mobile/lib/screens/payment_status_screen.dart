import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/backend.dart';
import '../services/payments.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Shows what the SERVER says about an order. Polls every 5 s for ~10 minutes,
/// and re-checks whenever the app comes back to the foreground or a UPI answer
/// was delivered.
class PaymentStatusScreen extends StatefulWidget {
  final OpenOrder order;
  const PaymentStatusScreen({super.key, required this.order});

  @override
  State<PaymentStatusScreen> createState() => _PaymentStatusScreenState();
}

class _PaymentStatusScreenState extends State<PaymentStatusScreen>
    with WidgetsBindingObserver {
  static const pollEvery = Duration(seconds: 5);
  static const pollFor = Duration(minutes: 10);

  PaymentOrder? order;
  String? error;
  bool checking = false;
  bool launching = false;
  Timer? _timer;
  late DateTime _pollUntil;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    payments.reported.addListener(_check);
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    payments.reported.removeListener(_check);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      payments.flush().whenComplete(_check);
      if (_timer == null && (order?.isOpen ?? true)) _startPolling();
    }
  }

  void _startPolling() {
    _pollUntil = DateTime.now().add(pollFor);
    _timer?.cancel();
    _timer = Timer.periodic(pollEvery, (_) {
      if (DateTime.now().isAfter(_pollUntil)) {
        _timer?.cancel();
        _timer = null;
        return;
      }
      _check();
    });
    _check();
  }

  Future<void> _check() async {
    if (checking) return;
    checking = true;
    try {
      final o = await Backend.paymentOrder(widget.order.id);
      if (!mounted) return;
      setState(() {
        order = o;
        error = null;
      });
      if (o != null && !o.isOpen) {
        _timer?.cancel();
        _timer = null;
        if (o.status == 'approved') {
          await app.refreshStatus();
          app.bumpContent();
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      checking = false;
    }
  }

  Future<void> _manualCheck() async {
    await payments.flush();
    if (_timer == null) _startPolling();
    await _check();
  }

  /// Opens the UPI app again for the same order (same reference and amount).
  Future<void> _payAgain() async {
    setState(() => launching = true);
    try {
      final payee = await payments.savedPayee();
      if (payee == null) {
        throw StateError('Order details missing. Start again from Premium.');
      }
      await payments.launch(widget.order, upiId: payee.$1, payee: payee.$2);
      _startPolling();
    } catch (e) {
      if (mounted) {
        showSnack(context, e is StateError ? e.message : friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    final status = o?.status ?? 'initiated';
    final (IconData icon, Color color, String message) = switch (status) {
      'approved' => (
        Icons.check_circle,
        AppColors.success,
        'Payment successful! Your plan is now active.',
      ),
      'failed' => (
        Icons.cancel,
        AppColors.primary,
        'Payment failed. Please try again.',
      ),
      'cancelled' => (
        Icons.remove_circle_outline,
        AppColors.muted,
        'Payment cancelled. You can try again.',
      ),
      'revoked' => (
        Icons.block,
        AppColors.muted,
        'This payment was reversed after review. Contact support if you think this is wrong.',
      ),
      _ => (
        Icons.hourglass_top,
        AppColors.warning,
        "Payment verification is pending. We're checking your payment.",
      ),
    };
    final open = o == null || o.isOpen;

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.barGradient),
          child: SizedBox.expand(),
        ),
        title: const Text('Payment'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.28),
                    blurRadius: 40,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(icon, size: 56, color: color),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _Row('Order number', widget.order.reference),
                _Row('Plan', o?.planName ?? widget.order.planName),
                _Row('Amount', o?.amountLabel ?? '₹${widget.order.amount}'),
                if (o?.txnId != null) _Row('UTR', o!.txnId!),
              ],
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.primary),
              ),
            ),
          const SizedBox(height: 24),
          if (open) ...[
            if (o?.clientStatus == 'NO_RESPONSE' || o?.status == 'initiated')
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  "If you didn't complete the payment in your UPI app, tap Pay again. "
                  'If money was taken, keep this order number; we will verify it.',
                  textAlign: TextAlign.center,
                ),
              ),
            OutlinedButton(
              onPressed: checking ? null : _manualCheck,
              child: const Text('Check payment status'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: launching ? null : _payAgain,
              child: Text(launching ? 'Opening…' : 'Pay again'),
            ),
          ] else
            FilledButton(
              onPressed: () => Navigator.pop(context, status == 'approved'),
              child: Text(status == 'approved' ? 'Done' : 'Back to plans'),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(color: AppColors.muted, fontSize: 14),
            ),
            const Spacer(),
            SelectableText(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
