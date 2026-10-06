import 'package:flutter/widgets.dart';

/// iOS share sheet rejects {{0,0},{0,0}} and any rect outside the source view.
/// A small inset box stays non-zero and inside a full-screen view such as
/// {{0,0},{393,852}}.
Rect shareSheetOrigin(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final viewWidth = size.width < 1 ? 1.0 : size.width;
  final viewHeight = size.height < 1 ? 1.0 : size.height;
  final boxWidth = viewWidth < 48 ? viewWidth : 48.0;
  final boxHeight = viewHeight < 24 ? viewHeight : 24.0;
  final left = ((viewWidth - boxWidth) / 2).clamp(0.0, viewWidth - boxWidth);
  final top = (viewHeight - boxHeight - 16).clamp(0.0, viewHeight - boxHeight);
  return Rect.fromLTWH(left, top, boxWidth, boxHeight);
}
