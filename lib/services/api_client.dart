import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'guest_token_store.dart';

String _baseUrl() {
  var url = apiBaseUrl;
  if (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

Future<Map<String, String>> _headers({bool guest = false}) async {
  final map = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
  if (guest) {
    final token = await GuestTokenStore.get();
    if (token != null && token.isNotEmpty) {
      map['Authorization'] = 'Bearer $token';
    }
  }
  return map;
}

Future<http.Response> apiGet(String path, {bool guest = false}) async {
  final uri = Uri.parse('${_baseUrl()}$path');
  final response = await http.get(uri, headers: await _headers(guest: guest));
  if (kDebugMode && path.startsWith('/guest/ticket/')) {
    debugPrint('[API GET][ticket] $uri');
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final data = decoded['data'];
          if (data is Map<String, dynamic>) {
            final ticketInfo = data['ticketInfo'];
            if (ticketInfo is Map<String, dynamic>) {
              ticketInfo.remove('email');
              ticketInfo.remove('otp');
              ticketInfo.remove('ticketId');
            }
            // Some APIs also include ticketFor at the top-level `data`.
            if (data.containsKey('ticketFor')) {
              data['ticketFor'] = null;
            }
          }
          debugPrint('[API GET][ticket][response][redacted] ${jsonEncode(decoded)}');
        } else {
          debugPrint('[API GET][ticket][response] ${response.body}');
        }
      } catch (_) {
        // Fallback: raw log, in case the response isn't JSON.
        debugPrint('[API GET][ticket][response] ${response.body}');
      }
  }
  return response;
}

Future<http.Response> apiPost(String path,
    {Map<String, dynamic>? body, bool guest = false}) async {
  final uri = Uri.parse('${_baseUrl()}$path');
  final encoded = body != null ? jsonEncode(body) : null;
  if (kDebugMode) {
    debugPrint('[API POST] $uri');
    if (encoded != null) debugPrint('[API BODY] $encoded');
  }
  final response = await http.post(uri,
      headers: await _headers(guest: guest),
      body: encoded);
  if (kDebugMode && response.statusCode >= 400) {
    debugPrint('[API RESPONSE ${response.statusCode}] ${response.body}');
  }
  return response;
}

Future<http.Response> apiPatch(String path,
    {Map<String, dynamic>? body, bool guest = false}) async {
  final uri = Uri.parse('${_baseUrl()}$path');
  final encoded = body != null ? jsonEncode(body) : null;
  if (kDebugMode) {
    debugPrint('[API PATCH] $uri');
    if (encoded != null) debugPrint('[API BODY] $encoded');
  }
  final response = await http.patch(uri,
      headers: await _headers(guest: guest),
      body: encoded);
  if (kDebugMode && response.statusCode >= 400) {
    debugPrint('[API RESPONSE ${response.statusCode}] ${response.body}');
  }
  return response;
}

Map<String, dynamic>? parseJsonBody(http.Response response) {
  final s = response.body;
  if (s.isEmpty) return null;
  return jsonDecode(s) as Map<String, dynamic>?;
}

String _errorMessageFromBody(Map<String, dynamic>? body, http.Response response) {
  if (body == null) return response.reasonPhrase ?? 'Request failed';
  final msg = body['message'] as String?;
  if (msg != null && msg.isNotEmpty) return msg;
  final err = body['error'];
  if (err is String && err.isNotEmpty) return err;
  if (err is List && err.isNotEmpty && err.first is String) return err.first as String;
  return response.reasonPhrase ?? 'Request failed';
}

void throwIfNotOk(http.Response response) {
  if (response.statusCode >= 200 && response.statusCode < 300) return;
  final body = parseJsonBody(response);
  throw ApiException(response.statusCode, _errorMessageFromBody(body, response));
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}
