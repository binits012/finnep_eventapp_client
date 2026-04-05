import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';

import '../models/checkout_payload.dart';
import '../models/event.dart';
import '../models/seat.dart';
import '../services/event_service.dart';
import '../services/seat_service.dart';
import '../utils/currency.dart';
import '../utils/place_id_decoder.dart';
import '../widgets/seat_map_canvas.dart';
import 'payment_screen.dart';

enum SeatStep { seats, info, otp, payment }

class SeatSelectionScreen extends StatefulWidget {
  const SeatSelectionScreen({super.key, required this.eventId});

  final String eventId;

  @override
  State<SeatSelectionScreen> createState() => _SeatSelectionScreenState();
}

class _SeatSelectionScreenState extends State<SeatSelectionScreen> {
  SeatStep _step = SeatStep.seats;
  SeatMapData? _seatData;
  List<SeatModel> _seats = [];
  Event? _event;
  bool _loading = true;
  String? _error;
  final List<String> _selectedPlaceIds = [];
  final Map<String, int> _areaSelectionMap = {};
  String? _areaTicketId;
  /// When pricingModel is ticket_info: placeId -> ticketId (chosen ticket type per seat).
  final Map<String, String> _seatTicketMap = {};
  String _sessionId = '';
  String _fullName = '';
  String _email = '';
  String _confirmEmail = '';
  String _otp = '';
  static const int _reservationDurationSeconds = 10 * 60;
  int? _reservationExpiresAtMs;
  Duration _reservationRemaining = Duration.zero;
  Timer? _reservationTimer;

  List<AreaSectionModel> get _purchasableAreaSections {
    final all = _seatData?.areaSections ?? const <AreaSectionModel>[];
    return all.where((a) => a.isPurchasableForAreaFlow).toList();
  }

  List<Map<String, dynamic>> get _sectionSelections {
    final areaById = <String, AreaSectionModel>{
      for (final area in _purchasableAreaSections) area.id: area,
    };
    return _areaSelectionMap.entries
        .where((e) => e.value > 0 && areaById.containsKey(e.key))
        .map((e) => <String, dynamic>{
              'sectionId': e.key,
              'sectionName': areaById[e.key]?.name,
              'quantity': e.value,
            })
        .toList();
  }

  int get _selectedTotalQty {
    final areaQty = _areaSelectionMap.values.fold<int>(0, (sum, qty) => sum + qty);
    return _selectedPlaceIds.length + areaQty;
  }

  /// Round to 3 decimals (matches backend Math.round(x * 1000) / 1000).
  static double _round3(double x) => (x * 1000).round() / 1000.0;

  String _tx(String key) {
    final lang = Localizations.localeOf(context).languageCode.toLowerCase();
    const labels = <String, Map<String, String>>{
      'en': {
        'selectSeatsAreasMax': 'Select seats/areas (max 10)',
        'ticket': 'ticket',
        'tickets': 'tickets',
        'selected': 'selected',
        'details': 'Details',
        'continue': 'Continue',
        'standingAreaSections': 'Standing / Area Sections',
        'available': 'Available',
        'price': 'Price',
        'soldOut': 'Sold Out',
        'areaPass': 'Area Pass',
      }
    };
    final fallback = labels['en']!;
    final selected = labels[lang] ?? fallback;
    return selected[key] ?? fallback[key] ?? key;
  }

  /// Single source of truth for "Total (N seats)" — used for display and for payment. No rounding.
  double get _selectedSeatsTotal {
    final selected = _seats.where((s) => _selectedPlaceIds.contains(s.placeId)).toList();
    var total = selected.fold<double>(0, (sum, s) => sum + (_effectiveSeatPrice(s) ?? 0));
    final areaQty = _areaSelectionMap.values.fold<int>(0, (sum, qty) => sum + qty);
    if (areaQty > 0) {
      if (_useTicketInfoPricing) {
        final areaTicket = _effectiveAreaTicket;
        if (areaTicket != null) {
          total += (areaTicket.totalPerTicket * areaQty);
        }
      } else {
        final areaSections = _purchasableAreaSections;
        for (final entry in _areaSelectionMap.entries) {
          if (entry.value <= 0) continue;
          final areaId = entry.key;
          AreaSectionModel? area;
          for (final a in areaSections) {
            if (a.id == areaId) {
              area = a;
              break;
            }
          }
          final unitPrice = area == null ? null : _areaUnitPrice(area);
          if (unitPrice != null) total += unitPrice * entry.value;
        }
      }
    }
    return total;
  }

