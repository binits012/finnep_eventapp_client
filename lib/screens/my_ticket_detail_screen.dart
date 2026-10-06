import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/ticket.dart';
import '../services/guest_service.dart';
import '../utils/currency.dart';
import '../utils/money.dart';
import '../utils/place_id_decoder.dart';
import '../utils/ticket_entry_qr.dart';
import '../widgets/legal_overflow_menu_button.dart';

void debugPrint(String? message, {int? wrapWidth}) {
  assert(() {
    if (message != null) developer.log(message);
    return true;
  }());
}

class MyTicketDetailScreen extends StatefulWidget {
  const MyTicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  State<MyTicketDetailScreen> createState() => _MyTicketDetailScreenState();
}

class _MyTicketDetailScreenState extends State<MyTicketDetailScreen> {
  GuestTicket? _ticket;
  bool _loading = true;
  String? _error;

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  Map<String, dynamic>? _extractTicketInfoMap(GuestTicket t) {
    final raw = t.raw;
    if (raw == null) return null;
    final ticketInfo = raw['ticketInfo'];
    if (ticketInfo is Map<String, dynamic>) return ticketInfo;
    if (ticketInfo is Map) return Map<String, dynamic>.from(ticketInfo);
    return null;
  }

  /// First non-null money value from [ticketInfo] then [raw] for the given keys.
  double? _firstMoney(
    Map<String, dynamic>? ticketInfo,
    Map<String, dynamic>? raw,
    List<String> keys,
  ) {
    for (final key in keys) {
      if (ticketInfo != null) {
        final fromInfo = _toDouble(ticketInfo[key]);
        if (fromInfo != null) return fromInfo;
      }
    }
    if (raw == null) return null;
    for (final key in keys) {
      final fromRaw = _toDouble(raw[key]);
      if (fromRaw != null) return fromRaw;
    }
    return null;
  }

  String _moneyAmountLabel(double? amount) {
    if (amount == null) return '';
    return roundMoney(amount).toStringAsFixed(2);
  }

  String _formatMoney(double? amount, String currency) {
    if (amount == null) return '';
    final c = normalizeDisplayCurrencyCode(currency.trim().isNotEmpty ? currency : 'EUR');
    return '${roundMoney(amount).toStringAsFixed(2)} $c';
  }

  String _withCurrency(String amountStr, String currency) {
    if (amountStr.isEmpty) return '';
    return currency.isNotEmpty ? '$amountStr $currency' : amountStr;
  }

  double? _resolveVatAmount(dynamic basePriceRaw, dynamic taxRaw) {
    final base = _toDouble(basePriceRaw);
    final tax = _toDouble(taxRaw);
    if (tax == null) return null;
    if (base == null) return tax;
    // tax can be either percent (e.g. 13.5) or already a money amount.
    if (tax >= 0 && tax <= 100) {
      return base * (tax / 100);
    }
    return tax;
  }

  double? _resolveSeatServiceTax(Map<String, dynamic> pricing) {
    final explicit = _toDouble(
      pricing['serviceTaxAmount'] ?? pricing['serviceTax'],
    );
    if (explicit != null) {
      // Rate percent (0–100) with no money amount key → compute from service fee.
      final asRateKey = pricing['serviceTaxAmount'] == null &&
          pricing['serviceTax'] != null &&
          explicit > 0 &&
          explicit <= 100;
      if (asRateKey) {
        final fee = _toDouble(pricing['serviceFee']) ?? 0;
        if (fee > 0) return moneyPercentOf(fee, explicit);
        return null;
      }
      return explicit;
    }
    return null;
  }

  String _formatDateReadable(String? raw) {
    if (raw == null) return '';
    final v = raw.trim();
    if (v.isEmpty) return '';
    final dt = DateTime.tryParse(v);
    if (dt == null) return raw;
    // Prefer date-only display unless time is present.
    final hasTime = v.contains('T') || v.contains(':');
    return hasTime ? DateFormat.yMMMd().add_jm().format(dt) : DateFormat.yMMMd().format(dt);
  }

  bool _isEventEnded(GuestTicket t) {
    final eventEndRaw = _extractField(t.raw, ['eventEndDate', 'event_end_date', 'eventDate']);
    if (eventEndRaw.isEmpty) return false;
    final eventEnd = DateTime.tryParse(eventEndRaw);
    if (eventEnd == null) return false;
    return eventEnd.toLocal().isBefore(DateTime.now().toLocal());
  }

