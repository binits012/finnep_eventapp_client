import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/checkout_payload.dart';
import '../services/payment_service.dart';
import '../utils/currency.dart';
import '../utils/money.dart';
import '../widgets/legal_overflow_menu_button.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.payload});

  final CheckoutPayload payload;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen>
    with WidgetsBindingObserver {
  bool _useStripe = true;
  bool _loading = false;
  String? _error;
  bool _stripeInitialized = false;
  String? _pendingPaytrailStamp;
  String? _pendingPaytrailTransactionId;
  bool _paytrailVerifying = false;
  Timer? _reservationTimer;
  Duration _reservationRemaining = Duration.zero;
  String? _pendingStripeClientSecret;
  String? _pendingStripePaymentIntentId;
  bool _stripeVerifying = false;

  void _applyStripeClientSettings() {
    Stripe.publishableKey = stripePublishableKey;
    Stripe.merchantIdentifier = stripeAppleMerchantIdentifier;
  }

  CheckoutPayload _effectivePayload() {
    final w = widget.payload;
    final pc = (w.couponCode ?? '').trim();
    if (pc.isEmpty || (w.couponDiscountAmount ?? 0) <= 0) return w;
    return w.mergeAppliedCoupon(
      couponCode: pc.trim().toUpperCase(),
      couponId: w.couponId,
      couponDiscountAmount: w.couponDiscountAmount!,
    );
  }

  bool get _canStripe => stripePublishableKey.isNotEmpty;

  bool get _canPaytrail => widget.payload.paytrailEnabled;

  bool get _isStripeTestMode =>
      stripePublishableKey.trim().toLowerCase().startsWith('pk_test_');

  bool get _canPayNow {
    if (_loading) return false;
    if (_isReservationExpired) return false;
    if (_useStripe && _canStripe) return _stripeInitialized;
    if (_canPaytrail) return true;
    return false;
  }

  bool get _isReservationExpired {
    final expiresAt = widget.payload.reservationExpiresAtMs;
    if (expiresAt == null) return false;
    return DateTime.now().millisecondsSinceEpoch >= expiresAt;
  }

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds < 0 ? 0 : d.inSeconds;
    final mins = totalSeconds ~/ 60;
    final secs = totalSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_canStripe) {
      _applyStripeClientSettings();
      Stripe.instance.applySettings().then((_) {
        if (mounted) setState(() => _stripeInitialized = true);
      });
    }
    _startReservationCountdown();
  }

  @override
  void dispose() {
    _reservationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startReservationCountdown() {
    final expiresAt = widget.payload.reservationExpiresAtMs;
    if (expiresAt == null) return;
    _reservationTimer?.cancel();
    _reservationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remainingMs = expiresAt - DateTime.now().millisecondsSinceEpoch;
      setState(() {
        _reservationRemaining = Duration(
          milliseconds: remainingMs > 0 ? remainingMs : 0,
        );
        if (remainingMs <= 0) {
          _error =
              'Reservation expired. Please go back and select seats again.';
        }
      });
      if (remainingMs <= 0) {
        _reservationTimer?.cancel();
      }
    });
    final initialRemaining = expiresAt - DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _reservationRemaining = Duration(
        milliseconds: initialRemaining > 0 ? initialRemaining : 0,
      );
      if (initialRemaining <= 0) {
        _error = 'Reservation expired. Please go back and select seats again.';
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeVerifyPaytrail(auto: true);
      _maybeFinalizeStripeAfterReturn();
    }
  }

  Map<String, dynamic> _buildVerifyPaytrailCheckoutData() {
    // Backend can use Redis by stamp, but also accepts client checkout data
    // (especially if verification happens after a delay).
    final p = _effectivePayload();
    final fullName = (p.fullName ?? '').trim();
    return <String, dynamic>{
      'eventId': p.eventId,
      'merchantId': p.merchantId,
      'externalMerchantId': p.externalMerchantId,
      'email': p.email,
      'fullName': fullName,
      'customerName': fullName.isNotEmpty
          ? fullName
          : (p.email.contains('@') ? p.email.split('@').first : p.email),
      'quantity': p.quantity,
      // Backend expects ticketTypeId for ticket_info; for pricing_configuration it can be null.
      'ticketTypeId': p.ticketId.isEmpty ? null : p.ticketId,
      'ticketName': p.ticketName,
      'eventName': p.eventName,
      'sessionId': p.sessionId,
      'seats': p.placeIds,
      'placeIds': p.placeIds,
      'sectionSelections': p.sectionSelections,
      'seatTickets': p.seatTickets,
      'amount': p.totalCents,
      'currency': p.currency.toUpperCase(),
      'basePrice': p.price,
      'serviceFee': p.serviceFee,
      'vatRate': p.vat,
      'serviceTax': p.serviceTax,
      'orderFee': p.orderFee,
      'country': p.country,
      'marketingOptIn': p.marketingOptIn,
      if ((p.couponCode ?? '').trim().isNotEmpty)
        'couponCode': p.couponCode!.trim().toUpperCase(),
      if ((p.couponId ?? '').trim().isNotEmpty) 'couponId': p.couponId!.trim(),
      if (p.couponDiscountAmount != null && p.couponDiscountAmount! > 0)
        'couponDiscountAmount': p.couponDiscountAmount,
    };
  }

  String? _resolveStripeConnectedAccountId(Map<String, dynamic> intent) {
    final raw = intent['stripeAccount'];
    if (raw == null) return null;
    final value = raw.toString().trim();
    if (value.isEmpty) return null;
    if (!value.startsWith('acct_')) {
      throw Exception(
        'Invalid Stripe connected account received from backend.',
      );
    }
    return value;
  }

  bool _isStripeUserCancellation(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('canceled') ||
        text.contains('cancelled') ||
        text.contains('cancled') ||
        text.contains('payment flow has been canceled');
  }

  bool _isStripeSucceededStatus(dynamic status) {
    final s = status?.toString().toLowerCase() ?? '';
    return s.contains('succeeded');
  }

  bool _isStripeFailureStatus(dynamic status) {
    final s = status?.toString().toLowerCase() ?? '';
    return s.contains('canceled') ||
        s.contains('cancelled') ||
        s.contains('failed') ||
        s.contains('requires_payment_method');
  }

  Future<void> _maybeFinalizeStripeAfterReturn() async {
    final clientSecret = _pendingStripeClientSecret;
    final pendingPid = _pendingStripePaymentIntentId;
    if (clientSecret == null ||
        clientSecret.isEmpty ||
        pendingPid == null ||
        pendingPid.isEmpty) {
      return;
    }
    if (_loading || _stripeVerifying) return;

    if (!mounted) return;
    setState(() {
      _stripeVerifying = true;
      _loading = true;
      _error = null;
    });

    try {
      final intent = await Stripe.instance.retrievePaymentIntent(clientSecret);
      final status = intent.status;
      if (_isStripeSucceededStatus(status)) {
        final p = _effectivePayload();
        final result = await paymentSuccess(
          paymentIntentId: pendingPid,
          eventId: p.eventId,
          email: p.email,
          merchantId: p.merchantId,
          ticketId: p.ticketId.isEmpty ? null : p.ticketId,
          quantity: p.quantity,
          eventName: p.eventName,
          ticketName: p.ticketName,
          externalMerchantId: p.externalMerchantId,
          sessionId: p.sessionId,
          placeIds: p.placeIds,
          sectionSelections: p.sectionSelections,
          seatTickets: p.seatTickets,
          marketingOptIn: p.marketingOptIn,
        );
        if (!mounted) return;
        _pendingStripeClientSecret = null;
        _pendingStripePaymentIntentId = null;
        final extra = <String, dynamic>{
          ...result,
          '_clientCurrency': p.currency,
          '_clientTotalAmountOverride': p.totalAmountOverride,
          '_clientTotalCents': p.totalCents,
          '_clientTicketName': p.ticketName,
          '_clientPlaceIds': p.placeIds,
          '_clientEmail': p.email,
        };
        context.go('/success', extra: extra);
        return;
      }

      if (_isStripeFailureStatus(status)) {
        if (!mounted) return;
        setState(() {
          _pendingStripeClientSecret = null;
          _pendingStripePaymentIntentId = null;
          _loading = false;
          _stripeVerifying = false;
          _error = null;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _stripeVerifying = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _stripeVerifying = false;
      });
    }
  }

  Future<void> _maybeVerifyPaytrail({required bool auto}) async {
    final stamp = _pendingPaytrailStamp;
    final transactionId = _pendingPaytrailTransactionId;
    if (stamp == null ||
        stamp.isEmpty ||
        transactionId == null ||
        transactionId.isEmpty) {
      return;
    }
    if (_loading || _paytrailVerifying) return;

    if (!mounted) return;
    setState(() {
      _paytrailVerifying = true;
      _loading = true;
      _error = auto ? 'Checking Paytrail payment status…' : null;
    });

    try {
      final result = await verifyPaytrailPayment(
        stamp: stamp,
        transactionId: transactionId,
        checkoutData: _buildVerifyPaytrailCheckoutData(),
      );
      if (!mounted) return;
      final p = _effectivePayload();
      final extra = <String, dynamic>{
        ...result,
        '_clientCurrency': p.currency,
        '_clientTotalAmountOverride': p.totalAmountOverride,
        '_clientTotalCents': p.totalCents,
        '_clientTicketName': p.ticketName,
        '_clientPlaceIds': p.placeIds,
        '_clientEmail': p.email,
      };
      context.go('/success', extra: extra);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _paytrailVerifying = false;
      });
    }
  }

  Future<void> _payWithStripe() async {
    if (!_canStripe) {
      setState(() => _error = 'Stripe not configured');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = _effectivePayload();
      _applyStripeClientSettings();
      final intent = await createPaymentIntent(
        amountCents: p.totalCents,
        currency: p.currency,
        eventId: p.eventId,
        merchantId: p.merchantId,
        externalMerchantId: p.externalMerchantId,
        email: p.email,
        quantity: p.quantity,
        ticketId: p.ticketId,
        eventName: p.eventName,
        ticketName: p.ticketName,
        basePrice: p.price,
        serviceFee: p.serviceFee,
        serviceTaxRate: p.serviceTax,
        orderFee: p.orderFee,
        vatRate: p.vat,
        sessionId: p.sessionId,
        placeIds: p.placeIds,
        sectionSelections: p.sectionSelections,
        seatTickets: p.seatTickets,
        country: p.country,
        fullName: p.fullName,
        totalAmountOverride: p.totalAmountOverride,
        marketingOptIn: p.marketingOptIn,
        couponCode: (p.couponCode != null && p.couponCode!.trim().isNotEmpty)
            ? p.couponCode!.trim().toUpperCase()
            : null,
        couponId: (p.couponId != null && p.couponId!.trim().isNotEmpty)
            ? p.couponId!.trim()
            : null,
        couponDiscountAmount:
            (p.couponDiscountAmount != null && p.couponDiscountAmount! > 0)
            ? p.couponDiscountAmount
            : null,
        registrationAnswers: p.registrationAnswers,
      );
      final clientSecret = intent['clientSecret'] as String?;
      if (clientSecret == null || clientSecret.isEmpty) {
        throw Exception('No client secret');
      }
      // Backend is the only source of truth for charge context:
      // platform (null) vs Connect direct charge (acct_...).
      final connectedAccountId = _resolveStripeConnectedAccountId(intent);
      Stripe.stripeAccountId = connectedAccountId;
      final appleMerchantIdentifier = stripeAppleMerchantIdentifier;
      if (appleMerchantIdentifier != null) {
        Stripe.merchantIdentifier = appleMerchantIdentifier;
      }
      await Stripe.instance.applySettings();
      final googlePayConfig = PaymentSheetGooglePay(
        merchantCountryCode: stripeMerchantCountryCode,
        currencyCode: p.currency.toUpperCase(),
        testEnv: _isStripeTestMode,
      );
      final applePayConfig = appleMerchantIdentifier == null
          ? null
          : PaymentSheetApplePay(
              merchantCountryCode: stripeMerchantCountryCode,
            );
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: stripeMerchantDisplayName,
          billingDetails: BillingDetails(email: p.email, name: p.fullName),
          googlePay: googlePayConfig,
          applePay: applePayConfig,
          allowsDelayedPaymentMethods: true,
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      final pid =
          intent['paymentIntentId'] as String? ??
          (clientSecret.split('_secret_').isNotEmpty
              ? clientSecret.split('_secret_').first
              : '');
      _pendingStripeClientSecret = clientSecret;
      _pendingStripePaymentIntentId = pid;
      final result = await paymentSuccess(
        paymentIntentId: pid,
        eventId: p.eventId,
        email: p.email,
        merchantId: p.merchantId,
        ticketId: p.ticketId.isEmpty ? null : p.ticketId,
        quantity: p.quantity,
        eventName: p.eventName,
        ticketName: p.ticketName,
        externalMerchantId: p.externalMerchantId,
        sessionId: p.sessionId,
        placeIds: p.placeIds,
        sectionSelections: p.sectionSelections,
        seatTickets: p.seatTickets,
        marketingOptIn: p.marketingOptIn,
      );
      if (!mounted) return;
      _pendingStripeClientSecret = null;
      _pendingStripePaymentIntentId = null;
      // Pass client-side totals and ticket name for display.
      final extra = <String, dynamic>{
        ...result,
        '_clientCurrency': p.currency,
        '_clientTotalAmountOverride': p.totalAmountOverride,
        '_clientTotalCents': p.totalCents,
        '_clientTicketName': p.ticketName,
        '_clientPlaceIds': p.placeIds,
        '_clientEmail': p.email,
      };
      context.go('/success', extra: extra);
    } catch (e) {
      if (!mounted) return;
      if (_isStripeUserCancellation(e)) {
        setState(() {
          _pendingStripeClientSecret = null;
          _pendingStripePaymentIntentId = null;
          _loading = false;
          _error = null;
        });
        return;
      }
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _payWithPaytrail() async {
    if (!_canPaytrail) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = _effectivePayload();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'pendingPaytrailCheckoutPayload',
        jsonEncode(p.toJson()),
      );

      final result = await createPaytrailPayment(
        amountCents: p.totalCents,
        currency: p.currency,
        eventId: p.eventId,
        merchantId: p.merchantId,
        externalMerchantId: p.externalMerchantId,
        email: p.email,
        quantity: p.quantity,
        ticketId: p.ticketId,
        eventName: p.eventName,
        ticketName: p.ticketName,
        basePrice: p.price,
        serviceFee: p.serviceFee,
        serviceTaxRate: p.serviceTax,
        orderFee: p.orderFee,
        vatRate: p.vat,
        sessionId: p.sessionId,
        placeIds: p.placeIds,
        sectionSelections: p.sectionSelections,
        seatTickets: p.seatTickets,
        country: p.country,
        fullName: p.fullName,
        totalAmountOverride: p.totalAmountOverride,
        marketingOptIn: p.marketingOptIn,
        couponCode: (p.couponCode != null && p.couponCode!.trim().isNotEmpty)
            ? p.couponCode!.trim().toUpperCase()
            : null,
        couponId: (p.couponId != null && p.couponId!.trim().isNotEmpty)
            ? p.couponId!.trim()
            : null,
        couponDiscountAmount:
            (p.couponDiscountAmount != null && p.couponDiscountAmount! > 0)
            ? p.couponDiscountAmount
            : null,
        registrationAnswers: p.registrationAnswers,
      );
      final url = result['paymentUrl'] as String?;
      final stamp = result['stamp']?.toString();
      final transactionId = result['transactionId']?.toString();
      if (url == null || url.isEmpty) throw Exception('No payment URL');
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        setState(() {
          _pendingPaytrailStamp = stamp;
          _pendingPaytrailTransactionId = transactionId;
        });
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      setState(() {
        _loading = false;
        _error = 'After paying, return to the app to finish verification.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _effectivePayload();
    final total = p.totalCents / 100.0;
    final theme = Theme.of(context);
    final couponCodeApplied = (p.couponCode ?? '').trim();
    final couponDiscApplied = p.couponDiscountAmount;
    final activeCouponSubtitle =
        couponCodeApplied.isNotEmpty &&
            couponDiscApplied != null &&
            couponDiscApplied > 0
        ? '$couponCodeApplied (−${formatPrice(roundMoney(couponDiscApplied), p.currency)})'
        : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: const [LegalOverflowMenuButton()],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total: ${formatFinalTotal(total, p.currency)}',
              style: theme.textTheme.titleLarge,
            ),
            if (activeCouponSubtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                'Discount code $activeCouponSubtitle',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (widget.payload.reservationExpiresAtMs != null) ...[
              const SizedBox(height: 8),
              Text(
                'Reservation expires in ${_formatDuration(_reservationRemaining)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _reservationRemaining.inSeconds <= 60
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            if (_canStripe && _canPaytrail)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('Stripe (Card / Wallet)'),
                    icon: Icon(Icons.credit_card),
                  ),
                  ButtonSegment(value: false, label: Text('Paytrail')),
                ],
                selected: {_useStripe},
                onSelectionChanged: (s) => setState(() => _useStripe = s.first),
              )
            else if (_canPaytrail)
              const Text('Pay with Paytrail')
            else if (_canStripe)
              Text(
                'Pay with Stripe (Card / Wallet)',
                style: theme.textTheme.titleMedium,
              ),
            if (_useStripe && _canStripe) ...[
              const SizedBox(height: 16),
              if (!_stripeInitialized)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else ...[
                Text(
                  'Continue to Stripe to choose your available payment methods (card/wallet).',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canPayNow
                    ? () {
                        if (_useStripe && _canStripe) {
                          _payWithStripe();
                        } else if (_canPaytrail) {
                          _payWithPaytrail();
                        }
                      }
                    : null,
                child: _loading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Pay now'),
              ),
            ),
            if (_pendingPaytrailStamp != null && !_useStripe) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: (_loading || _paytrailVerifying)
                      ? null
                      : () => _maybeVerifyPaytrail(auto: false),
                  child: const Text('I have paid (verify)'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
