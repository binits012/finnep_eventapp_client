import '../models/ticket.dart';
import 'api_client.dart';
import 'guest_token_store.dart';

Future<void> sendCode(String email) async {
  final response = await apiPost('/guest/send-code', body: {'email': email});
  throwIfNotOk(response);
}

Future<String> verifyCode(String email, String code) async {
  final response =
      await apiPost('/guest/verify-code', body: {'email': email, 'code': code});
  throwIfNotOk(response);
  final body = parseJsonBody(response);
  final token = body?['token'] as String? ?? body?['data']?['token'] as String?;
  if (token == null || token.isEmpty) throw ApiException(500, 'No token in response');
  await GuestTokenStore.set(token);
  return token;
}

Future<List<GuestTicket>> getTickets({int? year}) async {
  var path = '/guest/tickets';
  if (year != null) path += '?year=$year';
  final response = await apiGet(path, guest: true);
  throwIfNotOk(response);
  final body = parseJsonBody(response);
  final raw = body?['data'] ?? body?['tickets'];
  final list = _toTicketList(raw);
  return list.map((e) => GuestTicket.fromJson(e)).toList();
}

List<Map<String, dynamic>> _toTicketList(dynamic raw) {
  if (raw == null) return [];
  if (raw is List<dynamic>) {
    return raw.whereType<Map<String, dynamic>>().toList();
  }
  if (raw is Map<String, dynamic>) return [raw];
  return [];
}

Future<GuestTicket> getTicketById(String id) async {
  final response = await apiGet('/guest/ticket/$id', guest: true);
  throwIfNotOk(response);
  final body = parseJsonBody(response);
  final data = body?['data'] as Map<String, dynamic>? ?? body;
  if (data == null) throw ApiException(404, 'Ticket not found');
  return GuestTicket.fromJson(data);
}
