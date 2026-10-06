import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okazzo/utils/share_origin.dart';

void main() {
  testWidgets('share origin is non-zero inside an iPhone view', (tester) async {
    late Rect origin;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(393, 852)),
        child: Builder(
          builder: (context) {
            origin = shareSheetOrigin(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    const view = Rect.fromLTWH(0, 0, 393, 852);
    expect(origin.isEmpty, isFalse);
    expect(origin.left, greaterThanOrEqualTo(view.left));
    expect(origin.top, greaterThanOrEqualTo(view.top));
    expect(origin.right, lessThanOrEqualTo(view.right));
    expect(origin.bottom, lessThanOrEqualTo(view.bottom));
  });
}
