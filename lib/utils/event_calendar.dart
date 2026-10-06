import '../models/event.dart';

class EventCalendarPayload {
  const EventCalendarPayload({
    required this.title,
    required this.description,
    required this.location,
    required this.url,
    required this.start,
    required this.end,
  });

  final String title;
  final String description;
  final String location;
  final String url;
  final DateTime start;
  final DateTime end;
}

String _escapeIcsText(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('\n', r'\n')
      .replaceAll(',', r'\,')
      .replaceAll(';', r'\;');
}

String toCalendarUtcStamp(DateTime date) {
  final utc = date.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}'
      '${two(utc.month)}'
      '${two(utc.day)}'
      'T'
      '${two(utc.hour)}'
      '${two(utc.minute)}'
      '${two(utc.second)}'
      'Z';
}

DateTime _resolveEndDate(Event event, DateTime start) {
  final raw = event.eventEndDate;
  var end = raw != null && raw.isNotEmpty
      ? DateTime.tryParse(raw)
      : null;
  end ??= start.add(const Duration(hours: 2));
  if (!end.isAfter(start)) {
    end = start.add(const Duration(hours: 2));
  }
  return end;
}

String _plainDescription(String? html) {
  if (html == null || html.isEmpty) return '';
  return html
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

EventCalendarPayload? buildEventCalendarPayload(Event event, String pageUrl) {
  if (event.eventDate.isEmpty) return null;
  final start = DateTime.tryParse(event.eventDate);
  if (start == null) return null;

  final end = _resolveEndDate(event, start);
  final locationParts = <String>[
    if ((event.venueInfo?.name ?? '').trim().isNotEmpty) event.venueInfo!.name!.trim(),
    if ((event.eventLocationAddress ?? event.city ?? '').trim().isNotEmpty)
      (event.eventLocationAddress ?? event.city)!.trim(),
  ];

  final descriptionParts = <String>[
    _plainDescription(event.eventDescription).charactersTake(500),
    pageUrl,
  ].where((s) => s.isNotEmpty).toList();

  return EventCalendarPayload(
    title: event.eventTitle.trim().isEmpty ? 'Event' : event.eventTitle.trim(),
    description: descriptionParts.join('\n\n'),
    location: locationParts.join(', '),
    url: pageUrl,
    start: start,
    end: end,
  );
}

extension on String {
  String charactersTake(int max) => length <= max ? this : substring(0, max);
}

String buildIcsContent(EventCalendarPayload payload) {
  final stamp = toCalendarUtcStamp(DateTime.now());
  final uidHash = payload.url.codeUnits.fold<int>(0, (acc, ch) => acc + ch).abs();
  final uid = '${toCalendarUtcStamp(payload.start)}-$uidHash@okazzo';
  final lines = <String?>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Okazzo Events//Event//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    'UID:$uid',
    'DTSTAMP:$stamp',
    'DTSTART:${toCalendarUtcStamp(payload.start)}',
    'DTEND:${toCalendarUtcStamp(payload.end)}',
    'SUMMARY:${_escapeIcsText(payload.title)}',
    'DESCRIPTION:${_escapeIcsText(payload.description)}',
    if (payload.location.isNotEmpty) 'LOCATION:${_escapeIcsText(payload.location)}',
    if (payload.url.isNotEmpty) 'URL:${payload.url}',
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return '${lines.whereType<String>().join('\r\n')}\r\n';
}

String buildGoogleCalendarUrl(EventCalendarPayload payload) {
  final params = <String, String>{
    'action': 'TEMPLATE',
    'text': payload.title,
    'dates':
        '${toCalendarUtcStamp(payload.start)}/${toCalendarUtcStamp(payload.end)}',
    'details': payload.description,
    'location': payload.location,
  };
  return Uri.https('calendar.google.com', '/calendar/render', params).toString();
}

String buildOutlookCalendarUrl(EventCalendarPayload payload) {
  final params = <String, String>{
    'path': '/calendar/action/compose',
    'rru': 'addevent',
    'subject': payload.title,
    'body': payload.description,
    'location': payload.location,
    'startdt': payload.start.toUtc().toIso8601String(),
    'enddt': payload.end.toUtc().toIso8601String(),
  };
  return Uri.https(
    'outlook.live.com',
    '/calendar/0/deeplink/compose',
    params,
  ).toString();
}

String slugifyCalendarFilename(String title) {
  final base = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (base.isEmpty) return 'event';
  return base.length <= 48 ? base : base.substring(0, 48);
}
