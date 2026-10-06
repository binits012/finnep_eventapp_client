import 'api_client.dart';

/// Register for a free event (no payment). Matches web POST front/free-event-register.
Future<void> registerFreeEvent({
  required String email,
  required int quantity,
  required String eventId,
  required String ticketId,
  required String merchantId,
  required String externalMerchantId,
  required String eventName,
  required String ticketName,
  bool marketingOptIn = false,
  Map<String, dynamic>? registrationAnswers,
}) async {
  final body = <String, dynamic>{
    'email': email.trim(),
    'quantity': quantity,
    'eventId': eventId,
    'ticketId': ticketId,
    'merchantId': merchantId,
    'externalMerchantId': externalMerchantId,
    'eventName': eventName,
    'ticketName': ticketName,
    'marketingOptIn': marketingOptIn,
  };
  if (registrationAnswers != null && registrationAnswers.isNotEmpty) {
    body['registrationAnswers'] = registrationAnswers;
  }

  final response = await apiPost('/free-event-register', body: body);
  throwIfNotOk(response);
}
