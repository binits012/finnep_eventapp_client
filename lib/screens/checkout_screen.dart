import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/checkout_payload.dart';
import '../utils/currency.dart';
import '../utils/ticket_pricing.dart';
import 'payment_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, this.payload});

  final CheckoutPayload? payload;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  late String _email;

  static String _fmtPct(double rate) {
    // Don't round away decimals (e.g. 13.5%). Keep up to 2dp, trim trailing zeros.
    final s = rate.toStringAsFixed(2);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.payload?.email ?? '';
    _email = initial;
    _emailController.text = initial;
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  static Widget _priceRow(ThemeData theme, String label, double amount, String currency, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: bold ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600) : theme.textTheme.bodyMedium),
          Text(formatPrice(amount, currency), style: bold ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600) : theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  void _submit() {
    if (widget.payload == null) return;
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    final payload = CheckoutPayload(
      eventId: widget.payload!.eventId,
      eventName: widget.payload!.eventName,
      merchantId: widget.payload!.merchantId,
      externalMerchantId: widget.payload!.externalMerchantId,
      email: _email,
      ticketId: widget.payload!.ticketId,
      ticketName: widget.payload!.ticketName,
      price: widget.payload!.price,
      serviceFee: widget.payload!.serviceFee,
      serviceTax: widget.payload!.serviceTax,
      orderFee: widget.payload!.orderFee,
      vat: widget.payload!.vat,
      quantity: widget.payload!.quantity,
      currency: widget.payload!.currency,
      paytrailEnabled: widget.payload!.paytrailEnabled,
      placeIds: widget.payload!.placeIds,
      seatTickets: widget.payload!.seatTickets,
      sessionId: widget.payload!.sessionId,
      country: widget.payload!.country,
      totalAmountOverride: widget.payload!.totalAmountOverride,
      finalPricePerTicket: widget.payload!.finalPricePerTicket,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PaymentScreen(payload: payload),
      ),
    );
  }

  @override 
  Widget build(BuildContext context) {
    final p = widget.payload;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: const Center(child: Text('Missing checkout data')),
      );
    }
    final breakdown = calculateTicketPrice(
      price: p.price,
      vat: p.vat,
      entertainmentTax: null,
      serviceTax: p.serviceTax,
      serviceFee: p.serviceFee,
      orderFee: 0,
    );
    final orderFeeTax = p.orderFee > 0 ? (p.orderFee * (p.serviceTax / 100)) : 0.0;
    final total = (breakdown.finalPricePerTicket * p.quantity) + p.orderFee + orderFeeTax;
    final theme = Theme.of(context);
    final taxLabel = (p.taxLabel != null && p.taxLabel!.trim().isNotEmpty) ? p.taxLabel!.trim() : 'VAT';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.eventName, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(p.quantity == 1 ? p.ticketName : '${p.ticketName} x ${p.quantity}', style: theme.textTheme.titleSmall),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    _priceRow(theme, 'Price', p.price * p.quantity, p.currency),
                    if (p.serviceFee > 0) _priceRow(theme, 'Service fee', p.serviceFee * p.quantity, p.currency),
                    if (breakdown.serviceFeeTaxAmount > 0)
                      _priceRow(theme, 'Service tax on service fee ${_fmtPct(breakdown.serviceTaxRate)}%', breakdown.serviceFeeTaxAmount * p.quantity, p.currency),
                    if (p.orderFee > 0) _priceRow(theme, 'Order fee (per transaction)', p.orderFee, p.currency),
                    if (orderFeeTax > 0)
                      _priceRow(theme, 'Service tax on order fee ${_fmtPct(breakdown.serviceTaxRate)}%', orderFeeTax, p.currency),
                    if (breakdown.vatAmountPerTicket > 0) _priceRow(theme, '$taxLabel ${_fmtPct(breakdown.vatRate)}%', breakdown.vatAmountPerTicket * p.quantity, p.currency),
                    const Divider(height: 16),
                    _priceRow(theme, 'Total', total, p.currency, bold: true),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter email';
                  if (!v.contains('@')) return 'Invalid email';
                  return null;
                },
                onSaved: (v) => _email = v ?? '',
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Confirm email'),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Confirm your email';
                  if (v != _emailController.text.trim()) return 'Emails do not match';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  child: const Text('Continue to payment'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
