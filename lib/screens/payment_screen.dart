import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/checkout_payload.dart';
import '../services/payment_service.dart';
import '../utils/currency.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.payload});

  final CheckoutPayload payload;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> with WidgetsBindingObserver {
  bool _useStripe = true;
  bool _loading = false;
  String? _error;
  bool _cardComplete = false;
  bool _stripeInitialized = false;
  String? _pendingPaytrailStamp;
  String? _pendingPaytrailTransactionId;
  bool _paytrailVerifying = false;

  bool get _canStripe => stripePublishableKey.isNotEmpty;

  bool get _canPaytrail => widget.payload.paytrailEnabled;

  bool get _canPayNow {
    if (_loading) return false;
    if (_useStripe && _canStripe) return _cardComplete;
    if (_canPaytrail) return true;
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_canStripe) {
      Stripe.publishableKey = stripePublishableKey;
      Stripe.instance.applySettings().then((_) {
        if (mounted) setState(() => _stripeInitialized = true);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeVerifyPaytrail(auto: true);
    }
  }

  Map<String, dynamic> _buildVerifyPaytrailCheckoutData() {
    // Backend can use Redis by stamp, but also accepts client checkout data
    // (especially if verification happens after a delay).
    final fullName = (widget.payload.fullName ?? '').trim();
    return <String, dynamic>{
      'eventId': widget.payload.eventId,
      'merchantId': widget.payload.merchantId,
      'externalMerchantId': widget.payload.externalMerchantId,
      'email': widget.payload.email,
      'fullName': fullName,
      'customerName': fullName.isNotEmpty
          ? fullName
          : (widget.payload.email.contains('@') ? widget.payload.email.split('@').first : widget.payload.email),
      'quantity': widget.payload.quantity,
      // Backend expects ticketTypeId for ticket_info; for pricing_configuration it can be null.
      'ticketTypeId': widget.payload.ticketId.isEmpty ? null : widget.payload.ticketId,
      'ticketName': widget.payload.ticketName,
      'eventName': widget.payload.eventName,
      'sessionId': widget.payload.sessionId,
      'seats': widget.payload.placeIds,
      'placeIds': widget.payload.placeIds,
      'seatTickets': widget.payload.seatTickets,
      'amount': widget.payload.totalCents,
      'currency': widget.payload.currency.toUpperCase(),
      'basePrice': widget.payload.price,
      'serviceFee': widget.payload.serviceFee,
      'vatRate': widget.payload.vat,
      'serviceTax': widget.payload.serviceTax,
      'orderFee': widget.payload.orderFee,
      'country': widget.payload.country,
    };
  }

  Future<void> _maybeVerifyPaytrail({required bool auto}) async {
    final stamp = _pendingPaytrailStamp;
    final transactionId = _pendingPaytrailTransactionId;
    if (stamp == null || stamp.isEmpty || transactionId == null || transactionId.isEmpty) return;
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
      final extra = <String, dynamic>{
        ...result,
        '_clientCurrency': widget.payload.currency,
        '_clientTotalAmountOverride': widget.payload.totalAmountOverride,
        '_clientTotalCents': widget.payload.totalCents,
        '_clientTicketName': widget.payload.ticketName,
        '_clientPlaceIds': widget.payload.placeIds,
        '_clientEmail': widget.payload.email,
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
      Stripe.publishableKey = stripePublishableKey;
      await Stripe.instance.applySettings();
      debugPrint('payload: ${widget.payload.toJson()}');
      final intent = await createPaymentIntent(
        amountCents: widget.payload.totalCents,
        currency: widget.payload.currency,
        eventId: widget.payload.eventId,
        merchantId: widget.payload.merchantId,
        externalMerchantId: widget.payload.externalMerchantId,
        email: widget.payload.email,
        quantity: widget.payload.quantity,
        ticketId: widget.payload.ticketId,
        eventName: widget.payload.eventName,
        ticketName: widget.payload.ticketName,
        basePrice: widget.payload.price,
        serviceFee: widget.payload.serviceFee,
        serviceTaxRate: widget.payload.serviceTax,
        orderFee: widget.payload.orderFee,
        vatRate: widget.payload.vat,
        sessionId: widget.payload.sessionId,
        placeIds: widget.payload.placeIds,
        seatTickets: widget.payload.seatTickets,
        country: widget.payload.country,
        fullName: widget.payload.fullName,
        totalAmountOverride: widget.payload.totalAmountOverride,
      );
      final clientSecret = intent['clientSecret'] as String?;
      if (clientSecret == null || clientSecret.isEmpty) {
        throw Exception('No client secret');
      }
      await Stripe.instance.confirmPayment(
        paymentIntentClientSecret: clientSecret,
        data: PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(
            billingDetails: BillingDetails(
              email: widget.payload.email,
              name: widget.payload.fullName,
            ),
          ),
        ),
      );
      final pid = intent['paymentIntentId'] as String? ?? (clientSecret.split('_secret_').isNotEmpty ? clientSecret.split('_secret_').first : '');
      final result = await paymentSuccess(
        paymentIntentId: pid,
        eventId: widget.payload.eventId,
        email: widget.payload.email,
        merchantId: widget.payload.merchantId,
        ticketId: widget.payload.ticketId.isEmpty ? null : widget.payload.ticketId,
        quantity: widget.payload.quantity,
        eventName: widget.payload.eventName,
        ticketName: widget.payload.ticketName,
        externalMerchantId: widget.payload.externalMerchantId,
        sessionId: widget.payload.sessionId,
        placeIds: widget.payload.placeIds,
        seatTickets: widget.payload.seatTickets,
      );
      if (!mounted) return;
      // Pass client-side totals and ticket name for display.
      final extra = <String, dynamic>{
        ...result,
        '_clientCurrency': widget.payload.currency,
        '_clientTotalAmountOverride': widget.payload.totalAmountOverride,
        '_clientTotalCents': widget.payload.totalCents,
        '_clientTicketName': widget.payload.ticketName,
        '_clientPlaceIds': widget.payload.placeIds,
        '_clientEmail': widget.payload.email,
      };
      context.go('/success', extra: extra);
    } catch (e) {
      if (!mounted) return;
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pendingPaytrailCheckoutPayload', jsonEncode(widget.payload.toJson()));
      debugPrint('[Paytrail] Saved pending checkout payload to storage.');

      final result = await createPaytrailPayment(
        amountCents: widget.payload.totalCents,
        currency: widget.payload.currency,
        eventId: widget.payload.eventId,
        merchantId: widget.payload.merchantId,
        externalMerchantId: widget.payload.externalMerchantId,
        email: widget.payload.email,
        quantity: widget.payload.quantity,
        ticketId: widget.payload.ticketId,
        eventName: widget.payload.eventName,
        ticketName: widget.payload.ticketName,
        basePrice: widget.payload.price,
        serviceFee: widget.payload.serviceFee,
        serviceTaxRate: widget.payload.serviceTax,
        orderFee: widget.payload.orderFee,
        vatRate: widget.payload.vat,
        sessionId: widget.payload.sessionId,
        placeIds: widget.payload.placeIds,
        seatTickets: widget.payload.seatTickets,
        country: widget.payload.country,
        fullName: widget.payload.fullName,
        totalAmountOverride: widget.payload.totalAmountOverride,
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
        debugPrint('[Paytrail] Launching external browser. stamp=$stamp transactionId=$transactionId url=$url');
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
    // Use totalAmountOverride for display so 3-decimal totals (e.g. 30.645) show correctly; totalCents is for the actual charge.
    final total = widget.payload.totalAmountOverride ?? (widget.payload.totalCents / 100.0);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total: ${formatPrice(total, widget.payload.currency)}', style: theme.textTheme.titleLarge),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            if (_canStripe && _canPaytrail)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Card (Stripe)'), icon: Icon(Icons.credit_card)),
                  ButtonSegment(value: false, label: Text('Paytrail')),
                ],
                selected: {_useStripe},
                onSelectionChanged: (s) => setState(() => _useStripe = s.first),
              )
            else if (_canPaytrail)
              const Text('Pay with Paytrail')
            else if (_canStripe)
              Text('Pay with card', style: theme.textTheme.titleMedium),
            if (_useStripe && _canStripe) ...[
              const SizedBox(height: 16),
              if (!_stripeInitialized)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else ...[
                Text('Card details', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.8))),
                const SizedBox(height: 8),
                CardField(
                  onCardChanged: (details) => setState(() => _cardComplete = details?.complete ?? false),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                child: _loading ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Pay now'),
              ),
            ),
            if (_pendingPaytrailStamp != null && !_useStripe) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: (_loading || _paytrailVerifying) ? null : () => _maybeVerifyPaytrail(auto: false),
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
