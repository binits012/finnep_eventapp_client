import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okazzo/widgets/seat_map_canvas.dart';

void main() {
  test('curtain covers the overview and clears once zoomed in', () {
    const inputOverview = 1.0;
    const inputOpen = 1.2;
    const inputInside = 1.7;
    final actualOverview = curtainOpacityForZoom(
      relativeZoom: inputOverview,
      sectionOpen: false,
    );
    final actualOpen = curtainOpacityForZoom(
      relativeZoom: inputOpen,
      sectionOpen: false,
    );
    final actualInside = curtainOpacityForZoom(
      relativeZoom: inputInside,
      sectionOpen: false,
    );
    final actualSection = curtainOpacityForZoom(
      relativeZoom: inputOverview,
      sectionOpen: true,
    );
    expect(actualOverview, 1);
    expect(actualOpen, closeTo(1 - (0.2 / 0.7), 0.0001));
    expect(actualInside, 0);
    expect(actualSection, 0);
  });

  test('fitted overview scale ignores the unchanged Z axis', () {
    final Matrix4 inputMatrix = Matrix4.diagonal3Values(0.2, 0.2, 1);
    final double actualScale = viewScaleOf(inputMatrix);
    expect(actualScale, closeTo(0.2, 0.0001));
    expect(inputMatrix.getMaxScaleOnAxis(), 1);
  });
}
