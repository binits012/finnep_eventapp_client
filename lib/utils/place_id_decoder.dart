import 'dart:convert';

class DecodedPlaceId {
  final String section;
  final String tierCode;
  final int row;
  final int seat;
  final double x;
  final double y;
  final bool available;
  final List<String> tags;

  DecodedPlaceId({
    required this.section,
    required this.tierCode,
    required this.row,
    required this.seat,
    required this.x,
    required this.y,
    this.available = true,
    this.tags = const [],
  });
}

String _base64UrlDecode(String input) {
  var s = input.replaceAll('-', '+').replaceAll('_', '/');
  while (s.length % 4 != 0) {
    s += '=';
  }
  return utf8.decode(base64.decode(s));
}

DecodedPlaceId? decodePlaceId(String placeId) {
  if (placeId.isEmpty) return null;
  try {
    if (!placeId.contains('|')) return null;
    final parts = placeId.split('|');
    if (parts.length >= 5) {
      final sectionB64 = parts[0].length > 4 ? parts[0].substring(4) : parts[0];
      final section = _base64UrlDecode(sectionB64);
      final tierCode = parts[1];
      final positionCode = parts[2];
      final availableFlag = parts[3];
      final position = _decodePosition(positionCode);
      if (position == null) return null;
      List<String> tags = [];
      if (parts[4].isNotEmpty) {
        try {
          final t = _base64UrlDecode(parts[4]);
          tags = t.split(',').where((e) => e.isNotEmpty).toList();
        } catch (_) {}
      }
      return DecodedPlaceId(
        section: section,
        tierCode: tierCode,
        row: position.$1,
        seat: position.$2,
        x: position.$3,
        y: position.$4,
        available: availableFlag == '1',
        tags: tags,
      );
    }
    if (parts.length == 3) {
      final sectionB64 = parts[0].length > 4 ? parts[0].substring(4) : parts[0];
      final section = _base64UrlDecode(sectionB64);
      final tierCode = parts[1];
      final position = _decodePosition(parts[2]);
      if (position == null) return null;
      return DecodedPlaceId(
        section: section,
        tierCode: tierCode,
        row: position.$1,
        seat: position.$2,
        x: position.$3,
        y: position.$4,
      );
    }
  } catch (_) {}
  return null;
}

(int, int, double, double)? _decodePosition(String code) {
  if (code.isEmpty) return null;
  try {
    final combinedValue = int.tryParse(code, radix: 36);
    if (combinedValue == null) return null;
    const two48 = 281474976710656;
    const two32 = 4294967296;
    const two16 = 65536;
    final row = (combinedValue ~/ two48) & 0xFFFF;
    final seat = (combinedValue ~/ two32) & 0xFFFF;
    final x = (combinedValue ~/ two16) & 0xFFFF;
    final y = combinedValue & 0xFFFF;
    return (row, seat, x.toDouble(), y.toDouble());
  } catch (_) {}
  return null;
}
