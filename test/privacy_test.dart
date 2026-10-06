import 'package:flutter_test/flutter_test.dart';
import 'package:okazzo/utils/privacy.dart';

void main() {
  test('maskEmailForDisplay obfuscates local and domain name', () {
    expect(maskEmailForDisplay('nidhi@example.com'), 'n***i@e***e.com');
    expect(maskEmailForDisplay('a@example.com'), 'a***@e***e.com');
  });

  test('maskEmailForDisplay leaves invalid email-like values unchanged', () {
    expect(maskEmailForDisplay(''), '');
    expect(maskEmailForDisplay('not-an-email'), 'not-an-email');
    expect(maskEmailForDisplay('a@@example.com'), 'a@@example.com');
  });
}
