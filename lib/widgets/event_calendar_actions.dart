import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../models/event.dart';
import '../utils/event_calendar.dart';
import '../utils/share_origin.dart';

/// Add-to-calendar control matching marketplace / silo (Apple ICS, Google, Outlook).
class EventCalendarActions extends StatelessWidget {
  const EventCalendarActions({super.key, required this.event});

  final Event event;

  String get _pageUrl => '$publicSiteBaseUrl/events/${event.id}';

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _shareIcs(BuildContext context, EventCalendarPayload payload) async {
    try {
      final dir = await getTemporaryDirectory();
      final name = '${slugifyCalendarFilename(payload.title)}.ics';
      final file = File('${dir.path}/$name');
      await file.writeAsString(buildIcsContent(payload), flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/calendar')],
        subject: payload.title,
        text: 'Add "${payload.title}" to your calendar',
        sharePositionOrigin: shareSheetOrigin(context),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create calendar file')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final payload = buildEventCalendarPayload(event, _pageUrl);
    if (payload == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return PopupMenuButton<String>(
      tooltip: 'Add to calendar',
      onSelected: (value) async {
        switch (value) {
          case 'apple':
            await _shareIcs(context, payload);
            break;
          case 'google':
            await _openUrl(buildGoogleCalendarUrl(payload));
            break;
          case 'outlook':
            await _openUrl(buildOutlookCalendarUrl(payload));
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'apple', child: Text('Apple Calendar')),
        PopupMenuItem(value: 'google', child: Text('Google Calendar')),
        PopupMenuItem(value: 'outlook', child: Text('Outlook')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available, size: 20, color: scheme.primary),
            const SizedBox(width: 8),
            Text(
              'Add to calendar',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            Icon(Icons.arrow_drop_down, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

Future<void> shareEventLink(BuildContext context, Event event) async {
  final url = '$publicSiteBaseUrl/events/${event.id}';
  final date = DateTime.tryParse(event.eventDate);
  final dateLabel = date != null
      ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
      : event.eventDate;
  await Share.share(
    '${event.eventTitle}\n$dateLabel\n$url',
    subject: event.eventTitle,
    sharePositionOrigin: shareSheetOrigin(context),
  );
}
