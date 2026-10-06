import 'dart:convert';
import 'dart:typed_data';

/// PNG stored on the ticket. Same image the ticket email attaches, encoding the Mongo id.
Uint8List? decodeServerTicketQrPng(dynamic qrCode) {
  if (qrCode == null) return null;
  if (qrCode is String) {
    final value = qrCode.trim();
    if (value.isEmpty) return null;
    final payload = value.startsWith('data:image')
        ? value.substring(value.indexOf(',') + 1)
        : value;
    try {
      return base64Decode(payload);
    } catch (_) {
      return null;
    }
  }
  if (qrCode is! Map) return null;
  final data = qrCode['data'];
  if (data is! List || data.isEmpty) return null;
  final bytes = Uint8List.fromList(
    data.map((dynamic n) => (n as num).toInt() & 0xff).toList(),
  );
  final asText = utf8.decode(bytes, allowMalformed: true);
  if (asText.startsWith('data:image')) {
    final payload = asText.substring(asText.indexOf(',') + 1);
    try {
      return base64Decode(payload);
    } catch (_) {
      return null;
    }
  }
  if (bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50) return bytes;
  return null;
}

/// Purchased ticket document id. The venue scanner looks this up. Not the entry code.
String purchasedTicketMongoId(dynamic rawId) {
  if (rawId is String) {
    final value = rawId.trim();
    return RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(value) ? value : '';
  }
  if (rawId is Map) {
    final nested = rawId[r'$oid'] ?? rawId['_id'] ?? rawId['oid'];
    return purchasedTicketMongoId(nested);
  }
  return '';
}

/// Aligns with web client: backend may still return a parent/master QR for qty>1,
/// but the app only shows per-guest entry QRs in that case.
int parseTicketOrderQuantity(String? quantityStr, Map<String, dynamic>? ticketInfo) {
  final s = (quantityStr ?? '').trim();
  if (s.isNotEmpty) {
    final n = int.tryParse(s);
    if (n != null && n >= 1) return n;
  }
  if (ticketInfo != null) {
    final q = ticketInfo['quantity'];
    final n2 = int.tryParse(q?.toString().trim() ?? '');
    if (n2 != null && n2 >= 1) return n2;
  }
  return 1;
}

bool showMasterEntryQrOnClient(int orderQuantity) => orderQuantity <= 1;

/// `ticketInfo.childQRCodes` from API: `{ childIndex, childQrCodeValue }`.
List<Map<String, dynamic>> parseChildQrCodes(Map<String, dynamic>? ticketInfo) {
  if (ticketInfo == null) return [];
  final list = ticketInfo['childQRCodes'];
  if (list is! List) return [];
  final out = <Map<String, dynamic>>[];
  for (final item in list) {
    if (item is! Map) continue;
    final m = Map<String, dynamic>.from(item);
    final v = (m['childQrCodeValue'] ?? m['child_qr_code_value'])?.toString().trim() ?? '';
    if (v.isEmpty) continue;
    out.add(m);
  }
  return out;
}
