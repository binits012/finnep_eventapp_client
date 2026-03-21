import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/checkout_payload.dart';
import '../models/event.dart';
import '../services/event_service.dart';
import '../services/seat_service.dart';
import '../services/free_event_service.dart';
import '../services/waitlist_service.dart';
import '../theme_scope.dart';
import '../utils/currency.dart';
import '../services/api_client.dart' show ApiException;

Future<void> _openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  Event? _event;
  bool _loading = true;
  String? _error;
  TicketInfo? _selectedTicket;
  int _quantity = 1;
  bool _hasSeatSelectionFromSeats = false;
  bool _hasPricingConfig = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final e = await getEventById(widget.eventId);
      bool hasSeatSelectionFromSeats = false;
      bool hasPricingConfig = false;
      String effectivePricingModel = e.venue?.pricingModel ?? 'ticket_info';
      try {
        final seatData = await getEventSeats(widget.eventId);
        hasSeatSelectionFromSeats =
            seatData.placeIds.isNotEmpty || seatData.sections.isNotEmpty;
        final modelFromSeatData = seatData.venue?['pricingModel']?.toString().trim();
        if (modelFromSeatData != null && modelFromSeatData.isNotEmpty) {
          effectivePricingModel = modelFromSeatData;
        }
        hasPricingConfig = (effectivePricingModel == 'pricing_configuration') && seatData.pricingConfig != null;
      } catch (err, stack) {
        debugPrint('[EventDetail] seats API failed: $err');
        debugPrint('[EventDetail] stack: $stack');
        // Fallback must stay strict: only trust the event's explicit seat-selection signal.
        // Using "venue exists" caused non-seated events to incorrectly show "Choose seats".
        hasSeatSelectionFromSeats = e.hasSeatSelection;
      }
      setState(() {
        _event = e;
        _hasSeatSelectionFromSeats = hasSeatSelectionFromSeats;
        _hasPricingConfig = hasPricingConfig;
        _loading = false;
        if (e.ticketInfo.isNotEmpty && _selectedTicket == null) {
          _selectedTicket = e.ticketInfo.first;
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Widget _mapButton(String geoCode) {
    final parts = geoCode.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.length < 2) return const SizedBox.shrink();
    final url = 'https://www.google.com/maps?q=${parts[0]},${parts[1]}';
    return TextButton.icon(
      icon: const Icon(Icons.map, size: 20),
      label: const Text('Open in Maps'),
      onPressed: () => _openUrl(url),
    );
  }

  Widget _merchantAvatar(String? name) {
    return CircleAvatar(
      radius: 28,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(
        (name != null && name.isNotEmpty) ? name[0].toUpperCase() : 'O',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// False when event is sold out and no waitlist is offered; otherwise true when user can tap the main CTA.
  bool _canProceedToEventAction(Event event, String? waitlistOffer, bool isPreSaleFull) {
    debugPrint('event.isSoldOut: ${event.isSoldOut} waitlistOffer: $waitlistOffer isPreSaleFull: $isPreSaleFull');

    final hasSeatSelectionEffective = event.hasSeatSelection || _hasSeatSelectionFromSeats;
    // IMPORTANT: ticket_info sold-out must NOT block seated events. Only block
    // when this is a pure ticket-model event (no seat selection).
    if (!hasSeatSelectionEffective && event.isSoldOut && waitlistOffer != 'sold_out') {
      return false;
    }
    return hasSeatSelectionEffective || _selectedTicket != null;
  }

  void _buyTickets() {
    final event = _event;
    if (event == null) return;
    if ( !event.hasSeatSelection && event.isSoldOut) return;
    if (event.isFreeEvent) return; // Free events use FreeEventRegistrationModal instead.
    final merchantId = event.merchant?.id ?? event.merchantId;
    final externalMerchantId = event.externalMerchantId ?? event.merchant?.merchantId ?? '';
    if (merchantId == null || merchantId.isEmpty) return;
    final hasSeatSelectionEffective = event.hasSeatSelection || _hasSeatSelectionFromSeats;
    if (hasSeatSelectionEffective) {
      debugPrint('[Seats] Choose seats clicked — eventId=${event.id}, pushing to /events/${event.id}/seats');
      context.push('/events/${event.id}/seats');
      debugPrint('[Seats] Push to seats route completed');
      return;
    }
    if (_selectedTicket == null) return;
    final selectedTicket = _selectedTicket!;
    final isScanCountPass = (selectedTicket.scanCount ?? 0) > 0;
    final currency = currencyFromCountry(event.country);
    // ScanCount passes are personal season/recurring passes: force qty=1 per purchase.
    final qty = isScanCountPass ? 1 : (selectedTicket.price == 0 ? 1 : _quantity);
    debugPrint('finalPricePerTicket: ${_selectedTicket!.finalPricePerTicket}');
    debugPrint('[Checkout] isScanCountPass=$isScanCountPass qty=$qty');
    final effectiveBaseTaxRate =
        (selectedTicket.entertainmentTax != null &&
                (selectedTicket.entertainmentTax ?? 0) > 0)
            ? (selectedTicket.entertainmentTax ?? 0)
            : (selectedTicket.vat ?? 0);
    final taxLabel = 'VAT';
    final payload = CheckoutPayload(
      eventId: event.id,
      eventName: event.eventTitle,
      merchantId: merchantId,
      externalMerchantId: externalMerchantId,
      email: '',
      country: event.country,
      ticketId: selectedTicket.id,
      ticketName: selectedTicket.name,
      price: selectedTicket.price,
      serviceFee: (selectedTicket.serviceFee ?? 0).toDouble(),
      serviceTax: (selectedTicket.serviceTax ?? 0).toDouble(),
      orderFee: (selectedTicket.orderFee ?? 0).toDouble(),
      // Match backend/web rule: entertainmentTax when > 0, otherwise VAT.
      vat: effectiveBaseTaxRate.toDouble(),
      taxLabel: taxLabel,
      quantity: qty,
      currency: currency,
      paytrailEnabled: event.merchant?.paytrailEnabled ?? false,
      finalPricePerTicket: selectedTicket.finalPricePerTicket,
    );
    context.push('/checkout', extra: payload);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Event')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _event == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Event')),
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
    final event = _event!;
    final bool isScanCountPass = (_selectedTicket?.scanCount ?? 0) > 0;
    final waitlistOffer = event.waitlistOffer;
    final isPreSaleFull = event.isPreSaleWaitlistFull;
    final date = DateTime.tryParse(event.eventDate);
    final dateStr = date != null ? DateFormat.yMMMd().add_Hm().format(date) : event.eventDate;
    return Scaffold(
      appBar: AppBar(
        title: Text(event.eventTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(ThemeScope.of(context).themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: ThemeScope.of(context).toggleTheme,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (event.eventPromotionPhoto != null && event.eventPromotionPhoto!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  event.eventPromotionPhoto!,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(height: 200, child: Icon(Icons.image_not_supported, size: 48)),
                ),
              )
            else
              const SizedBox(height: 0),
            const SizedBox(height: 16),
            Text(event.eventTitle, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(dateStr),
            if (event.venueInfo?.name != null) Text('Venue: ${event.venueInfo!.name}'),
            if (event.eventLocationAddress != null) Text(event.eventLocationAddress!),
            if (event.eventDescription != null && event.eventDescription!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(event.eventDescription!),
            ],
            if (event.eventLocationAddress != null || event.transportLink != null || event.eventLocationGeoCode != null) ...[
              const SizedBox(height: 24),
              Text('Location', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (event.venueInfo?.name != null) Text(event.venueInfo!.name!, style: const TextStyle(fontWeight: FontWeight.w500)),
              if (event.eventLocationAddress != null) ...[const SizedBox(height: 4), Text(event.eventLocationAddress!)],
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (event.transportLink != null && event.transportLink!.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.directions, size: 20),
                      label: const Text('Get directions'),
                      onPressed: () => _openUrl(event.transportLink!),
                    ),
                  if (event.eventLocationGeoCode != null && event.eventLocationGeoCode!.isNotEmpty)
                    _mapButton(event.eventLocationGeoCode!),
                ],
              ),
            ],
            if (event.videoUrl != null && event.videoUrl!.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Video', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.play_circle_outline, size: 22),
                label: const Text('Watch video'),
                onPressed: () => _openUrl(event.videoUrl!),
              ),
            ],
            if (event.merchant != null) ...[
              const SizedBox(height: 24),
              Text('Organizer', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Material(
                elevation: 1,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (event.merchant!.logo != null && event.merchant!.logo!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: Image.network(
                            event.merchant!.logo!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _merchantAvatar(event.merchant!.name),
                          ),
                        )
                      else
                        _merchantAvatar(event.merchant!.name),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.merchant!.name ?? 'Event Organizer',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (event.merchant!.website != null && event.merchant!.website!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: () => _openUrl(event.merchant!.website!),
                                child: Text(
                                  'Visit website',
                                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 14),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (event.venueInfo?.website != null && event.venueInfo!.website!.isNotEmpty) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () => _openUrl(event.venueInfo!.website!),
                child: Text('Venue website', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              ),
            ],
            // Only show ticket list for non-seat events without pricing configuration.
            if (!(event.hasSeatSelection || _hasSeatSelectionFromSeats) &&
                !_hasPricingConfig &&
                event.ticketInfo.isNotEmpty &&
                waitlistOffer == null) ...[
              const SizedBox(height: 24),
              const Text('Ticket types', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...event.ticketInfo.map((t) => _TicketTile(
                    ticket: t,
                    currency: currencyFromCountry(event.country),
                    groupValue: _selectedTicket,
                    onTap: () => setState(() {
                      _selectedTicket = t;
                      final isScanCountPass = (t.scanCount ?? 0) > 0;
                      if (t.price == 0 || isScanCountPass) {
                        _quantity = 1;
                      }
                    }),
                  )),
              if (_selectedTicket != null && _selectedTicket!.price > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Quantity: '),
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: !isScanCountPass && _quantity > 1
                          ? () => setState(() => _quantity--)
                          : null,
                    ),
                    Text(isScanCountPass ? '1' : '$_quantity'),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: isScanCountPass ? null : () => setState(() => _quantity++),
                    ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canProceedToEventAction(event, waitlistOffer, isPreSaleFull)
                    ? () {
                        if (event.isFreeEvent && _selectedTicket != null) {
                          showDialog<void>(
                            context: context,
                            barrierDismissible: true,
                            builder: (ctx) => FreeEventRegistrationModal(
                              event: event,
                              ticket: _selectedTicket!,
                              onClose: () => Navigator.of(ctx).pop(),
                            ),
                          );
                          return;
                        }
                        if (waitlistOffer != null && !(waitlistOffer == 'pre_sale' && isPreSaleFull)) {
                          showDialog<void>(
                            context: context,
                            barrierDismissible: true,
                            builder: (ctx) => WaitlistJoinModal(
                              eventId: event.id,
                              waitlistOffer: waitlistOffer,
                              onClose: () => Navigator.of(ctx).pop(),
                            ),
                          );
                        } else {
                          _buyTickets();
                        }
                      }
                    : null,
                child: Text(
                  (event.hasSeatSelection || _hasSeatSelectionFromSeats)
                      ? 'Choose seats'
                      : event.isSoldOut && waitlistOffer != 'sold_out'
                          ? 'Sold out'
                          : event.isFreeEvent
                              ? 'Register'
                              : waitlistOffer == 'pre_sale'
                                  ? (isPreSaleFull ? 'Pre-sale waitlist full' : 'Join pre-sale waitlist')
                                  : waitlistOffer == 'sold_out'
                                      ? 'Join waitlist'
                                      : 'Buy tickets',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketTile extends StatelessWidget {
  const _TicketTile({
    required this.ticket,
    required this.currency,
    required this.groupValue,
    required this.onTap,
  });

  final TicketInfo ticket;
  final String currency;
  final TicketInfo? groupValue;
  final VoidCallback onTap;

  static String _fmtPct(double rate) {
    // Don't round away decimals (e.g. 13.5%). Keep up to 2dp, trim trailing zeros.
    final s = rate.toStringAsFixed(2);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = <Widget>[
      Text('${ticket.name}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Row(
        children: [
          Text('Price', style: theme.textTheme.bodySmall),
          const Spacer(),
          Text(formatPrice(ticket.price, currency), style: theme.textTheme.bodySmall),
        ],
      ),
    ];
    if (ticket.serviceFeeAmount > 0) {
      lines.add(Row(
        children: [
          Text('Service fee', style: theme.textTheme.bodySmall),
          const Spacer(),
          Text(formatPrice(ticket.serviceFeeAmount, currency), style: theme.textTheme.bodySmall),
        ],
      ));
      if (ticket.serviceFeeTaxAmount > 0) {
        lines.add(Row(
          children: [
            Text('Service tax on service fee', style: theme.textTheme.bodySmall),
            const Spacer(),
            Text(formatPrice(ticket.serviceFeeTaxAmount, currency), style: theme.textTheme.bodySmall),
          ],
        ));
      }
    }
    if (ticket.orderFeeAmount > 0) {
      lines.add(Row(
        children: [
          Text('Order fee', style: theme.textTheme.bodySmall),
          const Spacer(),
          Text(formatPrice(ticket.orderFeeAmount, currency), style: theme.textTheme.bodySmall),
        ],
      ));
      if (ticket.orderFeeTaxAmount > 0) {
        lines.add(Row(
          children: [
            Text('Service tax on order fee', style: theme.textTheme.bodySmall),
            const Spacer(),
            Text(formatPrice(ticket.orderFeeTaxAmount, currency), style: theme.textTheme.bodySmall),
          ],
        ));
      }
    }
    final baseTaxLabel = 'VAT';
    if (ticket.vatRate > 0) {
      lines.add(Row(
        children: [
          Text('$baseTaxLabel ${_fmtPct(ticket.vatRate)}%', style: theme.textTheme.bodySmall),
          const Spacer(),
          Text(formatPrice(ticket.vatAmountPerTicket, currency), style: theme.textTheme.bodySmall),
        ],
      ));
    }
    lines.add(const SizedBox(height: 4));
    lines.add(Row(
      children: [
        Text('Total per ticket', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(formatPrice(ticket.finalPricePerTicket, currency), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      ],
    ));
    if (ticket.available != null) {
      lines.add(const SizedBox(height: 2));
      lines.add(Text('${ticket.available} available', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)));
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: RadioListTile<TicketInfo>(
        value: ticket,
        groupValue: groupValue,
        onChanged: (_) => onTap(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: lines,
        ),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }
}

/// Two-step waitlist join: 1) enter email → send code; 2) enter code → join.
class WaitlistJoinModal extends StatefulWidget {
  const WaitlistJoinModal({
    super.key,
    required this.eventId,
    required this.waitlistOffer,
    required this.onClose,
  });

  final String eventId;
  final String waitlistOffer; // 'pre_sale' | 'sold_out'
  final VoidCallback onClose;

  @override
  State<WaitlistJoinModal> createState() => _WaitlistJoinModalState();
}

class _WaitlistJoinModalState extends State<WaitlistJoinModal> {
  String _step = 'email';
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _success = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  static const _locale = 'en-US';

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() {
        _error = 'Please enter a valid email address';
      });
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await waitlistSendCode(
        widget.eventId,
        email: email,
        locale: _locale,
      );
      if (!mounted) return;
      setState(() {
        _step = 'code';
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException
          ? e.message
          : e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '');
      final alreadyOn = e is ApiException && (e.statusCode == 409 || msg.toLowerCase().contains('already'));
      setState(() {
        _loading = false;
        _error = alreadyOn ? 'You are already on the waitlist.' : msg;
      });
    }
  }

  Future<void> _join() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Please enter the code from your email.');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await waitlistJoin(
        widget.eventId,
        email: _emailController.text.trim(),
        code: code,
        locale: _locale,
      );
      if (!mounted) return;
      setState(() {
        _success = true;
        _loading = false;
      });
      await Future<void>.delayed(const Duration(milliseconds: 2000));
      if (!mounted) return;
      widget.onClose();
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException
          ? e.message
          : e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '');
      final alreadyOn = e is ApiException && (e.statusCode == 409 || msg.toLowerCase().contains('already'));
      if (alreadyOn) {
        setState(() {
          _success = true;
          _loading = false;
        });
        await Future<void>.delayed(const Duration(milliseconds: 2000));
        if (!mounted) return;
        widget.onClose();
      } else {
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPreSale = widget.waitlistOffer == 'pre_sale';
    final title = isPreSale ? 'Join pre-sale waitlist' : 'Join waitlist';

    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: _success
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  "You're on the list! We'll notify you when tickets are available.",
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              )
            : _step == 'email'
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Enter your email and we\'ll send you a verification code.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          hintText: 'you@example.com',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _sendCode(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loading ? null : _sendCode,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Send code'),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Check your email and enter the code we sent you.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.numberWithOptions(signed: false, decimal: false),
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Verification code',
                          hintText: 'e.g. 31543442',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _join(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loading ? null : _join,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Join waitlist'),
                      ),
                    ],
                  ),
      ),
      actions: [
        if (!_success)
          TextButton(
            onPressed: () => widget.onClose(),
            child: const Text('Cancel'),
          ),
      ],
    );
  }
}

/// Free event registration: email + quantity (1) + marketingOptIn, then POST to free-event-register.
class FreeEventRegistrationModal extends StatefulWidget {
  const FreeEventRegistrationModal({
    super.key,
    required this.event,
    required this.ticket,
    required this.onClose,
  });

  final Event event;
  final TicketInfo ticket;
  final VoidCallback onClose;

  @override
  State<FreeEventRegistrationModal> createState() => _FreeEventRegistrationModalState();
}

class _FreeEventRegistrationModalState extends State<FreeEventRegistrationModal> {
  final _emailController = TextEditingController();
  final _confirmEmailController = TextEditingController();
  int _quantity = 1;
  bool _marketingOptIn = false;
  bool _loading = false;
  String? _error;
  bool _success = false;

  @override
  void dispose() {
    _emailController.dispose();
    _confirmEmailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final confirmEmail = _confirmEmailController.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    if (email != confirmEmail) {
      setState(() => _error = 'Email and confirm email do not match.');
      return;
    }
    final merchantId = widget.event.merchant?.id ?? widget.event.merchantId ?? '';
    final externalMerchantId = widget.event.externalMerchantId ?? widget.event.merchant?.merchantId ?? '';
    debugPrint('[FreeEvent] merchantId=$merchantId externalMerchantId=$externalMerchantId eventId=${widget.event.id} ticketId=${widget.ticket.id}');
    if (merchantId.isEmpty) {
      debugPrint('[FreeEvent] validation failed: Event organizer not set');
      setState(() => _error = 'Event organizer not set.');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await registerFreeEvent(
        email: email,
        quantity: _quantity,
        eventId: widget.event.id,
        ticketId: widget.ticket.id,
        merchantId: merchantId,
        externalMerchantId: externalMerchantId,
        eventName: widget.event.eventTitle,
        ticketName: widget.ticket.name,
        marketingOptIn: _marketingOptIn,
      );
      debugPrint('[FreeEvent] registration succeeded');
      if (!mounted) return;
      setState(() {
        _success = true;
        _loading = false;
      });
      await Future<void>.delayed(const Duration(milliseconds: 2000));
      if (!mounted) return;
      widget.onClose();
    } catch (e, stack) {
      debugPrint('[FreeEvent] registration failed: $e');
      debugPrint('[FreeEvent] stack: $stack');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Register for free event'),
      content: SingleChildScrollView(
        child: _success
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  "You're registered. We've sent your ticket to your email — check your inbox.",
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.primary),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Enter your email to register. No payment required.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'you@example.com',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmEmailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Confirm email',
                      hintText: 'Re-enter your email',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: _marketingOptIn,
                    onChanged: (v) => setState(() => _marketingOptIn = v ?? false),
                    title: Text('Send me news and offers', style: theme.textTheme.bodyMedium),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Register'),
                  ),
                ],
              ),
      ),
      actions: [
        if (!_success)
          TextButton(
            onPressed: () => widget.onClose(),
            child: const Text('Cancel'),
          ),
      ],
    );
  }
}
