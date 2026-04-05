import 'dart:async';

import 'package:flutter/material.dart';

import 'site_notice_html_block.dart';

const _kPopoverAutoDismiss = Duration(seconds: 10);

/// Modal notice with auto-dismiss (aligned with web ~10s).
class SiteNoticePopoverDialog extends StatefulWidget {
  const SiteNoticePopoverDialog({super.key, required this.html});

  final String html;

  @override
  State<SiteNoticePopoverDialog> createState() => _SiteNoticePopoverDialogState();
}

class _SiteNoticePopoverDialogState extends State<SiteNoticePopoverDialog> {
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    _auto = Timer(_kPopoverAutoDismiss, _close);
  }

  void _close() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _auto?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Notice'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: SiteNoticeHtmlBlock(html: widget.html),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _close,
          child: const Text('Close'),
        ),
      ],
    );
  }
}
