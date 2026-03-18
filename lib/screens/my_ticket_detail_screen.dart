import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/ticket.dart';
import '../services/guest_service.dart';
import '../utils/place_id_decoder.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Widget _buildQrWidget(BuildContext context, GuestTicket t) {
    final extractedQrPayload = _extractField(
      t.raw,
      [
        'ticketId',
        'qrPayload',
        'qr',
        'ticketCode',
        'otp',
        'entryCode',
        'code',
        'qrCode',
      ],
    );
    final qrPayload = extractedQrPayload.trim().isNotEmpty ? extractedQrPayload.trim() : t.id.trim();
    if (qrPayload.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
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
          SizedBox(width: 100, child: Text('$label:', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey))),
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
    final placeIdsRaw = t.raw?['placeIds'] ?? t.raw?['_clientPlaceIds'];
    String seatingLabel = mappedSeatingLabel.isNotEmpty
        ? mappedSeatingLabel
        : _seatLabelFromPlaceIds(placeIdsRaw);

    final extractedQrPayload = _extractField(
      t.raw,
      [
        'ticketId',
        'qrPayload',
        'qr',
        'ticketCode',
        'otp',
        'entryCode',
        'code',
        'qrCode',
      ],
    );
    final effectiveQrPayload =
        extractedQrPayload.trim().isNotEmpty ? extractedQrPayload.trim() : t.id.trim();
    final hasQr = effectiveQrPayload.isNotEmpty;

    // Seat ticket breakdown (optional for seated events).
    final seatTicketsRaw = t.raw?['ticketInfo'] is Map
        ? (t.raw?['ticketInfo']?['seatTickets'])
        : null;
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

    final currency = (t.currency ?? _extractField(t.raw, ['currency'])).trim();
    final bool usedModelBasePrice = (t.basePrice ?? '').trim().isNotEmpty;
    final bool usedModelServiceFee = (t.serviceFee ?? '').trim().isNotEmpty;
    final bool usedModelTotalAmount = (t.totalAmount ?? '').trim().isNotEmpty;

    String priceStr = usedModelBasePrice
        ? (t.basePrice ?? '').trim()
        : _extractField(t.raw, [
            'basePrice',
            'price',
            'ticketPrice',
            'subtotal',
            'unitPrice',
            'finalPrice',
            'finalPricePerTicket',
          ]);
    String serviceFeeStr = usedModelServiceFee
        ? (t.serviceFee ?? '').trim()
        : _extractField(t.raw, ['serviceFee', 'totalServiceFee', 'service_fee', 'ticketServiceFee']);
    String totalStr = usedModelTotalAmount
        ? (t.totalAmount ?? '').trim()
        : _extractField(t.raw, [
            'totalAmount',
            'total',
            'amount',
            'totalPaid',
            'grandTotal',
            'totalPaidAmount',
          ]);
    bool showPricing = priceStr.isNotEmpty || serviceFeeStr.isNotEmpty || totalStr.isNotEmpty;

    // If seat tickets exist, compute price/service fee/total from their per-seat pricing.
    if (seatTickets.isNotEmpty) {
      double totalBasePrice = 0;
      double totalServiceFee = 0;
      double totalAmount = 0;
      bool hasAnySeatLevelPricing = false;

      for (final st in seatTickets) {
        final pricingRaw = st['pricing'];
        if (pricingRaw is! Map) continue;
        final pricing = Map<String, dynamic>.from(pricingRaw);

        // Only consider the seat for computation if it has at least base price or service fee.
        final baseMaybe = pricing['basePrice'] ?? pricing['unitPrice'];
        final serviceFeeMaybe = pricing['serviceFee'];
        if (baseMaybe == null && serviceFeeMaybe == null) continue;

        hasAnySeatLevelPricing = true;

        final basePrice = _toDouble(pricing['basePrice'] ?? pricing['unitPrice']) ?? 0;
        final taxPct = _toDouble(pricing['tax'] ?? pricing['vat']) ?? 0;
        final serviceFee = _toDouble(pricing['serviceFee']) ?? 0;
        final serviceTaxPct = _toDouble(pricing['serviceTax']) ?? 0;
        final orderFee = _toDouble(pricing['orderFee']) ?? 0;

        totalBasePrice += basePrice;
        totalServiceFee += serviceFee;

        final baseTaxAmount = basePrice * (taxPct / 100);
        final serviceTaxAmount = serviceFee * (serviceTaxPct / 100);
        final orderFeeTaxAmount = orderFee * (serviceTaxPct / 100);

        totalAmount += (basePrice + baseTaxAmount + serviceFee + serviceTaxAmount + orderFee + orderFeeTaxAmount);
      }

      // If backend didn't provide per-seat pricing (pricing=null), fall back to the aggregate values.
      if (hasAnySeatLevelPricing) {
        priceStr = totalBasePrice.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
        serviceFeeStr = totalServiceFee.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
        totalStr = totalAmount.toStringAsFixed(2);
        showPricing = totalAmount > 0 || showPricing;
      }
    }

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
        'extractedQrPayloadLen=${extractedQrPayload.length} '
        'effectiveQrPayloadLen=${effectiveQrPayload.length}',
      );
      debugPrint(
        '[MyTicketDetailScreen][pricing] currency="$currency" '
        'basePrice(model)="${t.basePrice ?? ''}" usedModelBasePrice=$usedModelBasePrice '
        'serviceFee(model)="${t.serviceFee ?? ''}" usedModelServiceFee=$usedModelServiceFee '
        'totalAmount(model)="${t.totalAmount ?? ''}" usedModelTotalAmount=$usedModelTotalAmount '
        'priceStr="$priceStr" serviceFeeStr="$serviceFeeStr" totalStr="$totalStr" '
        'showPricing=$showPricing '
        'rawKeys=${t.raw?.keys.toList() ?? const <String>[]}',
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ticket'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (t.eventTitle != null && t.eventTitle!.isNotEmpty) Text(t.eventTitle!, style: Theme.of(context).textTheme.titleLarge),
            if (t.venue != null && t.venue!.isNotEmpty) Text(t.venue!, style: Theme.of(context).textTheme.bodySmall),
            if (t.ticketFor != null && t.ticketFor!.isNotEmpty) Text('Ticket for: ${t.ticketFor!}'),
            if (seatingLabel.isNotEmpty) Text(seatingLabel, style: Theme.of(context).textTheme.bodySmall),
            if (seatingLabel.isEmpty && (t.ticketName != null && t.ticketName!.isNotEmpty))
              Text(t.ticketName!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 24),
            Text('Ticket details', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
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
                  _infoRow(context, 'Qty', t.quantity ?? ''),
                  _infoRow(context, 'Order', t.orderId ?? ''),
                  if (entryCode.isNotEmpty) _infoRow(context, 'Entry code', entryCode),
                  _infoRow(context, 'Purchased', _formatDateReadable(t.purchaseDate)),
                  if (showPricing) ...[
                    const Divider(height: 24),
                    Text('Pricing', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    _infoRow(
                      context,
                      'Price',
                      priceStr.isNotEmpty ? '${priceStr}${currency.isNotEmpty ? ' $currency' : ''}' : '',
                    ),
                    _infoRow(
                      context,
                      'Service fee',
                      serviceFeeStr.isNotEmpty ? '${serviceFeeStr}${currency.isNotEmpty ? ' $currency' : ''}' : '',
                    ),
                    _infoRow(
                      context,
                      'Total',
                      totalStr.isNotEmpty ? '${totalStr}${currency.isNotEmpty ? ' $currency' : ''}' : '',
                    ),
                  ],
                  if ((t.paymentMethod ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _infoRow(context, 'Payment', t.paymentMethod ?? ''),
                  ],
                ],
              ),
            ),
            if (hasQr) ...[
              const SizedBox(height: 24),
              Text('QR Code', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Center(child: _buildQrWidget(context, t)),
            ],
          ],
        ),
      ),
    );
  }
}
