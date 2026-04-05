import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/ticket.dart';
import '../services/guest_service.dart';
import '../utils/currency.dart';
import '../utils/place_id_decoder.dart';
import '../utils/ticket_entry_qr.dart';

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

  String _formatMoney(double? amount, String currency) {
    if (amount == null) return '';
    final c = normalizeDisplayCurrencyCode(currency.trim().isNotEmpty ? currency : 'EUR');
    return '${amount.toStringAsFixed(3)} $c';
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
    final sectionSelectionsRaw = t.raw?['sectionSelections'] ??
        (t.raw?['ticketInfo'] is Map ? (t.raw?['ticketInfo']?['sectionSelections']) : null);
    String seatingLabel = mappedSeatingLabel.isNotEmpty
        ? mappedSeatingLabel
        : _seatLabelFromPlaceIds(placeIdsRaw);
    if (seatingLabel.isEmpty) {
      seatingLabel = _sectionSelectionsLabel(sectionSelectionsRaw);
    }

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
    final ticketInfoMap = t.raw?['ticketInfo'] is Map<String, dynamic>
        ? t.raw!['ticketInfo'] as Map<String, dynamic>
        : (t.raw?['ticketInfo'] is Map ? Map<String, dynamic>.from(t.raw!['ticketInfo'] as Map) : null);
    final orderQty = parseTicketOrderQuantity(t.quantity, ticketInfoMap);
    final showMasterQr = showMasterEntryQrOnClient(orderQty);
    final childQrCodes = parseChildQrCodes(ticketInfoMap);
    final hasQr = effectiveQrPayload.isNotEmpty;
    final showMasterQrBlock = showMasterQr && hasQr;
    final showGuestQrBlock = !showMasterQr && childQrCodes.isNotEmpty;

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

    final currencyRaw = (t.currency ?? _extractField(t.raw, ['currency'])).trim();
    final currency = normalizeDisplayCurrencyCode(currencyRaw.isNotEmpty ? currencyRaw : 'EUR');
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
    String vatStr = _extractField(t.raw, [
      'vatAmount',
      'totalVatAmount',
      'taxAmount',
      'entertainmentTaxAmount',
    ]);
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
    bool showPricing = priceStr.isNotEmpty || serviceFeeStr.isNotEmpty || vatStr.isNotEmpty || totalStr.isNotEmpty;

    // If seat tickets exist, compute price/service fee/total from their per-seat pricing.
    if (seatTickets.isNotEmpty) {
      double totalBasePrice = 0;
      double totalServiceFee = 0;
      double totalVatAmount = 0;
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
        final vatAmount = _resolveVatAmount(pricing['basePrice'] ?? pricing['unitPrice'], pricing['tax'] ?? pricing['vat']) ?? 0;
        final serviceFee = _toDouble(pricing['serviceFee']) ?? 0;

        totalBasePrice += basePrice;
        totalServiceFee += serviceFee;
        totalVatAmount += vatAmount;

        totalAmount += (basePrice + vatAmount + serviceFee);
      }

      // If backend didn't provide per-seat pricing (pricing=null), fall back to the aggregate values.
      if (hasAnySeatLevelPricing) {
        priceStr = totalBasePrice.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
        serviceFeeStr = totalServiceFee.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
        vatStr = totalVatAmount.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
        totalStr = totalAmount.toStringAsFixed(2);
        showPricing = totalAmount > 0 || showPricing;
      }
    }

    final priceNum = _toDouble(priceStr);
    final serviceFeeNum = _toDouble(serviceFeeStr);
    final vatNum = _toDouble(vatStr);
    final totalNum = _toDouble(totalStr);
    final isFreeTicket = [priceNum, serviceFeeNum, vatNum, totalNum].every((v) => v == null || v == 0);
    final isEventEnded = _isEventEnded(t);

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
                        final lineVat = _resolveVatAmount(pricing['basePrice'] ?? pricing['unitPrice'], pricing['tax'] ?? pricing['vat']);
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
                              Text(lineName.isNotEmpty ? lineName : 'Ticket ${index + 1}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                              _infoRow(context, 'Price', _formatMoney(lineBase, lineCurrency)),
                              _infoRow(context, 'Service fee', _formatMoney(lineServiceFee, lineCurrency)),
                              _infoRow(context, 'VAT', _formatMoney(lineVat, lineCurrency)),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                    ],
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
                      'VAT',
                      vatStr.isNotEmpty ? '${vatStr}${currency.isNotEmpty ? ' $currency' : ''}' : '',
                    ),
                    _infoRow(
                      context,
                      'Total',
                      totalStr.isNotEmpty ? '${totalStr}${currency.isNotEmpty ? ' $currency' : ''}' : '',
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