  /// Canvas should render only real seat dots.
  /// Area/standing sections are selected via the counter list, not via seat circles.
  List<SeatModel> get _canvasSeats {
    final areaNames = (_seatData?.areaSections ?? const <AreaSectionModel>[])
        .where((a) => a.selectionMode.toLowerCase() == 'area')
        .map((a) => a.name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
    if (areaNames.isEmpty) return _seats;
    return _seats.where((seat) {
      final section = (seat.section ?? '').trim().toLowerCase();
      if (section.isEmpty) return true;
      return !areaNames.contains(section);
    }).toList();
  }

  /// Look up the PricingTier for a seat via its placeId tierCode.
  PricingTier? _tierForSeat(SeatModel seat) {
    final config = _seatData?.pricingConfig;
    if (config == null) return null;
    final decoded = decodePlaceId(seat.placeId);
    if (decoded == null || decoded.tierCode.isEmpty) return null;
    for (final t in config.tiers) {
      if (t.id == decoded.tierCode) return t;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // PRICING MODEL RULES (single source of truth — do not mix)
  // ---------------------------------------------------------------------------
  // • ticket_info (venue.pricingModel == 'ticket_info'):
  //   - All prices, breakdown, and totals come ONLY from event.ticketInfo.
  //   - Per-seat choice stored in _seatTicketMap (placeId -> ticketId).
  //   - Do NOT use seat.price, seat.basePrice, seat.taxAmount (decoded from placeIds).
  //   - Display: ticket name + Base Price, Tax(%), Total from TicketInfo (3 decimals).
  //   - Payment: totalAmountOverride = backend formula (entertainmentTax, per-seat round, orderFee once); seatTickets array.
  //   - Backend uses entertainmentTax (not vat) for seatTickets; total = sum(perSeat round3) + round3(orderFee+orderFeeTax).
  // • pricing_configuration (venue.pricingModel == 'pricing_configuration'):
  //   - All prices, breakdown, and totals come ONLY from decoded seat data (tiers/zones).
  //   - Do NOT use event.ticketInfo for price calculation or display.
  //   - Display: SECTION/ROW/SEAT + seat.basePrice, seat.taxAmount, seat.price (3 decimals).
  //   - Payment: totalAmountOverride = sum(seat.price) + orderFee only (seat.price is already base+tax+serviceFee from tier).
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    debugPrint('[SeatSelection] initState — eventId=${widget.eventId}');
    _sessionId = _generateUuid();
    _load();
  }

  @override
  void dispose() {
    _reservationTimer?.cancel();
    super.dispose();
  }

  String _generateUuid() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replaceAllMapped(
      RegExp(r'[xy]'),
      (m) {
        final r = (DateTime.now().microsecondsSinceEpoch + m.input.length) % 16;
        return (m[0] == 'x' ? r : (r & 0x3 | 0x8)).toRadixString(16);
      },
    );
  }

  Future<void> _load() async {
    debugPrint('[SeatSelection] _load started — eventId=${widget.eventId}');
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      debugPrint('[SeatSelection] Fetching event by id...');
      final event = await getEventById(widget.eventId);
      debugPrint('[SeatSelection] Event loaded: ${event.eventTitle}, venue=${event.venue != null}, pricingModel=${event.venue?.pricingModel}, ticketInfo.length=${event.ticketInfo.length}');
      debugPrint('[SeatSelection] Fetching seats...');
      final data = await getEventSeats(widget.eventId);
      debugPrint('[SeatSelection] Seats API response — placeIds.length=${data.placeIds.length}, sold=${data.sold.length}, reserved=${data.reserved.length}');
      final seats = decodeSeats(data);
      final withPrice = seats.where((s) => s.price != null && s.price! > 0).toList();
      final fromTier = seats.where((s) => s.basePrice != null).toList();
      debugPrint('[SeatSelection] decodeSeats: ${seats.length} seats, ${withPrice.length} with price, ${fromTier.length} from tier (base+tax)');
      if (data.pricingZones.isNotEmpty) debugPrint('[SeatSelection] pricingZones: ${data.pricingZones.length} zones');
      if (data.pricingConfig != null) debugPrint('[SeatSelection] pricingConfig: ${data.pricingConfig!.tiers.length} tiers, orderFee=${data.pricingConfig!.orderFee}');
      for (var i = 0; i < withPrice.length && i < 3; i++) {
        final s = withPrice[i];
        if (s.basePrice != null && s.taxAmount != null) {
          debugPrint('[SeatSelection] seat[$i] tier: base=${s.basePrice} tax=${s.taxAmount} total=${s.price}');
        } else {
          debugPrint('[SeatSelection] seat[$i] zone: total=${s.price}');
        }
      }
      setState(() {
        _event = event;
        _seatData = data;
        _seats = seats;
        _loading = false;
        final purchasableIds =
            data.areaSections.where((a) => a.isPurchasableForAreaFlow).map((a) => a.id).toSet();
        _areaSelectionMap.removeWhere((id, _) => !purchasableIds.contains(id));
      });
      debugPrint('[SeatSelection] _load success — _seats.length=${seats.length}, _loading=false');
    } catch (e, stack) {
      debugPrint('[SeatSelection] _load error: $e');
      debugPrint('[SeatSelection] stack: $stack');
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _continueFromSeats() {
    final areaSections = _purchasableAreaSections;
    final areaById = <String, AreaSectionModel>{
      for (final area in areaSections) area.id: area,
    };

    final normalizedAreaMap = <String, int>{};
    var runningAreaTotal = 0;
    for (final entry in _areaSelectionMap.entries) {
      final area = areaById[entry.key];
      if (area == null) continue;
      final qty = entry.value < 0 ? 0 : entry.value;
      final maxForArea = area.availableCount < 0 ? 0 : area.availableCount;
      final remainingSlots = 10 - _selectedPlaceIds.length - runningAreaTotal;
      final normalizedQty = qty > maxForArea
          ? maxForArea
          : (qty > remainingSlots ? remainingSlots : qty);
      if (normalizedQty > 0) {
        normalizedAreaMap[entry.key] = normalizedQty;
        runningAreaTotal += normalizedQty;
      }
    }

    final areaTotal = normalizedAreaMap.values.fold<int>(0, (sum, qty) => sum + qty);
    final totalQty = _selectedPlaceIds.length + areaTotal;
    if (totalQty <= 0) return;

    if (totalQty > 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 10 seats can be selected at a time')),
      );
      return;
    }

    setState(() {
      _areaSelectionMap
        ..clear()
        ..addAll(normalizedAreaMap);
      _step = SeatStep.info;
    });
  }

  /// Info step is valid when fullName, email and confirm email are filled and match.
  bool get _canSubmitInfo {
    final name = _fullName.trim();
    final email = _email.trim();
    if (name.isEmpty || email.isEmpty) return false;
    if (email != _confirmEmail.trim()) return false;
    if (!email.contains('@') || !email.contains('.')) return false;
    return true;
  }

  Future<void> _sendOtp() async {
    if (!_canSubmitInfo) return;
    setState(() => _error = null);
    try {
      await sendSeatOtp(
        widget.eventId,
        _email.trim(),
        fullName: _fullName.trim(),
        placeIds: _selectedPlaceIds,
        sectionSelections: _sectionSelections,
      );
      setState(() => _step = SeatStep.otp);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _verifyOtp() async {
    if (_otp.isEmpty) return;
    setState(() => _error = null);
    try {
      await verifySeatOtp(
        widget.eventId,
        _email.trim(),
        _otp,
        placeIds: _selectedPlaceIds,
        sectionSelections: _sectionSelections,
      );
      await reserveSeats(
        widget.eventId,
        _selectedPlaceIds,
        _sessionId,
        email: _email.trim(),
        sectionSelections: _sectionSelections,
      );
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      _reservationExpiresAtMs = nowMs + (_reservationDurationSeconds * 1000);
      _startReservationCountdown();
      await _refreshEventAndSeatsForPayment();
      if (!mounted) return;
      setState(() => _step = SeatStep.payment);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  /// After reserve, re-fetch event and seats so payment step shows final ticket/event info.
  Future<void> _refreshEventAndSeatsForPayment() async {
    try {
      final event = await getEventById(widget.eventId);
      final data = await getEventSeats(widget.eventId);
      final seats = decodeSeats(data);
      if (!mounted) return;
      setState(() {
        _event = event;
        _seatData = data;
        _seats = seats;
      });
    } catch (_) {
      // Keep existing _event/_seats on refetch failure; don't block payment step
    }
  }

  void _goToPayment() {
    final event = _event;
    if (event == null) return;
    final merchantId = event.merchant?.id ?? event.merchantId;
    final externalMerchantId = event.externalMerchantId ?? event.merchant?.merchantId ?? '';
    if (merchantId == null || merchantId.isEmpty) return;
    final selectedSeats = _seats.where((s) => _selectedPlaceIds.contains(s.placeId)).toList();
    final qty = _selectedTotalQty;
    if (qty == 0) return;
    if (_isReservationExpired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reservation expired. Please select seats again.')),
      );
      _resetExpiredReservationState();
      return;
    }
    final currency = currencyFromCountry(event.country);

    double basePrice = 0;
    double serviceFee = 0;
    double serviceTax = 0;
    double orderFee = 0;
    double vat = 0;
    String ticketId;
    String ticketName;
    double? totalAmountOverride;
    List<Map<String, dynamic>>? seatTickets;

    if (_useTicketInfoPricing && event.ticketInfo.isNotEmpty) {
      // Use the same total we display ("Total (N seats)") — no recalculation.
      final firstSeatTicket_ = selectedSeats.isNotEmpty
          ? _ticketForSeat(selectedSeats.first)
          : _effectiveAreaTicket;
      if (firstSeatTicket_ == null) return;
      final ft = firstSeatTicket_;
      ticketId = ft.id;
      ticketName = ft.name;
      basePrice = ft.price;
      serviceFee = (ft.serviceFee ?? 0).toDouble();
      serviceTax = (ft.serviceTax ?? 0).toDouble();
      orderFee = (ft.orderFee ?? 0).toDouble();
      vat = (ft.entertainmentTax ?? ft.vat ?? 0).toDouble();
      final seatsTotalTruncated = _round3(_selectedSeatsTotal);
      final orderFeeTax = _round3(orderFee * (serviceTax / 100));
      final orderFeeTotalTruncated = _round3(orderFee + orderFeeTax);
      totalAmountOverride = _round3(seatsTotalTruncated + orderFeeTotalTruncated);
      seatTickets = selectedSeats.map((s) {
        final t = _ticketForSeat(s);
        return <String, dynamic>{
          'placeId': s.placeId,
          'ticketId': t?.id ?? '',
          'ticketName': t?.name ?? '',
          'price': t?.price ?? 0,
          'totalPerTicket': t?.totalPerTicket ?? 0,
        };
      }).toList();
      if (_areaSelectionMap.isNotEmpty) {
        final areaById = <String, AreaSectionModel>{
          for (final area in _purchasableAreaSections) area.id: area,
        };
        for (final entry in _areaSelectionMap.entries) {
          final qty = entry.value;
          if (qty <= 0) continue;
          final areaName = areaById[entry.key]?.name ?? _tx('areaPass');
          for (var i = 0; i < qty; i++) {
            seatTickets.add(<String, dynamic>{
              'placeId': '',
              'ticketId': ft.id,
              'ticketName': areaName,
              'price': ft.price,
              'totalPerTicket': ft.totalPerTicket,
            });
          }
        }
      }
      if (selectedSeats.isEmpty && _areaSelectionMap.isNotEmpty) {
        final areaById = <String, AreaSectionModel>{
          for (final area in _purchasableAreaSections) area.id: area,
        };
        final selectedAreaEntries = _areaSelectionMap.entries.where((e) => e.value > 0).toList();
        if (selectedAreaEntries.length == 1) {
          final areaName = areaById[selectedAreaEntries.first.key]?.name;
          if (areaName != null && areaName.trim().isNotEmpty) {
            final qtyLabel = selectedAreaEntries.first.value > 1 ? ' x${selectedAreaEntries.first.value}' : '';
            ticketName = '$areaName$qtyLabel';
          }
        } else if (selectedAreaEntries.length > 1) {
          ticketName = _tx('areaPass');
        }
      }
      debugPrint('[Payment calc] source=ticket_info | seatsTotal=$seatsTotalTruncated orderFeeTotal=$orderFeeTotalTruncated → totalAmountOverride=$totalAmountOverride (web formula, entertainmentTax)');
    } else {
      // pricing_configuration: build seatTickets with tier pricing when seats are selected.
      final firstTicket = event.ticketInfo.isNotEmpty ? event.ticketInfo.first : null;
      ticketId = firstTicket?.id ?? '';
      final selectedAreaEntries = _areaSelectionMap.entries.where((e) => e.value > 0).toList();
      final areaQty = selectedAreaEntries.fold<int>(0, (sum, e) => sum + e.value);

      ticketName = 'Ticket';
      if (selectedSeats.isNotEmpty && areaQty == 0) {
        ticketName = 'Seat';
      } else if (selectedSeats.isNotEmpty && areaQty > 0) {
        ticketName = 'Ticket';
      } else if (areaQty > 0) {
        if (selectedAreaEntries.length == 1) {
          final areaId = selectedAreaEntries.first.key;
          AreaSectionModel? area;
          for (final a in _purchasableAreaSections) {
            if (a.id == areaId) {
              area = a;
              break;
            }
          }
          if (area != null) {
            ticketName = area.name;
          } else {
            ticketName = _tx('areaPass');
          }
        } else {
          ticketName = _tx('areaPass');
        }
      }
      orderFee = _seatData?.pricingConfig?.orderFee ?? 0;

      double totalBase = 0;
      double totalSvcFee = 0;
      double tierTax = 0;
      double tierSvcTax = 0;
      bool tierRatesSet = false;
      seatTickets = <Map<String, dynamic>>[];

      void setTierRatesIfNeeded(PricingTier? tier) {
        if (tierRatesSet) return;
        if (tier == null) return;
        tierTax = tier.tax;
        tierSvcTax = tier.serviceTax;
        tierRatesSet = true;
      }

      for (final s in selectedSeats) {
        final tier = _tierForSeat(s);
        final tb = tier?.basePrice ?? s.basePrice ?? 0;
        final tf = tier?.serviceFee ?? 0.0;
        totalBase += tb;
        totalSvcFee += tf;
        setTierRatesIfNeeded(tier);
        seatTickets.add(<String, dynamic>{
          'placeId': s.placeId,
          'ticketId': null,
          'ticketName': _seatTicketNameForSeat(s),
          'pricing': {
            'basePrice': tb,
            'serviceFee': tf,
            'tax': tier?.tax ?? 0,
            'serviceTax': tier?.serviceTax ?? 0,
            'orderFee': orderFee,
            'currency': currency.toUpperCase(),
          },
        });
      }

      if (areaQty > 0) {
        final areaSections = _purchasableAreaSections;
        for (final entry in selectedAreaEntries) {
          final q = entry.value;
          if (q <= 0) continue;
          final areaId = entry.key;

          AreaSectionModel? area;
          for (final a in areaSections) {
            if (a.id == areaId) {
              area = a;
              break;
            }
          }
          if (area == null) continue;

          final repSeat = _representativeSeatForArea(area);
          if (repSeat == null) continue;

          final tier = _tierForSeat(repSeat);
          final tb = tier?.basePrice ?? repSeat.basePrice ?? 0;
          final tf = tier?.serviceFee ?? 0.0;

          totalBase += tb * q;
          totalSvcFee += tf * q;
          setTierRatesIfNeeded(tier);

          final areaLabel = area.name;

          for (var i = 0; i < q; i++) {
            seatTickets.add(<String, dynamic>{
              'placeId': '',
              'ticketId': null,
              'ticketName': areaLabel,
              'pricing': {
                'basePrice': tb,
                'serviceFee': tf,
                'tax': tier?.tax ?? 0,
                'serviceTax': tier?.serviceTax ?? 0,
                'orderFee': orderFee,
                'currency': currency.toUpperCase(),
              },
            });
          }
        }
      }

      basePrice = qty > 0 ? (totalBase / qty) : 0;
      serviceFee = qty > 0 ? (totalSvcFee / qty) : 0;
      vat = tierTax;
      serviceTax = tierSvcTax;

      // Match backend formula: round3 each component, then sum
      final taxAmt = _round3(totalBase * tierTax / 100);
      final svcTaxAmt = _round3(totalSvcFee * tierSvcTax / 100);
      final seatsTotal = _round3(_round3(totalBase) + taxAmt + _round3(totalSvcFee) + svcTaxAmt);
      final orderFeeTax = _round3(orderFee * tierSvcTax / 100);
      final orderFeeTotal = _round3(orderFee + orderFeeTax);
      totalAmountOverride = _round3(seatsTotal + orderFeeTotal);

      debugPrint('[Payment calc] source=pricing_configuration | totalBase=$totalBase taxAmt=$taxAmt totalSvcFee=$totalSvcFee svcTaxAmt=$svcTaxAmt seatsTotal=$seatsTotal orderFee=$orderFee orderFeeTotal=$orderFeeTotal → totalAmountOverride=$totalAmountOverride');
    }

    final payload = CheckoutPayload(
      eventId: event.id,
      eventName: event.eventTitle,
      merchantId: merchantId,
      externalMerchantId: externalMerchantId,
      email: _email.trim(),
      fullName: _fullName.trim().isEmpty ? null : _fullName.trim(),
      country: event.country,
      ticketId: ticketId,
      ticketName: ticketName,
      price: basePrice,
      serviceFee: serviceFee,
      serviceTax: serviceTax,
      orderFee: orderFee,
      vat: vat,
      quantity: qty,
      currency: currency,
      paytrailEnabled: event.merchant?.paytrailEnabled ?? false,
      placeIds: _selectedPlaceIds,
      sectionSelections: _sectionSelections,
      seatTickets: seatTickets,
      sessionId: _sessionId,
      reservationExpiresAtMs: _reservationExpiresAtMs,
      totalAmountOverride: totalAmountOverride,
    );
    final cents = payload.totalCents;
    debugPrint('[Payment calc] CheckoutPayload.totalCents=$cents (${cents / 100} €)');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PaymentScreen(payload: payload),
      ),
    );
  }

  bool get _isReservationExpired {
    final expiresAt = _reservationExpiresAtMs;
    if (expiresAt == null) return false;
    return DateTime.now().millisecondsSinceEpoch >= expiresAt;
  }

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds < 0 ? 0 : d.inSeconds;
    final mins = totalSeconds ~/ 60;
    final secs = totalSeconds % 60;
    final mm = mins.toString().padLeft(2, '0');
    final ss = secs.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  void _startReservationCountdown() {
    _reservationTimer?.cancel();
    _updateReservationRemaining();
    _reservationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _updateReservationRemaining();
      if (_isReservationExpired) {
        _reservationTimer?.cancel();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reservation expired. Please select seats again.')),
        );
        _resetExpiredReservationState();
      }
    });
  }

  void _updateReservationRemaining() {
    final expiresAt = _reservationExpiresAtMs;
    if (expiresAt == null) {
      _reservationRemaining = Duration.zero;
      return;
    }
    final remainingMs = expiresAt - DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _reservationRemaining = Duration(milliseconds: remainingMs > 0 ? remainingMs : 0);
    });
  }

  void _resetExpiredReservationState() {
    setState(() {
      _step = SeatStep.seats;
      _reservationExpiresAtMs = null;
      _reservationRemaining = Duration.zero;
      _selectedPlaceIds.clear();
      _areaSelectionMap.clear();
      _seatTicketMap.clear();
      _areaTicketId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      debugPrint('[SeatSelection] build — showing LOADING (spinner)');
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(title: const Text('Choose seats')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _seatData == null) {
      debugPrint('[SeatSelection] build — showing ERROR state, _error=$_error');
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(title: const Text('Choose seats')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    debugPrint('[SeatSelection] build — showing MAIN (steps) _step=$_step, _seats.length=${_seats.length}, _seatData=${_seatData != null}');
    final steps = ['Seats', 'Info', 'Verify', 'Payment'];
    final stepIndex = SeatStep.values.indexOf(_step);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(_event?.eventTitle ?? 'Choose seats'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(value: (stepIndex + 1) / 4),
          if (_step != SeatStep.seats)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(4, (i) => Text(steps[i], style: TextStyle(fontWeight: i <= stepIndex ? FontWeight.bold : FontWeight.normal))),
              ),
            ),
          Expanded(
            child: _step == SeatStep.seats
                ? _buildSeatsStep()
                : _step == SeatStep.info
                    ? _buildInfoStep()
                    : _step == SeatStep.otp
                        ? _buildOtpStep()
                        : _buildPaymentStep(),
          ),
        ],
      ),
    );
  }

  /// When pricingModel is "ticket_info", pricing comes from event.ticketInfo only (ignore seat/zone prices).
  /// Some APIs return pricingModel at event level; others nest it under venue.
  bool get _useTicketInfoPricing {
    final model = _event?.venue?.pricingModel ?? (_event as dynamic).pricingModel;
    return model == 'ticket_info';
  }

  /// Ticket for a seat when pricingModel is ticket_info (from _seatTicketMap or first ticket).
  TicketInfo? _ticketForSeat(SeatModel seat) {
    if (_event?.ticketInfo.isEmpty ?? true) return null;
    final ticketId = _seatTicketMap[seat.placeId];
    if (ticketId != null) {
      for (final t in _event!.ticketInfo) {
        if (t.id == ticketId) return t;
      }
    }
    return _event!.ticketInfo.first;
  }

  TicketInfo? _ticketById(String? ticketId) {
    if (ticketId == null || ticketId.isEmpty || _event?.ticketInfo.isEmpty == true) return null;
    for (final t in _event!.ticketInfo) {
      if (t.id == ticketId) return t;
    }
    return null;
  }

  TicketInfo? get _effectiveAreaTicket {
    return _ticketById(_areaTicketId);
  }

  /// Per-seat price (no order fee). Uses TicketInfo.totalPerTicket so display and payment match the same source (tax on base only, then + service fee).
  double _ticketInfoSeatPrice(TicketInfo t) => _round3(t.totalPerTicket);

  /// Unit price for an area/standing ticket section.
  ///
  /// pricing_configuration: uses decoded seat tier pricing from any place belonging to this area section.
  /// ticket_info: uses the first ticket_info entry (backend currently allocates without per-section ticket picking on the UI side).
  double? _areaUnitPrice(AreaSectionModel area) {
    final event = _event;
    if (event == null) return null;

    if (_useTicketInfoPricing) {
      final areaTicket = _effectiveAreaTicket;
      if (areaTicket == null) return null;
      return _ticketInfoSeatPrice(areaTicket);
    }

    // pricing_configuration: find a representative decoded place for this section name.
    final target = area.name.trim().toLowerCase();
    for (final s in _seats) {
      final sec = (s.section ?? '').trim().toLowerCase();
      if (sec.isEmpty) continue;
      if (sec == target && s.price != null && s.price! > 0) return s.price;
    }
    return null;
  }

  TicketInfo? _ticketInfoForArea(AreaSectionModel area) {
    if (!_useTicketInfoPricing) return null;
    return _effectiveAreaTicket;
  }

  SeatModel? _representativeSeatForArea(AreaSectionModel area) {
    if (_useTicketInfoPricing) return null;
    final target = area.name.trim().toLowerCase();
    for (final s in _seats) {
      final sec = (s.section ?? '').trim().toLowerCase();
      if (sec.isEmpty) continue;
      if (sec == target && s.price != null && s.price! > 0) return s;
    }
    return null;
  }

  /// Per-seat label for pricing_configuration seatTickets (match web metadata style).
  /// Example: "Section: PERMANTO, Row: 19, Seat: 36"
  String _seatTicketNameForSeat(SeatModel seat) {
    final decoded = decodePlaceId(seat.placeId);
    if (decoded == null) return 'Seat';
    final section = decoded.section.trim().isEmpty ? '?' : decoded.section.trim();
    return 'Section: $section, Row: ${decoded.row}, Seat: ${decoded.seat}';
  }

  /// Price for a seat. Do not mix: ticket_info → only from ticket (web formula); pricing_configuration → only from decoded seat.
  double? _effectiveSeatPrice(SeatModel seat) {
    if (_useTicketInfoPricing) {
      final t = _ticketForSeat(seat);
      return t != null ? _ticketInfoSeatPrice(t) : null;
    }
    return seat.price != null && seat.price! > 0 ? seat.price : null;
  }

  Widget _priceRow(BuildContext context, String label, double amount, String currency, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: bold ? FontWeight.w600 : null)),
          Text(formatPrice(amount, currency), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: bold ? FontWeight.w600 : null)),
        ],
      ),
    );
  }

  /// Same as _priceRow but with 3 decimals (parity with web formatCurrency).
  Widget _priceRow3(BuildContext context, String label, double amount, String currency, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: bold ? FontWeight.w600 : null)),
          Text(formatPriceWithDecimals(amount, currency, 3), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: bold ? FontWeight.w600 : null)),
        ],
      ),
    );
  }

  /// Ticket_info breakdown matching web: Base Price, Tax, Service Fee (if >0), Service Tax (if >0), Total (3 decimals).
  List<Widget> _ticketInfoBreakdownLines(TicketInfo ticket, String currency) {
    final taxPct = ticket.entertainmentTax ?? (ticket.vat ?? 0);
    final taxAmount = _round3(ticket.price * (taxPct / 100));
    final sf = (ticket.serviceFee ?? 0).toDouble();
    final stPct = (ticket.serviceTax ?? 0) / 100;
    final serviceTaxAmount = _round3(sf * stPct);
    final totalDisplay = _round3(ticket.price + taxAmount + sf + serviceTaxAmount);
    final lines = <Widget>[
      _priceRow3(context, 'Base Price:', ticket.price, currency),
      if (taxPct > 0) _priceRow3(context, 'Tax:', taxAmount, currency),
      if (sf > 0) _priceRow3(context, 'Service Fee:', sf, currency),
      if (sf > 0 && stPct > 0) _priceRow3(context, 'Service Tax:', serviceTaxAmount, currency),
    ];
    lines.add(const Divider(height: 12));
    lines.add(_priceRow3(context, 'Total:', totalDisplay, currency, bold: true));
    return lines;
  }

  /// Bottom sheet with pricing info for a selected area/standing section.
  void _showAreaPricingDetails(AreaSectionModel area, String currency) {
    final ticket = _ticketInfoForArea(area);
    final repSeat = _representativeSeatForArea(area);
    final unitPrice = _areaUnitPrice(area);
    final availableTicketModels = (_event?.ticketInfo ?? const <TicketInfo>[])
        .where((t) => t.available == null || t.available! > 0)
        .toList();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          area.name,
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                const SizedBox(height: 8),
                if (_useTicketInfoPricing) ...[
                  if (availableTicketModels.isEmpty)
                    Text(
                      'No ticket models available',
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    )
                  else ...[
                    Text(
                      'Available ticket models',
                      style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    ...availableTicketModels.map((model) {
                      final isSelected = ticket != null && model.id == ticket.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    model.name,
                                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                if (isSelected)
                                  Text(
                                    'Selected',
                                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(ctx).colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ..._ticketInfoBreakdownLines(model, currency),
                          ],
                        ),
                      );
                    }),
                  ],
                ] else if (repSeat != null) ...[
                  Text(
                    'Total (per unit)',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  if (unitPrice != null)
                    _priceRow(ctx, 'Total', unitPrice, currency, bold: true),
                  const Divider(height: 12),
                  if (repSeat.basePrice != null) _priceRow3(ctx, 'Base Price:', repSeat.basePrice!, currency),
                  if (repSeat.taxAmount != null) _priceRow3(ctx, 'Tax:', repSeat.taxAmount!, currency),
                  if (repSeat.serviceFeeAmount != null) _priceRow3(ctx, 'Service Fee:', repSeat.serviceFeeAmount!, currency),
                  if (repSeat.serviceFeePercentage != null) _priceRow3(ctx, 'Service Tax:', repSeat.serviceFeePercentage!, currency),
                  if (repSeat.orderFeeAmount != null) _priceRow3(ctx, 'Order Fee:', repSeat.orderFeeAmount!, currency),
                  if (repSeat.price != null) _priceRow3(ctx, 'Total:', repSeat.price!, currency, bold: true),
                ] else ...[
                  Text(
                    unitPrice != null ? 'Price: ${formatPrice(unitPrice, currency)}' : 'Pricing not available',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAreaTicketTypeSelector(
    AreaSectionModel area,
    String currency,
    VoidCallback onSelected,
  ) {
    final event = _event;
    if (event == null || event.ticketInfo.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Select Ticket Type',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('Area: ${area.name}', style: Theme.of(ctx).textTheme.bodyMedium),
                const SizedBox(height: 16),
                ...event.ticketInfo.where((t) => t.available == null || t.available! > 0).map((ticket) {
                  final taxPct = ticket.entertainmentTax ?? ticket.vat ?? 0;
                  final taxAmount = _round3(ticket.price * (taxPct / 100));
                  final totalDisplay = _round3(ticket.price + taxAmount);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          setState(() => _areaTicketId = ticket.id);
                          onSelected();
                          Navigator.of(ctx).pop();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(ticket.name, style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                                  Text(
                                    formatPriceWithDecimals(totalDisplay, currency, 3),
                                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _priceRow3(ctx, 'Base Price:', ticket.price, currency),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Tax (${taxPct.toStringAsFixed(1)}%):', style: Theme.of(ctx).textTheme.bodySmall),
                                    Text('+${formatPriceWithDecimals(taxAmount, currency, 3)}', style: Theme.of(ctx).textTheme.bodySmall),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Show modal to pick ticket type for a seat (parity with web "Select Ticket Type").
  void _showTicketTypeSelector(SeatModel seat) {
    final event = _event;
    if (event == null || event.ticketInfo.isEmpty) return;
    final currency = currencyFromCountry(event.country);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Select Ticket Type',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (seat.section != null && seat.section!.isNotEmpty)
                  Text('Section: ${seat.section!.toUpperCase()}', style: Theme.of(ctx).textTheme.bodyMedium),
                if (seat.row != null && seat.row!.isNotEmpty)
                  Text('Row: ${seat.row}', style: Theme.of(ctx).textTheme.bodyMedium),
                if (seat.seat != null && seat.seat!.isNotEmpty)
                  Text('Seat: ${seat.seat}', style: Theme.of(ctx).textTheme.bodyMedium),
                const SizedBox(height: 16),
                ...event.ticketInfo.map((ticket) {
                  final taxPct = ticket.entertainmentTax ?? ticket.vat ?? 0;
                  final taxAmount = (ticket.price * (taxPct / 100) * 1000).round() / 1000.0;
                  final totalDisplay = ((ticket.price + taxAmount) * 1000).round() / 1000.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          setState(() {
                            _selectedPlaceIds.add(seat.placeId);
                            _seatTicketMap[seat.placeId] = ticket.id;
                          });
                          Navigator.of(ctx).pop();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(ticket.name, style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                                  Text(
                                    formatPriceWithDecimals(totalDisplay, currency, 3),
                                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _priceRow3(ctx, 'Base Price:', ticket.price, currency),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Tax (${taxPct.toStringAsFixed(1)}%):', style: Theme.of(ctx).textTheme.bodySmall),
                                    Text('+${formatPriceWithDecimals(taxAmount, currency, 3)}', style: Theme.of(ctx).textTheme.bodySmall),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

Widget _buildSeatsStep() {
  final withPosition =
      _canvasSeats.where((s) => s.x != null && s.y != null).toList();
  final useCanvas = withPosition.isNotEmpty;
  final currency = currencyFromCountry(_event?.country);

  double rowSpacingMultiplier = 1.0;
  double seatSpacingMultiplier = 1.0;
  double? seatRadiusOverride;
  final bg = _seatData?.backgroundSvg;
  if (bg is Map<String, dynamic>) {
    final displayConfig = bg['displayConfig'];
    if (displayConfig is Map<String, dynamic>) {
      final rowGap = (displayConfig['rowGap'] as num?)?.toDouble();
      final seatGap = (displayConfig['seatGap'] as num?)?.toDouble();
      final dotSize = (displayConfig['dotSize'] as num?)?.toDouble();
      if (rowGap != null && rowGap > 0) rowSpacingMultiplier = rowGap / 10.0;
      if (seatGap != null && seatGap > 0) seatSpacingMultiplier = seatGap / 10.0;
      if (dotSize != null && dotSize > 0) seatRadiusOverride = dotSize;
    }
  }

  final selectedSeats =
      _seats.where((s) => _selectedPlaceIds.contains(s.placeId)).toList();

  final totalPrice = _selectedSeatsTotal;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [

      // ============================================================
      // SEAT MAP — gets maximum vertical space
      // ============================================================
      if (useCanvas)
        Expanded(
          child: ClipRect(
            child: SeatMapCanvas(
              seats: _canvasSeats,
              sections: _seatData?.sections ?? const [],
              selectedPlaceIds: _selectedPlaceIds,
              rowSpacingMultiplier: rowSpacingMultiplier,
              seatSpacingMultiplier: seatSpacingMultiplier,
              seatRadiusOverride: seatRadiusOverride,
              onSeatTap: (seat) {
                if (seat.status != SeatStatus.available) return;

                if (_selectedPlaceIds.contains(seat.placeId)) {
                  setState(() {
                    _selectedPlaceIds.remove(seat.placeId);
                    _seatTicketMap.remove(seat.placeId);
                  });
                  return;
                }

                if (_selectedPlaceIds.length >= 10) return;

                if (_useTicketInfoPricing &&
                    _event?.ticketInfo.isNotEmpty == true) {
                  if (_event!.ticketInfo.length == 1) {
                    setState(() {
                      _selectedPlaceIds.add(seat.placeId);
                      _seatTicketMap[seat.placeId] =
                          _event!.ticketInfo.first.id;
                    });
                  } else {
                    _showTicketTypeSelector(seat);
                  }
                } else {
                  setState(() =>
                      _selectedPlaceIds.add(seat.placeId));
                }
              },
              maxSeatsToSelect: 10,
            ),
          ),
        )
      else
        const Expanded(child: SizedBox()),

      // ============================================================
      // COMPACT BOTTOM BAR — selection summary + continue
      // ============================================================
      Material(
        elevation: 8,
        surfaceTintColor: Colors.transparent,
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          top: false,
          bottom: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedTotalQty == 0
                                ? _tx('selectSeatsAreasMax')
                                : '$_selectedTotalQty ${_selectedTotalQty > 1 ? _tx("tickets") : _tx("ticket")} ${_tx("selected")}',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (_selectedTotalQty > 0)
                            Text(
                              formatPrice(totalPrice, currency),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_selectedTotalQty > 0) ...[
                      TextButton.icon(
                        onPressed: () => _showSelectionDetails(selectedSeats, currency, totalPrice),
                        icon: const Icon(Icons.receipt_long, size: 18),
                        label: Text(_tx('details')),
                      ),
                      const SizedBox(width: 8),
                    ],
                    ElevatedButton(
                      onPressed: _selectedTotalQty == 0 ? null : _continueFromSeats,
                      child: Text(_tx('continue')),
                    ),
                  ],
                ),
                if (_purchasableAreaSections.isNotEmpty && _selectedPlaceIds.isEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _tx('standingAreaSections'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ..._purchasableAreaSections.map((area) {
                    final currentQty = _areaSelectionMap[area.id] ?? 0;
                    final totalSelectedQty = _selectedTotalQty;
                    final unitPrice = _areaUnitPrice(area);
                    final areaTicket = _ticketInfoForArea(area);
                    // Web parity: in `ticket_info` pricing model, standing/area selection is capped by scanCount.
                    final ticketForAreas = _effectiveAreaTicket ??
                        (_event?.ticketInfo.isNotEmpty == true ? _event!.ticketInfo.first : null);
                    final scanCount = ticketForAreas?.scanCount ?? 0;
                    final isScanCountPass = _useTicketInfoPricing && scanCount > 0;
                    final maxQty = isScanCountPass ? 1 : area.availableCount;

                    final isSoldOut = maxQty <= 0;
                    // Match web label: when not sold-out, still display backend `availableCount`.
                    final availabilityText = isSoldOut ? _tx('soldOut') : '${_tx("available")}: ${area.availableCount}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _showAreaPricingDetails(area, currency),
                              child: Text(
                                '${area.name} · $availabilityText${_useTicketInfoPricing && areaTicket != null ? ' · ${areaTicket.name}' : ''}${unitPrice != null ? ' · ${_tx("price")}: ${formatPrice(unitPrice, currency)}' : ''}',
                                style: Theme.of(context).textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: currentQty <= 0
                                ? null
                                : () => setState(() {
                                      _areaSelectionMap[area.id] = currentQty - 1;
                                    }),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text('$currentQty'),
                          IconButton(
                            onPressed: currentQty >= maxQty || totalSelectedQty >= 10
                                ? null
                                : () {
                                    final increment = () => setState(() {
                                          final remainingSlots = 10 - (_selectedPlaceIds.length + _areaSelectionMap.values.fold<int>(0, (sum, qty) => sum + qty));
                                          if (remainingSlots <= 0) return;
                                          final nextQty = currentQty + 1;
                                          _areaSelectionMap[area.id] = nextQty > maxQty ? maxQty : nextQty;
                                        });
                                    if (_useTicketInfoPricing && (_event?.ticketInfo.isNotEmpty ?? false)) {
                                      _showAreaTicketTypeSelector(area, currency, increment);
                                    } else {
                                      increment();
                                    }
                                  },
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

  void _showSelectionDetails(List<SeatModel> selectedSeats, String currency, double totalPrice) {
    final areaById = <String, AreaSectionModel>{
      for (final area in _purchasableAreaSections) area.id: area,
    };
    final selectedAreaEntries = _areaSelectionMap.entries.where((e) => e.value > 0).toList();
    final totalQty = _selectedTotalQty;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (ctx, scrollCtrl) {
            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Your Selection', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop()),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      ...selectedSeats.map((s) {
                        final price = _effectiveSeatPrice(s);
                        // Full breakdown fields on SeatModel are for pricing_configuration.
                        // For ticket_info, ignore decoded seat tier/zone pricing completely.
                        final hasFullBreakdown = !_useTicketInfoPricing &&
                            (s.basePrice != null ||
                                s.taxAmount != null ||
                                s.serviceFeeAmount != null ||
                                s.serviceFeePercentage != null ||
                                s.orderFeeAmount != null);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (s.section != null) Text('SECTION: ${s.section!.toUpperCase()}', style: Theme.of(ctx).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                              if (s.row != null) Text('ROW: ${s.row}', style: Theme.of(ctx).textTheme.bodySmall),
                              if (s.seat != null) Text('SEAT: ${s.seat}', style: Theme.of(ctx).textTheme.bodySmall),
                              const SizedBox(height: 4),
                              if (hasFullBreakdown) ...[
                                if (s.basePrice != null) _priceRow3(ctx, 'Base Price:', s.basePrice!, currency),
                                if (s.taxAmount != null) _priceRow3(ctx, 'Tax:', s.taxAmount!, currency),
                                if (s.serviceFeeAmount != null) _priceRow3(ctx, 'Service Fee:', s.serviceFeeAmount!, currency),
                                if (s.serviceFeePercentage != null) _priceRow3(ctx, 'Service Tax:', s.serviceFeePercentage!, currency),
                                if (s.orderFeeAmount != null) _priceRow3(ctx, 'Order Fee:', s.orderFeeAmount!, currency),
                                const Divider(height: 12),
                                if (s.price != null) _priceRow3(ctx, 'Total:', s.price!, currency, bold: true),
                              ] else if (_useTicketInfoPricing && _ticketForSeat(s) != null) ...[
                                ..._ticketInfoBreakdownLines(_ticketForSeat(s)!, currency),
                              ] else if (price != null) ...[
                                _priceRow(ctx, 'Total', price, currency, bold: true),
                              ],
                              const Divider(height: 8),
                            ],
                          ),
                        );
                      }),
                      ...selectedAreaEntries.map((entry) {
                        final area = areaById[entry.key];
                        final areaName = area?.name ?? _tx('areaPass');
                        final qty = entry.value;
                        final unitPrice = area == null ? null : _areaUnitPrice(area);
                        final areaTotal = unitPrice != null ? unitPrice * qty : null;
                        final ticketInfo = area == null ? null : _ticketInfoForArea(area);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('AREA: $areaName', style: Theme.of(ctx).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                              Text('QTY: $qty', style: Theme.of(ctx).textTheme.bodySmall),
                              const SizedBox(height: 4),
                              if (ticketInfo != null) ...[
                                ..._ticketInfoBreakdownLines(ticketInfo, currency),
                                if (qty > 1) _priceRow3(ctx, 'Line Total:', _round3(ticketInfo.totalPerTicket * qty), currency, bold: true),
                              ] else if (areaTotal != null) ...[
                                _priceRow3(ctx, 'Line Total:', areaTotal, currency, bold: true),
                              ],
                              const Divider(height: 8),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total ($totalQty ${totalQty == 1 ? _tx("ticket") : _tx("tickets")})', style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          Text(formatPrice(totalPrice, currency), style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
  Widget _buildInfoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            initialValue: _fullName,
            decoration: const InputDecoration(
              labelText: 'Full name',
              hintText: 'Enter your full name',
            ),
            textCapitalization: TextCapitalization.words,
            autocorrect: false,
            onChanged: (v) => setState(() => _fullName = v),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: _email,
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'your@email.com',
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            onChanged: (v) => setState(() => _email = v),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: _confirmEmail,
            decoration: const InputDecoration(
              labelText: 'Confirm email',
              hintText: 'Repeat your email',
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            onChanged: (v) => setState(() => _confirmEmail = v),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _canSubmitInfo ? _sendOtp : null,
            child: const Text('Send verification code'),
          ),
          TextButton(onPressed: () => setState(() => _step = SeatStep.seats), child: const Text('Back')),
        ],
      ),
    );
  }

  Widget _buildOtpStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Code sent to $_email'),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('otp_code_input'),
            initialValue: _otp,
            decoration: const InputDecoration(labelText: 'Code', hintText: 'Enter verification code'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (v) => setState(() => _otp = v),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _otp.isEmpty ? null : _verifyOtp,
            child: const Text('Verify'),
          ),
          TextButton(onPressed: () => setState(() => _step = SeatStep.info), child: const Text('Back')),
        ],
      ),
    );
  }

  Widget _buildPaymentStep() {
    final event = _event;
    final currency = currencyFromCountry(event?.country);
    final selectedSeats = _seats.where((s) => _selectedPlaceIds.contains(s.placeId)).toList();
    final areaById = <String, AreaSectionModel>{
      for (final area in (_seatData?.areaSections ?? const <AreaSectionModel>[]))
        area.id: area,
    };
    final selectedAreaEntries = _areaSelectionMap.entries.where((e) => e.value > 0).toList();
    final totalPrice = _selectedSeatsTotal;
    final totalQty = _selectedTotalQty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Seats reserved. Review and proceed to payment.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_reservationExpiresAtMs != null) ...[
            const SizedBox(height: 8),
            Text(
              'Reservation expires in ${_formatDuration(_reservationRemaining)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _reservationRemaining.inSeconds <= 60
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (event != null) ...[
            const SizedBox(height: 16),
            Text(
              event.eventTitle,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order Summary', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ...selectedSeats.map((s) {
                  final price = _effectiveSeatPrice(s);
                  // Full breakdown fields on SeatModel are for pricing_configuration.
                  // For ticket_info, ignore decoded seat tier/zone pricing completely.
                  final hasFullBreakdown = !_useTicketInfoPricing &&
                      (s.basePrice != null || s.taxAmount != null || s.serviceFeeAmount != null);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (s.section != null) Text('SECTION: ${s.section!.toUpperCase()}', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                        if (s.row != null) Text('ROW: ${s.row}', style: Theme.of(context).textTheme.bodySmall),
                        if (s.seat != null) Text('SEAT: ${s.seat}', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),
                        if (hasFullBreakdown) ...[
                          if (s.basePrice != null) _priceRow3(context, 'Base Price:', s.basePrice!, currency),
                          if (s.taxAmount != null) _priceRow3(context, 'Tax:', s.taxAmount!, currency),
                          if (s.serviceFeeAmount != null) _priceRow3(context, 'Service Fee:', s.serviceFeeAmount!, currency),
                          if (s.price != null) _priceRow3(context, 'Seat Total:', s.price!, currency, bold: true),
                        ] else if (_useTicketInfoPricing && _ticketForSeat(s) != null) ...[
                          ..._ticketInfoBreakdownLines(_ticketForSeat(s)!, currency),
                        ] else if (price != null) ...[
                          _priceRow(context, 'Seat Total', price, currency, bold: true),
                        ],
                        const Divider(height: 8),
                      ],
                    ),
                  );
                }),
                ...selectedAreaEntries.map((entry) {
                  final area = areaById[entry.key];
                  final areaName = area?.name ?? _tx('areaPass');
                  final qty = entry.value;
                  final ticketInfo = area == null ? null : _ticketInfoForArea(area);
                  final unitPrice = area == null ? null : _areaUnitPrice(area);
                  final lineTotal = ticketInfo != null
                      ? _round3(ticketInfo.totalPerTicket * qty)
                      : (unitPrice != null ? _round3(unitPrice * qty) : null);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AREA: $areaName', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                        Text('QTY: $qty', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),
                        if (ticketInfo != null) ...[
                          ..._ticketInfoBreakdownLines(ticketInfo, currency),
                          if (qty > 1) _priceRow3(context, 'Line Total:', _round3(ticketInfo.totalPerTicket * qty), currency, bold: true),
                        ] else if (lineTotal != null) ...[
                          _priceRow3(context, 'Line Total:', lineTotal, currency, bold: true),
                        ],
                        const Divider(height: 8),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total ($totalQty ${totalQty == 1 ? _tx("ticket") : _tx("tickets")})', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    Text(formatPrice(totalPrice, currency), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isReservationExpired ? null : _goToPayment,
              child: const Text('Pay now'),
            ),
          ),
          TextButton(onPressed: () => setState(() => _step = SeatStep.otp), child: const Text('Back')),
        ],
      ),
    );
  }
}