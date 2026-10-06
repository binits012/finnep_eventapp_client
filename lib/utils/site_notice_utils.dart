// Mirrors web notificationTypes / sanitizeCmsHtml behavior.

enum SiteNoticeVariant {
  marquee,
  inBetween,
  popOver,
  footerBased,
}

SiteNoticeVariant resolveSiteNoticeVariant(String? typeName) {
  final raw = (typeName ?? '').trim().toLowerCase().replaceAll('_', '-');
  if (raw == 'marquee' || raw == 'marqueee') return SiteNoticeVariant.marquee;
  if (raw == 'in-between' || raw == 'inbetween' || raw == 'between') {
    return SiteNoticeVariant.inBetween;
  }
  if (raw == 'pop-over' || raw == 'popover') return SiteNoticeVariant.popOver;
  if (raw == 'footer-based' || raw == 'footer' || raw == 'footerbased') {
    return SiteNoticeVariant.footerBased;
  }
  return SiteNoticeVariant.inBetween;
}

String htmlToPlainText(String html) {
  if (html.isEmpty) return '';
  return html
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Basic hardening (aligned with web sanitizeCmsHtml).
String sanitizeCmsHtml(String html) {
  if (html.isEmpty) return '';
  var s = html;
  s = s.replaceAll(RegExp(r'<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'<iframe\b[^<]*(?:(?!<\/iframe>)<[^<]*)*<\/iframe>', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'\s*on\w+\s*=\s*("[^"]*"|[^\s>]+)', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'javascript:', caseSensitive: false), '');
  s = _normalizeQuillBulletLists(s);
  return s;
}

String _normalizeQuillBulletLists(String html) {
  // Quill serializes bullet lists as <ol><li data-list="bullet">...</li></ol>.
  // Convert pure bullet blocks to <ul> so non-Quill renderers show bullets.
  return html.replaceAllMapped(
    RegExp(r'<ol\b([^>]*)>([\s\S]*?)<\/ol>', caseSensitive: false),
    (match) {
      final attrs = match.group(1) ?? '';
      final inner = match.group(2) ?? '';
      final hasBulletItems = RegExp(
        "<li\\b[^>]*\\sdata-list=[\"']bullet[\"'][^>]*>",
        caseSensitive: false,
      ).hasMatch(inner);
      final hasOrderedItems = RegExp(
        "<li\\b[^>]*\\sdata-list=[\"']ordered[\"'][^>]*>",
        caseSensitive: false,
      ).hasMatch(inner);

      if (!hasBulletItems || hasOrderedItems) {
        return match.group(0) ?? '';
      }

      final normalizedInner = inner
          .replaceAll(RegExp("\\sdata-list=[\"'][^\"']*[\"']", caseSensitive: false), '')
          .replaceAll(
            RegExp(
              "<span\\b[^>]*class=[\"'][^\"']*\\bql-ui\\b[^\"']*[\"'][^>]*><\\/span>",
              caseSensitive: false,
            ),
            '',
          );

      return '<ul$attrs>$normalizedInner</ul>';
    },
  );
}

bool hasRenderableRichNotificationHtml(String html) {
  final cleaned = sanitizeCmsHtml(html);
  if (cleaned.trim().isEmpty) return false;
  final textOnly = cleaned.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&nbsp;', ' ').trim();
  if (textOnly.isNotEmpty) return true;
  return RegExp(r'<(img|picture|source|video|audio|figure|svg)\b', caseSensitive: false).hasMatch(cleaned);
}
