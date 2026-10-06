import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:okazzo/models/seat.dart';
import 'package:okazzo/services/seat_service.dart';

void main() {
  test('decodeSeats treats own reserved seats as selectable', () {
    final section = base64Url.encode(utf8.encode('Floor')).replaceAll('=', '');
    final position =
        ((1 * 281474976710656) + (1 * 4294967296) + (10 * 65536) + 20)
            .toRadixString(36);
    final placeId = 'sec_$section|standard|$position|1|';
    final data = SeatMapData(
      placeIds: [placeId],
      sold: const [],
      reserved: [placeId],
      ownReserved: [placeId],
      sections: const [],
    );

    final seats = decodeSeats(data);

    expect(seats, hasLength(1));
    expect(seats.first.status, SeatStatus.available);
  });
}
