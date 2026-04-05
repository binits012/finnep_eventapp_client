import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';

import '../models/site_notification.dart';
import '../utils/site_notice_utils.dart';
import 'site_notice_html_block.dart';

double marqueeVelocityForPlainTextLen(int len) {
  return (28 + len * 0.1).clamp(22.0, 80.0);
}

/// Sticky-style amber strip with scrolling plain text (matches web marquee).
class SiteNoticeMarqueeRow extends StatelessWidget {
  const SiteNoticeMarqueeRow({
    super.key,
    required this.item,
    required this.onDismiss,
  });

  final SiteNotification item;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final plain = htmlToPlainText(item.notificationHtml);
    final display = plain.trim().isEmpty ? '\u00A0' : plain;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.amber.shade900.withValues(alpha: 0.45) : Colors.amber.shade50;
    final fg = isDark ? Colors.amber.shade50 : Colors.amber.shade900;
    final border = isDark ? Colors.amber.shade800 : Colors.amber.shade200;

    return Material(
      color: bg,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: border.withValues(alpha: 0.6))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 36,
                child: Marquee(
                  text: display,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: fg),
                  scrollAxis: Axis.horizontal,
                  blankSpace: 48,
                  velocity: marqueeVelocityForPlainTextLen(display.length),
                  pauseAfterRound: const Duration(seconds: 1),
                  showFadingOnlyWhenScrolling: true,
                  startPadding: 8,
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: fg),
              tooltip: 'Dismiss',
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline / footer-style rich notice card.
class SiteNoticeRichCard extends StatelessWidget {
  const SiteNoticeRichCard({
    super.key,
    required this.item,
    required this.onDismiss,
    this.denseBottom = false,
  });

  final SiteNotification item;
  final VoidCallback onDismiss;
  final bool denseBottom;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.amber.shade900.withValues(alpha: 0.35) : Colors.amber.shade50;
    final border = isDark ? Colors.amber.shade800 : Colors.amber.shade200;

    return Material(
      color: bg,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: border.withValues(alpha: 0.5)),
          ),
        ),
        padding: EdgeInsets.fromLTRB(12, 10, 4, denseBottom ? 10 : 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: SiteNoticeHtmlBlock(html: item.notificationHtml)),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Dismiss',
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}
