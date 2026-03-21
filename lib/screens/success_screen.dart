import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/currency.dart';
import '../utils/place_id_decoder.dart';

class SuccessScreen extends StatefulWidget {
  const SuccessScreen({super.key, this.ticketData});

  final Map<String, dynamic>? ticketData;

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen> {
  final GlobalKey _ticketKey = GlobalKey();
  bool _downloading = false;

  static Map<String, dynamic>? _getTicket(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    final data = raw['data'] as Map<String, dynamic>?;
    final ticket = raw['ticket'] as Map<String, dynamic>?;
    return data ?? ticket ?? (raw.containsKey('_id') ? raw : null);
  }

  static String _str(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is Map) {
      final name = v['venueName'] ?? v['name'] ?? v['address'];
      if (name != null) return _str(name);
      return '';
    }
    return v.toString();
  }

  /// Obfuscate email for display: "user@domain.com" → "u***r@domain.com".
  static String _obfuscateEmail(String email) {
    final s = email.trim();
    if (s.isEmpty || !s.contains('@')) return s;
    final parts = s.split('@');
    if (parts.length != 2) return s;
    final local = parts[0];
    final domain = parts[1];
    if (local.isEmpty) return '@$domain';
    if (local.length == 1) return '${local}***@$domain';
    return '${local[0]}***${local[local.length - 1]}@$domain';
  }

  static String _formatIsoDateTimeReadable(String iso) {
    final s = iso.trim();
    if (s.isEmpty) return '';
    try {
      final dt = DateTime.parse(s).toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      // 2026-03-17 14:05 (local)
      return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return s;
    }
  }

  static String _seatLabelFromPlaceIds(List<String> placeIds) {
    final decoded = <DecodedPlaceId>[];
    for (final pid in placeIds) {
      final d = decodePlaceId(pid);
      if (d != null) decoded.add(d);
    }
    if (decoded.isEmpty) return '';
    final first = decoded.first;
    final rawSection = first.section.trim();
    final section = rawSection.toLowerCase().startsWith('section')
        ? rawSection
        : 'Section $rawSection';
    if (decoded.length == 1) {
      return '$section • Row ${first.row} • Seat ${first.seat}';
    }
    return '$section • Row ${first.row} • Seat ${first.seat} (+${decoded.length - 1} more)';
  }

  String _field(Map<String, dynamic>? ticket, Map<String, dynamic>? ticketInfo, List<String> keys) {
    final data = widget.ticketData?['data'] as Map<String, dynamic>?;
    for (final k in keys) {
      final v = ticketInfo?[k] ?? ticket?[k] ?? data?[k] ?? widget.ticketData?[k];
      if (v != null) {
        final s = _str(v);
        if (s.isNotEmpty) return s;
      }
    }
    return '';
  }

