import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/site_notice_utils.dart';

/// Renders CMS HTML (links open externally; images supported).
class SiteNoticeHtmlBlock extends StatelessWidget {
  const SiteNoticeHtmlBlock({super.key, required this.html});

  final String html;

  @override
  Widget build(BuildContext context) {
    final sanitized = sanitizeCmsHtml(html);
    final cs = Theme.of(context).colorScheme;
    return Html(
      data: sanitized,
      shrinkWrap: true,
      style: {
        'body': Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          fontSize: FontSize(14),
          color: cs.onSurface,
        ),
        'img': Style(
          width: Width(100, Unit.percent),
          height: Height.auto(),
        ),
        'a': Style(color: cs.primary),
      },
      onLinkTap: (url, attributes, element) {
        if (url == null || url.isEmpty) return;
        final uri = Uri.tryParse(url);
        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
      },
    );
  }
}
