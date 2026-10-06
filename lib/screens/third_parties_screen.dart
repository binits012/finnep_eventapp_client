import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';

/// High-level list of services that may process data or handle payments.
/// Full legal text lives on the site privacy policy.
class ThirdPartiesScreen extends StatelessWidget {
  const ThirdPartiesScreen({super.key});

  Future<void> _openPrivacy() async {
    final uri = Uri.parse(publicPrivacyUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Third-party services'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Okazzo uses the following categories of third-party services. '
            'What we collect and how we use it is described in our privacy policy.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          _PartyTile(
            title: 'Stripe',
            subtitle: 'Card and wallet payments (e.g. Google Pay, Apple Pay), fraud prevention.',
          ),
          _PartyTile(
            title: 'Paytrail',
            subtitle: 'Alternative payment methods where enabled for your region.',
          ),
          _PartyTile(
            title: 'Google',
            subtitle: 'Google Pay (where available), Play services, and related infrastructure on Android.',
          ),
          const SizedBox(height: 24),
          Text(
            'This list is illustrative. For definitions, retention, and your rights, see the full policy on our website.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _openPrivacy,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Open privacy policy'),
          ),
        ],
      ),
    );
  }
}

class _PartyTile extends StatelessWidget {
  const _PartyTile({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
