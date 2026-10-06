import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../utils/market_country_code.dart';
import '../utils/registration_form.dart';
import 'api_client.dart';

MediaType _contentTypeFromMime(String mimeType) {
  final parts = mimeType.split('/');
  if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
    return MediaType(parts[0], parts[1]);
  }
  return MediaType('application', 'octet-stream');
}

Future<RegistrationFileAnswerRef> uploadRegistrationFile({
  required String eventId,
  required String fieldId,
  required List<int> bytes,
  required String fileName,
  required String mimeType,
}) async {
  if (bytes.length > registrationFileMaxBytes) {
    throw ApiException(400, 'File too large');
  }

  final uri = buildApiUri('/event/$eventId/registration-upload');
  final request = http.MultipartRequest('POST', uri);
  final market = resolveMarketCountryCodeForApi();
  if (market != null && market.isNotEmpty) {
    request.headers['x-country-code'] = market;
  }
  request.fields['fieldId'] = fieldId;
  request.files.add(
    http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: fileName,
      contentType: _contentTypeFromMime(mimeType),
    ),
  );

  final streamed = await request.send();
  final response = await http.Response.fromStream(streamed);
  throwIfNotOk(response);
  final body = parseJsonBody(response);
  if (body == null) throw ApiException(500, 'No response');
  return RegistrationFileAnswerRef.fromJson(body);
}

Future<void> deleteRegistrationUpload({
  required String eventId,
  required String uploadId,
}) async {
  final uri = buildApiUri('/event/$eventId/registration-upload/$uploadId');
  final headers = <String, String>{'Accept': 'application/json'};
  final market = resolveMarketCountryCodeForApi();
  if (market != null && market.isNotEmpty) {
    headers['x-country-code'] = market;
  }
  final response = await http.delete(uri, headers: headers);
  throwIfNotOk(response);
}
