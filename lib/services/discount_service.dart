import 'api_client.dart';
import '../utils/money.dart';

class DiscountValidateResult {
  const DiscountValidateResult({
    required this.valid,
    this.error,
    this.code,
    this.couponId,
    this.discountAmount,
    this.name,
  });

  final bool valid;
  final String? error;
  final String? code;
  final String? couponId;
  final double? discountAmount;
  final String? name;
}

/// POST `/event/:eventId/discount/validate` — must pass catalog base subtotal (`unit price × qty`).
Future<DiscountValidateResult> validateEventDiscountCode({
  required String eventId,
  required String rawCode,
  required double orderBaseSubtotal,
}) async {
  final code = rawCode.trim();
  if (code.isEmpty) {
    return const DiscountValidateResult(valid: false, error: 'Enter a discount code');
  }
  final response = await apiPost(
    '/event/$eventId/discount/validate',
    body: {
      'code': code,
      'orderBaseSubtotal': roundMoney(orderBaseSubtotal),
    },
  );
  throwIfNotOk(response);
  final json = parseJsonBody(response);
  if (json == null) {
    return const DiscountValidateResult(valid: false, error: 'Unexpected response');
  }
  final valid = json['valid'] == true;
  if (!valid) {
    final msg = json['error']?.toString() ?? 'Invalid code';
    return DiscountValidateResult(valid: false, error: msg);
  }
  final amt = (json['discountAmount'] as num?)?.toDouble();
  if (amt == null || !amt.isFinite) {
    return const DiscountValidateResult(valid: false, error: 'Invalid discount response');
  }
  return DiscountValidateResult(
    valid: true,
    code: json['code']?.toString(),
    couponId: json['couponId']?.toString(),
    discountAmount: roundMoney(amt),
    name: json['name']?.toString(),
  );
}
