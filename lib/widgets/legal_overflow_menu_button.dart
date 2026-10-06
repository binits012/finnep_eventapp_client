import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';

/// App bar overflow: Contact, Privacy, Terms (browser) + Third parties (in-app).
class LegalOverflowMenuButton extends StatelessWidget {
  const LegalOverflowMenuButton({super.key});

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_vert),
      tooltip: 'Legal & contact',
      onSelected: (value) async {
        switch (value) {
          case 'contact':
            await _open(publicContactUrl);
            break;
          case 'privacy':
            await _open(publicPrivacyUrl);
            break;
          case 'terms':
            await _open(publicTermsUrl);
            break;
          case 'third':
            if (context.mounted) context.push('/third-parties');
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'contact', child: Text('Contact')),
        PopupMenuItem(value: 'privacy', child: Text('Privacy policy')),
        PopupMenuItem(value: 'terms', child: Text('Terms & conditions')),
        PopupMenuItem(value: 'third', child: Text('Third-party services')),
      ],
    );
  }
}
