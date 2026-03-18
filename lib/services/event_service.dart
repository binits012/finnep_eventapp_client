import '../models/event.dart';
import 'api_client.dart';

Future<AppData> getDataForFront() async {
  final response = await apiGet('/');
  throwIfNotOk(response);
  final body = parseJsonBody(response);
  if (body == null) throw ApiException(500, 'Empty response');
  return AppData.fromJson(body);
}

Future<List<Event>> getEvents() async {
  final response = await apiGet('/events');
  throwIfNotOk(response);
  final body = parseJsonBody(response);
  final raw = body?['items'] ?? body?['event'] ?? body?['data'] ?? body;
  final list = _toEventList(raw);
  return list.map((e) => Event.fromJson(e)).toList();
}

List<Map<String, dynamic>> _toEventList(dynamic raw) {
  if (raw == null) return [];
  if (raw is List<dynamic>) {
    return raw
        .where((e) => e != null && e is Map)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
  if (raw is Map) return [Map<String, dynamic>.from(raw)];
  return [];
}

Future<Event> getEventById(String id, {String? presale}) async {
  var path = '/event/$id';
  if (presale != null && presale.isNotEmpty) {
    path += '?presale=${Uri.encodeComponent(presale)}';
  }
  final response = await apiGet(path);
  throwIfNotOk(response);
  final body = parseJsonBody(response);
  if (body == null) throw ApiException(404, 'Event not found');
  final data = body['data'] is Map ? body['data'] as Map<String, dynamic>? : null;
  final eventJson = body['event'] as Map<String, dynamic>? ??
      data?['event'] as Map<String, dynamic>? ??
      data ??
      body;
  return Event.fromJson(Map<String, dynamic>.from(eventJson));
}

class AppData {
  final List<Event> events;

  AppData({this.events = const []});

  factory AppData.fromJson(Map<String, dynamic> json) {
    final raw = json['event'] ?? json['events'];
    final list = _toEventList(raw);
    return AppData(
      events: list.map((e) => Event.fromJson(e)).toList(),
    );
  }
}