  String _extractField(Map<String, dynamic>? raw, List<String> keys) {
    if (raw == null) return '';

    // Backend response may place fields under `ticketInfo` or directly under `data`.
    final ticketInfo = raw['ticketInfo'];
    final ticketInfoMap = ticketInfo is Map<String, dynamic> ? ticketInfo : null;
    final event = raw['event'];
    final eventMap = event is Map<String, dynamic> ? event : null;

    for (final key in keys) {
      final v = raw[key];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }

    if (ticketInfoMap != null) {
      for (final key in keys) {
        final v = ticketInfoMap[key];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
    }

    if (eventMap != null) {
      for (final key in keys) {
        final v = eventMap[key];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
    }

    return '';
  }

  String _seatLabelFromPlaceIds(dynamic placeIdsRaw) {
    if (placeIdsRaw is! List) return '';
    final decoded = <DecodedPlaceId>[];
    for (final pid in placeIdsRaw) {
      final s = pid?.toString().trim() ?? '';
      if (s.isEmpty) continue;
      final d = decodePlaceId(s);
      if (d != null) decoded.add(d);
    }
    if (decoded.isEmpty) return '';

    final first = decoded.first;
    final rawSection = first.section.trim();
    final section = rawSection.toLowerCase().startsWith('section')
        ? rawSection
        : 'Section $rawSection';

    if (decoded.length == 1) {
      return '$section · Row ${first.row} · Seat ${first.seat}';
    }
    return '$section · Row ${first.row} · Seat ${first.seat} (+${decoded.length - 1} more)';
  }

  String _sectionSelectionsLabel(dynamic sectionSelectionsRaw) {
    if (sectionSelectionsRaw is! List) return '';
    final labels = <String>[];
    for (final item in sectionSelectionsRaw) {
      if (item is! Map) continue;
      final sectionName = (item['sectionName'] ?? item['name'] ?? item['sectionId'] ?? '').toString().trim();
      final qty = (item['quantity'] ?? '').toString().trim();
      if (sectionName.isEmpty) continue;
      labels.add(qty.isNotEmpty ? '$sectionName x$qty' : sectionName);
    }
    if (labels.isEmpty) return '';
    return labels.join(' · ');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Widget _buildQrWidget(BuildContext context, GuestTicket t) {
    final qrPayload = t.id.trim();
    if (qrPayload.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: QrImageView(
        data: qrPayload,
        version: QrVersions.auto,
        size: 200,
        backgroundColor: Colors.white,
      ),
    );
  }

  Widget _buildGuestQrSection(BuildContext context, List<Map<String, dynamic>> children) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Entry codes for each guest',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Each guest should show their own code at the entrance.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        ...children.asMap().entries.map((e) {
          final i = e.key;
          final m = e.value;
          final rawIdx = m['childIndex'];
          final idx = rawIdx is num ? rawIdx.toInt() : i + 1;
          final val = m['childQrCodeValue']?.toString() ?? '';
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Guest $idx', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.shadow.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: val,
                      version: QrVersions.auto,
                      size: 200,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await getTicketById(widget.ticketId);
      setState(() {
        _ticket = t;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ticket')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _ticket == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ticket')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error ?? 'Not found'),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final t = _ticket!;

    final entryCode = _extractField(
      t.raw,
      ['otp', 'entryCode', 'ticketCode', 'code'],
    );

    final section = _extractField(t.raw, ['section', 'seatSection', 'zone', 'area']);
    final row = _extractField(t.raw, ['row', 'seatRow']);
    final seat = _extractField(t.raw, ['seat', 'seatNumber', 'seatNo']);
    final mappedSeatingLabel = [section, row, seat].where((x) => x.isNotEmpty).join(' · ');
    final ticketInfoMap = _extractTicketInfoMap(t);
    final placeIdsRaw = t.raw?['placeIds'] ?? t.raw?['_clientPlaceIds'];
    final sectionSelectionsRaw = t.raw?['sectionSelections'] ?? ticketInfoMap?['sectionSelections'];
    String seatingLabel = mappedSeatingLabel.isNotEmpty
        ? mappedSeatingLabel
        : _seatLabelFromPlaceIds(placeIdsRaw);
    if (seatingLabel.isEmpty) {
      seatingLabel = _sectionSelectionsLabel(sectionSelectionsRaw);
    }

    final effectiveQrPayload = t.id.trim();
    final orderQty = parseTicketOrderQuantity(t.quantity, ticketInfoMap);
    final showMasterQr = showMasterEntryQrOnClient(orderQty);
    final childQrCodes = parseChildQrCodes(ticketInfoMap);
    final hasQr = effectiveQrPayload.isNotEmpty;
    final showMasterQrBlock = showMasterQr && hasQr;
    final showGuestQrBlock = !showMasterQr && childQrCodes.isNotEmpty;

    // Seat ticket breakdown (optional for seated events).
    final seatTicketsRaw = ticketInfoMap?['seatTickets'];
    final List<Map<String, dynamic>> seatTickets = [];
    if (seatTicketsRaw is List) {
      for (final item in seatTicketsRaw) {
        if (item is Map) {
          seatTickets.add(Map<String, dynamic>.from(item));
        }
      }
    }

    if (seatTickets.isNotEmpty) {
      final firstName = (seatTickets.first['ticketName'] ?? '').toString().trim();
      if (firstName.isNotEmpty) {
        final more = seatTickets.length > 1 ? ' +${seatTickets.length - 1} more' : '';
        seatingLabel = '$firstName$more';
      }
    }

    final currencyRaw = (t.currency ?? _extractField(t.raw, ['currency'])).trim();
    final currency = normalizeDisplayCurrencyCode(currencyRaw.isNotEmpty ? currencyRaw : 'EUR');
    final bool usedModelBasePrice = (t.basePrice ?? '').trim().isNotEmpty;
    final bool usedModelServiceFee = (t.serviceFee ?? '').trim().isNotEmpty;
    final bool usedModelTotalAmount = (t.totalAmount ?? '').trim().isNotEmpty;

    // Prefer API aggregate money fields (ticketInfo / model / raw).
    double? apiTotalAmount = usedModelTotalAmount
        ? _toDouble(t.totalAmount)
        : _firstMoney(ticketInfoMap, t.raw, [
            'totalAmount',
            'total',
            'amount',
            'totalPaid',
            'grandTotal',
            'totalPaidAmount',
          ]);
    double? apiBasePrice = usedModelBasePrice
        ? _toDouble(t.basePrice)
        : _firstMoney(ticketInfoMap, t.raw, [
            'totalBasePrice',
            'basePrice',
            'catalogTotalBasePrice',
            'ticketPrice',
            'subtotal',
            'unitPrice',
          ]);
    // Do not treat remapped `price` as Total; only use as base fallback if no base yet.
    apiBasePrice ??= _firstMoney(ticketInfoMap, t.raw, ['price', 'finalPrice', 'finalPricePerTicket']);
    double? apiCatalogBase = _firstMoney(ticketInfoMap, t.raw, ['catalogTotalBasePrice']);
    double? apiServiceFee = usedModelServiceFee
        ? _toDouble(t.serviceFee)
        : _firstMoney(ticketInfoMap, t.raw, [
            'totalServiceFee',
            'serviceFee',
            'service_fee',
            'ticketServiceFee',
          ]);
    double? apiVatAmount = _firstMoney(ticketInfoMap, t.raw, [
      'vatAmount',
      'totalVatAmount',
      'taxAmount',
      'entertainmentTaxAmount',
    ]);
    double? apiVatRate = _firstMoney(ticketInfoMap, t.raw, ['vatRate']);
    if (apiVatRate != null && (apiVatRate < 0 || apiVatRate > 100)) {
      apiVatRate = null;
    }
    double? apiServiceTax = _firstMoney(ticketInfoMap, t.raw, [
      'serviceTaxAmount',
      'totalServiceTaxAmount',
    ]);
    double? apiOrderFee = _firstMoney(ticketInfoMap, t.raw, [
      'orderFee',
      'totalOrderFee',
    ]);
    double? apiOrderFeeServiceTax = _firstMoney(ticketInfoMap, t.raw, [
      'orderFeeServiceTax',
    ]);
    double? apiCouponDiscount = _firstMoney(ticketInfoMap, t.raw, [
      'couponDiscountAmount',
      'discountAmount',
    ]);
    final couponCode = () {
      final fromInfo = ticketInfoMap?['couponCode']?.toString().trim() ?? '';
      if (fromInfo.isNotEmpty) return fromInfo;
      return (t.raw?['couponCode']?.toString() ?? '').trim();
    }();

    double? priceNum = apiBasePrice;
    double? serviceFeeNum = apiServiceFee;
    double? vatNum = apiVatAmount;
    double? serviceTaxNum = apiServiceTax;
    double? orderFeeNum = apiOrderFee;
    double? orderFeeServiceTaxNum = apiOrderFeeServiceTax;
    double? discountNum = apiCouponDiscount;
    double? totalNum = (apiTotalAmount != null && apiTotalAmount > 0) ? apiTotalAmount : null;
    double? catalogBaseNum = apiCatalogBase;

    // Seat recompute fills gaps and provides line-item transparency; never overwrite a valid API total.
    if (seatTickets.isNotEmpty) {
      double seatBaseSum = 0;
      double seatServiceFeeSum = 0;
      double seatVatSum = 0;
      double seatServiceTaxSum = 0;
      double seatOrderFeeMax = 0;
      bool hasAnySeatLevelPricing = false;

      for (final st in seatTickets) {
        final pricingRaw = st['pricing'];
        if (pricingRaw is! Map) continue;
        final pricing = Map<String, dynamic>.from(pricingRaw);

        final baseMaybe = pricing['basePrice'] ?? pricing['unitPrice'];
        final serviceFeeMaybe = pricing['serviceFee'];
        if (baseMaybe == null && serviceFeeMaybe == null) continue;

        hasAnySeatLevelPricing = true;

        final basePrice = _toDouble(pricing['basePrice'] ?? pricing['unitPrice']) ?? 0;
        final vatAmount =
            _resolveVatAmount(pricing['basePrice'] ?? pricing['unitPrice'], pricing['tax'] ?? pricing['vat']) ??
                0;
        final serviceFee = _toDouble(pricing['serviceFee']) ?? 0;
        final serviceTax = _resolveSeatServiceTax(pricing) ?? 0;
        final seatOrderFee = _toDouble(pricing['orderFee']) ?? 0;

        seatBaseSum += basePrice;
        seatServiceFeeSum += serviceFee;
        seatVatSum += vatAmount;
        seatServiceTaxSum += serviceTax;
        if (seatOrderFee > seatOrderFeeMax) {
          seatOrderFeeMax = seatOrderFee;
        }
      }

      if (hasAnySeatLevelPricing) {
        priceNum ??= seatBaseSum;
        if (serviceFeeNum == null || serviceFeeNum == 0) {
          serviceFeeNum = seatServiceFeeSum;
        }
        vatNum ??= seatVatSum;
        if (serviceTaxNum == null || serviceTaxNum == 0) {
          serviceTaxNum = seatServiceTaxSum;
        }
        // Prefer aggregate ticketInfo.orderFee; otherwise take max once across seats (not a sum).
        if (orderFeeNum == null || orderFeeNum == 0) {
          orderFeeNum = seatOrderFeeMax > 0 ? seatOrderFeeMax : orderFeeNum;
        }

        if (totalNum == null) {
          final seatPartsTotal = seatBaseSum +
              seatVatSum +
              seatServiceFeeSum +
              seatServiceTaxSum +
              (orderFeeNum ?? 0) +
              (orderFeeServiceTaxNum ?? 0);
          if (seatPartsTotal > 0) {
            totalNum = seatPartsTotal;
          }
        }
      }
    }

    // Display base: catalog base when a coupon discount was applied.
    final displayBaseNum = (discountNum != null && discountNum > 0 && catalogBaseNum != null && catalogBaseNum > 0)
        ? catalogBaseNum
        : priceNum;

    final bool showPricing = [
          displayBaseNum,
          discountNum,
          serviceFeeNum,
          vatNum,
          serviceTaxNum,
          orderFeeNum,
          orderFeeServiceTaxNum,
          totalNum,
          apiTotalAmount,
          apiBasePrice,
        ].any((v) => v != null) ||
        seatTickets.isNotEmpty;

    final isFreeTicket = [
      displayBaseNum,
      discountNum,
      serviceFeeNum,
      vatNum,
      serviceTaxNum,
      orderFeeNum,
      orderFeeServiceTaxNum,
      totalNum,
    ].every((v) => v == null || v == 0);
    final isEventEnded = _isEventEnded(t);

    final String vatRowLabel = apiVatRate != null
        ? 'VAT (${apiVatRate.toStringAsFixed(apiVatRate % 1 == 0 ? 0 : 1)}%)'
        : 'VAT';

    if (kDebugMode) {
      final placeIdsSample = placeIdsRaw is List && placeIdsRaw.isNotEmpty
          ? placeIdsRaw.take(1).map((e) => e.toString()).toList()
          : <String>[];
      debugPrint(
        '[MyTicketDetailScreen] ticketId=${widget.ticketId} '
        'eventTitle="${t.eventTitle ?? ''}" '
        'eventDate="${t.eventDate ?? ''}" '
        'venue="${t.venue ?? ''}" '
        'ticketName(model)="${t.ticketName ?? ''}" '
        'ticketForPresent="${t.ticketFor?.isNotEmpty == true}" '
        'paymentMethod="${t.paymentMethod ?? ''}"',
      );
      debugPrint(
        '[MyTicketDetailScreen][seating] mappedSeatingLabel="$mappedSeatingLabel" '
        'section="$section" row="$row" seat="$seat" '
        'placeIdsRawType=${placeIdsRaw.runtimeType} '
        'placeIdsSample=$placeIdsSample '
        'seatingLabel="$seatingLabel"',
      );
      debugPrint(
        '[MyTicketDetailScreen][entry] entryCodeLen=${entryCode.length} '
        'effectiveQrPayloadLen=${effectiveQrPayload.length}',
      );
      debugPrint(
        '[MyTicketDetailScreen][pricing] currency="$currency" '
        'basePrice(model)="${t.basePrice ?? ''}" usedModelBasePrice=$usedModelBasePrice '
        'serviceFee(model)="${t.serviceFee ?? ''}" usedModelServiceFee=$usedModelServiceFee '
        'totalAmount(model)="${t.totalAmount ?? ''}" usedModelTotalAmount=$usedModelTotalAmount '
        'priceNum=$priceNum serviceFeeNum=$serviceFeeNum vatNum=$vatNum '
        'serviceTaxNum=$serviceTaxNum orderFeeNum=$orderFeeNum discountNum=$discountNum '
        'totalNum=$totalNum couponCode="$couponCode" showPricing=$showPricing '
        'rawKeys=${t.raw?.keys.toList() ?? const <String>[]}',
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ticket'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: const [LegalOverflowMenuButton()],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (t.eventTitle != null && t.eventTitle!.isNotEmpty) Text(t.eventTitle!, style: Theme.of(context).textTheme.titleLarge),
            if (t.venue != null && t.venue!.isNotEmpty) Text(t.venue!, style: Theme.of(context).textTheme.bodySmall),
            if (isEventEnded)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Past event',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (t.ticketFor != null && t.ticketFor!.isNotEmpty) Text('Ticket for: ${t.ticketFor!}'),
            if (seatingLabel.isNotEmpty) Text(seatingLabel, style: Theme.of(context).textTheme.bodySmall),
            if (seatingLabel.isEmpty && (t.ticketName != null && t.ticketName!.isNotEmpty))
              Text(t.ticketName!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 24),
            Text('Payment details', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _infoRow(context, 'Date', _formatDateReadable(t.eventDate)),
                  _infoRow(context, 'Venue', t.venue ?? ''),
                  _infoRow(
                    context,
                    'Seating',
                    seatingLabel.isNotEmpty ? seatingLabel : (t.ticketName ?? ''),
                  ),
                  _infoRow(context, 'Attendee', t.ticketFor ?? ''),
                  _infoRow(context, 'Ticket', t.ticketName ?? ''),
                  _infoRow(context, 'Qty', t.quantity ?? ''),
                  _infoRow(context, 'Order', t.orderId ?? ''),
                  if (entryCode.isNotEmpty) _infoRow(context, 'Entry code', entryCode),
                  _infoRow(context, 'Purchased', _formatDateReadable(t.purchaseDate)),
                  if (showPricing) ...[
                    const Divider(height: 24),
                    if (isFreeTicket) ...[
                      _infoRow(context, 'Pricing', 'Free Ticket'),
                    ] else ...[
                    if (seatTickets.isNotEmpty) ...[
                      Text(
                        'Ticket line items',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      ...seatTickets.asMap().entries.map((entry) {
                        final index = entry.key;
                        final st = entry.value;
                        final pricingRaw = st['pricing'];
                        final pricing = pricingRaw is Map ? Map<String, dynamic>.from(pricingRaw) : <String, dynamic>{};
                        final rawLineCur = (pricing['currency']?.toString() ?? '').trim();
                        final lineCurrency = normalizeDisplayCurrencyCode(
                          rawLineCur.isNotEmpty ? rawLineCur : (currencyRaw.isNotEmpty ? currencyRaw : 'EUR'),
                        );
                        final lineBase = _toDouble(pricing['basePrice'] ?? pricing['unitPrice']);
                        final lineServiceFee = _toDouble(pricing['serviceFee']);
                        final lineVat = _resolveVatAmount(
                          pricing['basePrice'] ?? pricing['unitPrice'],
                          pricing['tax'] ?? pricing['vat'],
                        );
                        final lineServiceTax = _resolveSeatServiceTax(pricing);
                        final lineName = (st['ticketName'] ?? '').toString().trim();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).dividerColor),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lineName.isNotEmpty ? lineName : 'Ticket ${index + 1}',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              _infoRow(context, 'Price', _formatMoney(lineBase, lineCurrency)),
                              _infoRow(context, 'Service fee', _formatMoney(lineServiceFee, lineCurrency)),
                              _infoRow(context, 'VAT', _formatMoney(lineVat, lineCurrency)),
                              if (lineServiceTax != null && lineServiceTax > 0)
                                _infoRow(context, 'Service tax', _formatMoney(lineServiceTax, lineCurrency)),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                    ],
                    if (displayBaseNum != null && displayBaseNum > 0)
                      _infoRow(
                        context,
                        'Price',
                        _withCurrency(_moneyAmountLabel(displayBaseNum), currency),
                      ),
                    if (discountNum != null && discountNum > 0)
                      _infoRow(
                        context,
                        couponCode.isNotEmpty ? 'Discount ($couponCode)' : 'Discount',
                        _withCurrency(_moneyAmountLabel(discountNum), currency),
                      ),
                    if (serviceFeeNum != null && serviceFeeNum > 0)
                      _infoRow(
                        context,
                        'Service fee',
                        _withCurrency(_moneyAmountLabel(serviceFeeNum), currency),
                      ),
                    if (vatNum != null && vatNum > 0)
                      _infoRow(
                        context,
                        vatRowLabel,
                        _withCurrency(_moneyAmountLabel(vatNum), currency),
                      ),
                    if (serviceTaxNum != null && serviceTaxNum > 0)
                      _infoRow(
                        context,
                        'Service tax',
                        _withCurrency(_moneyAmountLabel(serviceTaxNum), currency),
                      ),
                    if (orderFeeNum != null && orderFeeNum > 0)
                      _infoRow(
                        context,
                        'Order fee',
                        _withCurrency(_moneyAmountLabel(orderFeeNum), currency),
                      ),
                    if (orderFeeServiceTaxNum != null && orderFeeServiceTaxNum > 0)
                      _infoRow(
                        context,
                        'Order fee tax',
                        _withCurrency(_moneyAmountLabel(orderFeeServiceTaxNum), currency),
                      ),
                    _infoRow(
                      context,
                      'Total',
                      totalNum != null ? formatFinalTotal(totalNum, currency.isNotEmpty ? currency : 'EUR') : '',
                    ),
                    ],
                  ],
                  if ((t.paymentMethod ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _infoRow(context, 'Payment', t.paymentMethod ?? ''),
                  ],
                ],
              ),
            ),
            if (showMasterQrBlock) ...[
              const SizedBox(height: 24),
              Text('QR Code', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Center(child: _buildQrWidget(context, t)),
            ],
            if (showGuestQrBlock) ...[
              const SizedBox(height: 24),
              _buildGuestQrSection(context, childQrCodes),
            ],
          ],
        ),
      ),
    );
  }
}