  Future<void> _downloadTicket() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    String? errorMsg;
    try {
      await Future.delayed(const Duration(milliseconds: 150));
      Uint8List? pngBytes;
      final ro = _ticketKey.currentContext?.findRenderObject();
      if (ro is RenderRepaintBoundary) {
        try {
          final image = await ro.toImage(pixelRatio: 3.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) pngBytes = byteData.buffer.asUint8List();
        } catch (_) {}
      }
      if (pngBytes == null || pngBytes.isEmpty) {
        final payload = _getQrPayload();
        if (payload.isNotEmpty) {
          try {
            final painter = QrPainter(
              data: payload,
              version: QrVersions.auto,
              gapless: true,
            );
            final byteData = await painter.toImageData(300, format: ui.ImageByteFormat.png);
            if (byteData != null) pngBytes = byteData.buffer.asUint8List();
          } catch (_) {}
        }
      }
      if (pngBytes == null || pngBytes.isEmpty) {
        errorMsg = 'Could not generate ticket image';
      } else {
        final name = 'ticket_${DateTime.now().millisecondsSinceEpoch}.png';
        String dirPath;
        try {
          final dir = await getTemporaryDirectory();
          dirPath = dir.path;
        } on PlatformException {
          if (!Platform.isAndroid) rethrow;
          const channel = MethodChannel('com.finnep.eventapp/cache_path');
          final path = await channel.invokeMethod<String>('getCachePath');
          if (path == null || path.isEmpty) {
            throw PlatformException(code: 'cache_path', message: 'No cache path');
          }
          dirPath = path;
        }
        final file = File('$dirPath/$name');
        await file.writeAsBytes(pngBytes);
        if (!await file.exists()) {
          errorMsg = 'Could not save file';
        } else {
          try {
            await Share.shareXFiles([XFile(file.path)], text: 'My event ticket');
          } catch (shareError) {
            errorMsg = shareError is Exception ? shareError.toString().replaceFirst('Exception: ', '') : 'Share failed';
          }
        }
      }
    } catch (e, stack) {
      debugPrint('Download ticket error: $e');
      debugPrint(stack.toString());
      final raw = e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'Could not share ticket';
      errorMsg = raw.length > 120 ? '${raw.substring(0, 117)}…' : raw;
    }
    if (mounted) {
      setState(() => _downloading = false);
      if (errorMsg != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg)));
      }
    }
  }

  String _getQrPayload() {
    final ticket = _getTicket(widget.ticketData);
    final ticketId = ticket?['_id'] != null ? _str(ticket!['_id']) : null;
    return ticketId ?? widget.ticketData?['ticketId'] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ticketData == null) {
      debugPrint('[SuccessScreen] ticketData is NULL');
    } else {
      debugPrint('[SuccessScreen] ticketData keys: ${widget.ticketData!.keys.toList()}');
      debugPrint('[SuccessScreen] ticketData.data present: ${widget.ticketData!.containsKey('data')}');
    }
    final ticket = _getTicket(widget.ticketData);
    if (ticket != null) {
      debugPrint('[SuccessScreen] ticket keys: ${ticket.keys.toList()}');
      if (ticket['ticketInfo'] != null && ticket['ticketInfo'] is Map) {
        debugPrint('[SuccessScreen] ticket.ticketInfo keys: ${(ticket['ticketInfo'] as Map).keys.toList()}');
      }
    } else {
      debugPrint('[SuccessScreen] ticket is null');
    }
    final ticketInfo = ticket != null && ticket['ticketInfo'] != null
        ? (ticket['ticketInfo'] is Map<String, dynamic>
            ? ticket['ticketInfo'] as Map<String, dynamic>
            : null)
        : null;
    debugPrint('[SuccessScreen] ticketInfo: ${ticketInfo != null ? ticketInfo.keys.toList() : null}');
    final eventTitle = _field(ticket, ticketInfo, ['eventName', 'eventTitle']);
    final eventDate = _field(ticket, ticketInfo, ['eventDate', 'date', 'startDate']);
    final venue = _field(ticket, ticketInfo, ['venue', 'location', 'place', 'address']);
    final ticketNameFromServer = _field(ticket, ticketInfo, ['ticketName', 'ticketType', 'tier']);
    final ticketForRaw = _field(ticket, ticketInfo, ['email', 'attendeeEmail', 'ticketForEmail', 'ticketFor', 'attendee']);
    final clientEmail = _str(widget.ticketData?['_clientEmail']);
    final attendee = (clientEmail.contains('@') ? clientEmail : ticketForRaw);
    // Prefer client-provided ticket name (e.g. tier name) when server sends a generic one like "New Ticket".
    final clientTicketName = _str(widget.ticketData?['_clientTicketName']);
    // Seat location label is displayed separately from ticket type.
    final clientPlaceIdsRaw = widget.ticketData?['_clientPlaceIds'];
    final clientPlaceIds = clientPlaceIdsRaw is List ? clientPlaceIdsRaw.map((e) => _str(e)).where((e) => e.isNotEmpty).toList() : const <String>[];
    final ticketSeatLabel = clientPlaceIds.isNotEmpty ? _seatLabelFromPlaceIds(clientPlaceIds) : '';
    final ticketName = clientTicketName.isNotEmpty ? clientTicketName : ticketNameFromServer;
    final orderId = _field(ticket, ticketInfo, ['orderId', 'orderRef', 'reference']);
    // For your response shape, the real timestamp is `data.createdAt`.
    final purchaseDate = _field(ticket, ticketInfo, ['purchaseDate', 'createdAt', 'created']);
    final purchaseDateDisplay = purchaseDate.isNotEmpty ? _formatIsoDateTimeReadable(purchaseDate) : '';
    final quantity = _field(ticket, ticketInfo, ['quantity', 'qty']);
    // For your response shape, the entry code is `data.otp`.
    final entryCode = _field(ticket, ticketInfo, ['otp', 'entryCode', 'ticketCode', 'code']);
    final totalPaidRaw = _field(ticket, ticketInfo, ['totalPaid', 'total', 'amount']);
    final price = _field(ticket, ticketInfo, ['price']);
    final currency = _field(ticket, ticketInfo, ['currency']);

    // Prefer the client-side value we passed from PaymentScreen so 3-decimal totals
    // (e.g. 30.645) don't show up as 30.65 here.
    final clientCurrency = _str(widget.ticketData?['_clientCurrency']);
    final clientOverride = widget.ticketData?['_clientTotalAmountOverride'];
    final clientOverrideNum = clientOverride is num ? clientOverride.toDouble() : double.tryParse(_str(clientOverride));
    final clientCents = widget.ticketData?['_clientTotalCents'];
    final clientCentsNum = clientCents is num ? clientCents.toInt() : int.tryParse(_str(clientCents));
    final clientTotalDisplay = clientOverrideNum != null && clientOverrideNum > 0
        ? formatPriceWithDecimals(clientOverrideNum, clientCurrency.isNotEmpty ? clientCurrency : (currency.isNotEmpty ? currency : 'eur'), 3)
        : (clientCentsNum != null && clientCentsNum > 0)
            ? formatPriceWithDecimals(clientCentsNum / 100.0, clientCurrency.isNotEmpty ? clientCurrency : (currency.isNotEmpty ? currency : 'eur'), 2)
            : '';

    final totalPaid = clientTotalDisplay.isNotEmpty
        ? clientTotalDisplay
        : totalPaidRaw.isNotEmpty
            ? totalPaidRaw
            : (price.isNotEmpty && currency.isNotEmpty)
                ? '$price $currency'
                : price.isNotEmpty
                    ? price
                    : '';
    final ticketId = ticket?['_id'] != null ? _str(ticket!['_id']) : _str(widget.ticketData?['ticketId']);
    final qrPayload = ticketId.isNotEmpty ? ticketId : '';

    debugPrint('[SuccessScreen] eventTitle="$eventTitle" eventDate="$eventDate" venue="$venue" ticketName="$ticketName"');
    debugPrint('[SuccessScreen] attendee="$attendee" orderId="$orderId" purchaseDate="$purchaseDate" totalPaid="$totalPaid"');

    final scheme = Theme.of(context).colorScheme;
    final labelColor = scheme.onSurfaceVariant;
    final valueColor = scheme.onSurface;
    Widget _infoRow(String label, String value) {
      if (value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 100, child: Text('$label:', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: labelColor))),
            Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: valueColor))),
          ],
        ),
      );
    }

    final infoChildren = <Widget>[
      if (eventTitle.isNotEmpty) Text(eventTitle, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: valueColor)),
      if (eventDate.isNotEmpty) _infoRow('Date', eventDate),
      if (venue.isNotEmpty) _infoRow('Venue', venue),
      if (ticketName.isNotEmpty) _infoRow('Ticket', ticketName),
      if (ticketSeatLabel.isNotEmpty) _infoRow('Seating', ticketSeatLabel),
      if (totalPaid.isNotEmpty) _infoRow('Total', totalPaid),
      if (attendee.isNotEmpty) _infoRow('Attendee', attendee.contains('@') ? _obfuscateEmail(attendee) : attendee),
      if (quantity.isNotEmpty) _infoRow('Qty', quantity),
      if (orderId.isNotEmpty || ticketId.isNotEmpty || purchaseDate.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Order Information', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: valueColor)),
      ],
      if (orderId.isNotEmpty) _infoRow('Order', orderId),
      if (entryCode.isNotEmpty) _infoRow('Entry code', entryCode),
      if (purchaseDateDisplay.isNotEmpty) _infoRow('Purchased', purchaseDateDisplay),
    ];

    debugPrint('[SuccessScreen] infoChildren.length=${infoChildren.length}');

    return Scaffold(
      appBar: AppBar(title: const Text('Success')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Payment successful',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: scheme.onSurface),
              ),
            ),
            const SizedBox(height: 16),
            if (infoChildren.isNotEmpty || qrPayload.isNotEmpty)
              RepaintBoundary(
                key: _ticketKey,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (infoChildren.isNotEmpty) ...infoChildren,
                      if (qrPayload.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Center(
                          child: Text(
                            'Your ticket',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onSurface),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: QrImageView(
                              data: qrPayload,
                              version: QrVersions.auto,
                              size: 200,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: qrPayload.isNotEmpty && !_downloading ? _downloadTicket : null,
              icon: _downloading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download),
              label: Text(_downloading ? 'Preparing…' : 'Download ticket'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('Back to home'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
