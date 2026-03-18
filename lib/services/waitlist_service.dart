import 'api_client.dart';

/// Send verification code to email. Optional [captchaToken] for backend captcha.
Future<void> waitlistSendCode(
  String eventId, {
  required String email,
  String? captchaToken,
  String locale = 'en-US',
}) async {
  final body = <String, dynamic>{
    'email': email.trim(),
    'locale': locale,
  };
  if (captchaToken != null && captchaToken.isNotEmpty) {
    body['captchaToken'] = captchaToken;
  }
  final response = await apiPost('/event/$eventId/waitlist/send-code', body: body);
  throwIfNotOk(response);
}

/// Join waitlist with email and code received by email.
Future<void> waitlistJoin(
  String eventId, {
  required String email,
  required String code,
  String locale = 'en-US',
}) async {
  final response = await apiPost('/event/$eventId/waitlist', body: {
    'email': email.trim(),
    'code': code.trim(),
    'locale': locale,
  });
  throwIfNotOk(response);
}
