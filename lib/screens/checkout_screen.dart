import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/checkout_payload.dart';
import '../services/discount_service.dart';
import '../navigation/adaptive_navigation.dart';
import '../utils/currency.dart';
import '../utils/money.dart';
import '../utils/privacy.dart';
import '../utils/seat_catalog_coupon.dart';
import '../utils/registration_form.dart';
import '../widgets/registration_form_fields.dart';
import '../widgets/legal_overflow_menu_button.dart';
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
  final _couponController = TextEditingController();
  late String _email;
  bool _marketingOptIn = false;

  bool _applyingCoupon = false;
  String? _couponError;
  String? _appliedCouponCode;
  String? _appliedCouponId;
  double? _appliedCouponDiscount;

  RegistrationFormSchema? _registrationForm;
  RegistrationAnswers _registrationAnswers = {};
  Map<String, String> _registrationFieldErrors = {};
  bool _isUploadingRegistrationFile = false;

  bool get _hasGaRegistrationForm {
    final p = widget.payload;
    if (p == null) return false;
    final hasSeats = (p.placeIds?.isNotEmpty ?? false) ||
        (p.seatTickets?.isNotEmpty ?? false) ||
        (p.sectionSelections?.isNotEmpty ?? false);
    return !hasSeats && (_registrationForm?.fields.isNotEmpty ?? false);
  }

  bool get _hasReservedSeatEmail {
    final p = widget.payload;
    return p?.reservationExpiresAtMs != null &&
        (p?.email.trim().isNotEmpty ?? false);
  }

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
    _marketingOptIn = widget.payload?.marketingOptIn ?? false;
    _registrationForm = registrationFormFromPayloadFields(
      widget.payload?.registrationFormFields,
    );
    _registrationAnswers = buildInitialRegistrationAnswers(_registrationForm);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _couponController.dispose();
    super.dispose();
  }

  CheckoutPayload _effectivePayload() {
    final w = widget.payload!;
    if (_appliedCouponCode == null ||
        _appliedCouponDiscount == null ||
        _appliedCouponDiscount! <= 0) {
      return w;
    }
    return w.mergeAppliedCoupon(
      couponCode: _appliedCouponCode!,
      couponId: _appliedCouponId,
      couponDiscountAmount: _appliedCouponDiscount!,
    );
  }

  bool get _canEnterDiscountCoupon {
    final p = widget.payload!;
    return p.hasDiscountCodes &&
        ((p.totalAmountOverride == null &&
                (p.placeIds == null || p.placeIds!.isEmpty) &&
                (p.seatTickets == null || p.seatTickets!.isEmpty)) ||
            (p.totalAmountOverride != null &&
                p.totalAmountOverride! > 0 &&
                p.seatTickets != null &&
                p.seatTickets!.isNotEmpty));
  }

  double _catalogBaseSubtotalForDiscountValidate(CheckoutPayload p) {
    if (p.totalAmountOverride != null && (p.seatTickets?.isNotEmpty ?? false)) {
      return seatTicketsCatalogSum(p.seatTickets!);
    }
    return roundMoney(p.price * p.quantity);
  }

  static Widget _priceRow(
    ThemeData theme,
    String label,
    double amount,
    String currency, {
    bool bold = false,
    bool isFinalTotal = false,
  }) {
    final formatted = isFinalTotal
        ? formatFinalTotal(amount, currency)
        : formatPrice(amount, currency);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: bold
                  ? theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    )
                  : theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            formatted,
            style: bold
                ? theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  )
                : theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Future<void> _applyCoupon() async {
    final p = widget.payload;
    if (p == null || !_canEnterDiscountCoupon) return;
    final typed = _couponController.text.trim();
    if (typed.isEmpty) {
      setState(() => _couponError = 'Enter a code');
      return;
    }
    setState(() {
      _applyingCoupon = true;
      _couponError = null;
    });
    try {
      final baseSubtotal = _catalogBaseSubtotalForDiscountValidate(p);
      final res = await validateEventDiscountCode(
        eventId: p.eventId,
        rawCode: typed,
        orderBaseSubtotal: baseSubtotal,
      );
      if (!mounted) return;
      if (!res.valid) {
        setState(() {
          _applyingCoupon = false;
          _couponError = res.error ?? 'Invalid code';
          _appliedCouponCode = null;
          _appliedCouponId = null;
          _appliedCouponDiscount = null;
        });
        return;
      }
      setState(() {
        _applyingCoupon = false;
        _couponError = null;
        _appliedCouponCode = res.code ?? typed.trim().toUpperCase();
        _appliedCouponId = res.couponId;
        _appliedCouponDiscount = res.discountAmount;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyingCoupon = false;
        _couponError = e.toString();
        _appliedCouponCode = null;
        _appliedCouponId = null;
        _appliedCouponDiscount = null;
      });
    }
  }

  void _clearCoupon() {
    setState(() {
      _appliedCouponCode = null;
      _appliedCouponId = null;
      _appliedCouponDiscount = null;
      _couponError = null;
      _couponController.clear();
    });
  }

  void _submit() {
    if (widget.payload == null) return;
    if (!_formKey.currentState!.validate()) return;
    if (_hasGaRegistrationForm) {
      final validation = validateRegistrationAnswersClient(
        _registrationForm,
        _registrationAnswers,
      );
      if (!validation.valid) {
        setState(() {
          _registrationFieldErrors = validation.fieldErrors;
        });
        return;
      }
    }
    if (_isUploadingRegistrationFile) return;
    _formKey.currentState!.save();
    final w = widget.payload!;
    final p = _effectivePayload();
    final payload = CheckoutPayload(
      eventId: w.eventId,
      eventName: w.eventName,
      merchantId: w.merchantId,
      externalMerchantId: w.externalMerchantId,
      email: _email,
      fullName: w.fullName,
      ticketId: w.ticketId,
      ticketName: w.ticketName,
      price: w.price,
      serviceFee: w.serviceFee,
      serviceTax: w.serviceTax,
      orderFee: w.orderFee,
      vat: w.vat,
      taxLabel: w.taxLabel,
      quantity: w.quantity,
      currency: w.currency,
      paytrailEnabled: w.paytrailEnabled,
      marketingOptIn: _marketingOptIn,
      placeIds: w.placeIds,
      sectionSelections: w.sectionSelections,
      seatTickets: w.seatTickets,
      sessionId: w.sessionId,
      country: w.country,
      reservationExpiresAtMs: w.reservationExpiresAtMs,
      totalAmountOverride: w.totalAmountOverride,
      finalPricePerTicket: w.finalPricePerTicket,
      hasDiscountCodes: w.hasDiscountCodes,
      couponCode: p.couponCode,
      couponId: p.couponId,
      couponDiscountAmount: p.couponDiscountAmount,
      registrationFormFields: w.registrationFormFields,
      registrationAnswers: serializeRegistrationAnswers(
        _hasGaRegistrationForm ? _registrationAnswers : null,
      ),
    );
    Navigator.of(context).push(
      adaptiveRoute(PaymentScreen(payload: payload)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.payload;
    if (w == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Checkout'),
          actions: const [LegalOverflowMenuButton()],
        ),
        body: const Center(child: Text('Missing checkout data')),
      );
    }
    final p = _effectivePayload();
    final line = computeTicketLinePricing(
      basePrice: p.effectiveUnitBaseForLine,
      serviceFee: p.serviceFee,
      vatRatePercent: p.vat,
      serviceTaxRatePercent: p.serviceTax,
      orderFee: p.orderFee,
      quantity: p.quantity,
    );
    final total = (p.totalAmountOverride != null && p.totalAmountOverride! > 0)
        ? p.totalCents / 100.0
        : line.total;
    final theme = Theme.of(context);
    final taxLabel = (p.taxLabel != null && p.taxLabel!.trim().isNotEmpty)
        ? p.taxLabel!.trim()
        : 'VAT';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: const [LegalOverflowMenuButton()],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(w.eventName, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                w.quantity == 1
                    ? w.ticketName
                    : '${w.ticketName} x ${w.quantity}',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    _priceRow(theme, 'Price', line.totalBasePrice, p.currency),
                    if (_appliedCouponCode != null &&
                        _appliedCouponDiscount != null &&
                        _appliedCouponDiscount! > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Discount code $_appliedCouponCode (−${formatPrice(roundMoney(_appliedCouponDiscount!), p.currency)})',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    if (line.totalServiceFee > 0)
                      _priceRow(
                        theme,
                        'Service fee',
                        line.totalServiceFee,
                        p.currency,
                      ),
                    if (line.totalServiceTaxAmount > 0)
                      _priceRow(
                        theme,
                        'Service tax on service fee ${_fmtPct(p.serviceTax)}%',
                        line.totalServiceTaxAmount,
                        p.currency,
                      ),
                    if (line.orderFee > 0)
                      _priceRow(
                        theme,
                        'Order fee (per transaction)',
                        line.orderFee,
                        p.currency,
                      ),
                    if (line.orderFeeServiceTax > 0)
                      _priceRow(
                        theme,
                        'Service tax on order fee ${_fmtPct(p.serviceTax)}%',
                        line.orderFeeServiceTax,
                        p.currency,
                      ),
                    if (line.totalVatAmount > 0)
                      _priceRow(
                        theme,
                        '$taxLabel ${_fmtPct(p.vat)}%',
                        line.totalVatAmount,
                        p.currency,
                      ),
                    const Divider(height: 16),
                    _priceRow(
                      theme,
                      'Total',
                      total,
                      p.currency,
                      bold: true,
                      isFinalTotal: true,
                    ),
                  ],
                ),
              ),
              if (_canEnterDiscountCoupon) ...[
                const SizedBox(height: 20),
                Text(
                  'Discount code',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _couponController,
                        autocorrect: false,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          hintText: 'Code',
                          isDense: true,
                          // M3 resolves inline label/hint layouts via a merge chain; if an
                          // inherited defaultStyle replaces titleMedium entirely, Flutter
                          // still uses `decoration.labelStyle` last — set baseline so
                          // InputDecorator's `labelStyle.textBaseline!` never sees null.
                          labelStyle: TextStyle(textBaseline: TextBaseline.alphabetic),
                        ),
                        onSubmitted: (_) =>
                            _applyingCoupon ? null : _applyCoupon(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _applyingCoupon ? null : _applyCoupon,
                      child: _applyingCoupon
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Apply'),
                    ),
                  ],
                ),
                if (_couponError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _couponError!,
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ],
                if (_appliedCouponDiscount != null &&
                    _appliedCouponDiscount! > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _clearCoupon,
                      child: const Text('Remove discount'),
                    ),
                  ),
              ],
              const SizedBox(height: 24),
              if (_hasReservedSeatEmail) ...[
                Text(
                  'Email: ${maskEmailForDisplay(w.email)}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
              ] else ...[
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
                    if (v != _emailController.text.trim()) {
                      return 'Emails do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
              ],
              CheckboxListTile(
                value: _marketingOptIn,
                onChanged: (v) => setState(() => _marketingOptIn = v ?? false),
                title: Text(
                  'Send me news and offers',
                  style: theme.textTheme.bodyMedium,
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              if (_hasGaRegistrationForm) ...[
                const SizedBox(height: 16),
                RegistrationFormFields(
                  eventId: w.eventId,
                  fields: _registrationForm!.fields,
                  answers: _registrationAnswers,
                  fieldErrors: _registrationFieldErrors,
                  onUploadingChange: (uploading) =>
                      setState(() => _isUploadingRegistrationFile = uploading),
                  onChanged: (fieldId, value) {
                    setState(() {
                      _registrationAnswers[fieldId] = value;
                      _registrationFieldErrors.remove(fieldId);
                    });
                  },
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isUploadingRegistrationFile ? null : _submit,
                  child: Text(
                    _isUploadingRegistrationFile
                        ? 'Uploading file…'
                        : 'Continue to payment',
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
