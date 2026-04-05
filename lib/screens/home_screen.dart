import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/event.dart';
import '../models/site_notification.dart';
import '../services/event_service.dart';
import '../services/site_notification_dismiss_store.dart';
import '../theme_scope.dart';
import '../utils/currency.dart';
import '../utils/site_notice_utils.dart';
import '../widgets/home_site_notice_widgets.dart';
import '../widgets/site_notice_popover_dialog.dart';

Future<void> _openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

bool _eventIsFree(Event e) {
  if (e.ticketInfo.isEmpty) return true;
  return e.ticketInfo.every((t) => t.price == 0);
}

String _eventPriceLabel(Event e) {
  if (_eventIsFree(e)) return 'Free';
  final minPrice = e.ticketInfo.map((t) => t.price).reduce((a, b) => a < b ? a : b);
  final currency = currencyFromCountry(e.country);
  return 'From ${formatPrice(minPrice, currency)}';
}

Widget _priceChip(BuildContext context, Event event, {double fontSize = 12}) {
  // For events with seat selection / pricing configuration, we do NOT show a
  // ticket-model based price here. Pricing comes from seat tiers/zones instead,
  // and if that data isn't available on this screen it's safer to show no price
  // than a misleading "From X€".
  if (event.hasSeatSelection) {
    return const SizedBox.shrink();
  }
  final isFree = _eventIsFree(event);
  final label = _eventPriceLabel(event);
  return Container(
    padding: EdgeInsets.symmetric(horizontal: fontSize > 11 ? 8 : 6, vertical: fontSize > 11 ? 4 : 2),
    decoration: BoxDecoration(
      color: isFree ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(fontSize > 11 ? 8 : 6),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: isFree ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onSecondaryContainer,
      ),
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Event> _events = [];
  List<SiteNotification> _notifications = [];
  Set<String> _dismissed = {};
  bool _scheduledPopovers = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dismissed = await SiteNotificationDismissStore.load();
      final data = await getDataForFront();
      if (!mounted) return;
      setState(() {
        _events = data.events;
        _notifications = data.notifications;
        _dismissed = dismissed;
        _loading = false;
      });
      if (!_scheduledPopovers) {
        _scheduledPopovers = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _runPopoverQueue();
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _dismissNotice(String id) async {
    await SiteNotificationDismissStore.dismiss(id);
    if (!mounted) return;
    setState(() {
      _dismissed.add(id);
    });
  }

  Future<void> _runPopoverQueue() async {
    final pops = _notifications.where((n) {
      if (_dismissed.contains(n.id)) return false;
      if (resolveSiteNoticeVariant(n.notificationTypeName) != SiteNoticeVariant.popOver) {
        return false;
      }
      return hasRenderableRichNotificationHtml(n.notificationHtml);
    }).toList();

    for (final n in pops) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => SiteNoticePopoverDialog(html: n.notificationHtml),
      );
      if (mounted) await _dismissNotice(n.id);
    }
  }

  static DateTime? _parseLocal(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  static bool _isFutureStart(Event e) {
    final start = _parseLocal(e.eventDate);
    if (start == null) return false;
    return start.isAfter(DateTime.now().toLocal());
  }

  static bool _isTodayStart(Event e) {
    final start = _parseLocal(e.eventDate);
    if (start == null) return false;
    final now = DateTime.now().toLocal();
    return start.year == now.year && start.month == now.month && start.day == now.day;
  }

  static bool _isActiveNow(Event e) {
    final now = DateTime.now().toLocal();
    final start = _parseLocal(e.eventDate);
    if (start == null) return false;
    final end = _parseLocal(e.eventEndDate) ?? start;
    return !start.isAfter(now) && !end.isBefore(now);
  }

  List<Event> get _featured {
    return _events
        .where((e) =>
            e.featured?.isFeatured == true && _isFutureStart(e))
        .toList()
      ..sort((a, b) => (b.featured?.priority ?? 0).compareTo(a.featured?.priority ?? 0));
  }

  List<Event> get _today {
    final featuredIds = _featured.map((e) => e.id).toSet();
    return _events
        .where((e) =>
            !featuredIds.contains(e.id) &&
            (_isTodayStart(e) || _isActiveNow(e) || e.status == 'on-going'))
        .toList()
      ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
  }

  List<Event> get _upcoming {
    final featuredIds = _featured.map((e) => e.id).toSet();
    final todayIds = _today.map((e) => e.id).toSet();
    return _events
        .where((e) =>
            !featuredIds.contains(e.id) &&
            !todayIds.contains(e.id) &&
            _isFutureStart(e))
        .toList()
      ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Okazzo Events'),
        actions: [
          IconButton(
            icon: Icon(ThemeScope.of(context).themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: ThemeScope.of(context).toggleTheme,
          ),
          TextButton(
            onPressed: () => context.go('/events'),
            child: const Text('Events'),
          ),
          TextButton(
            onPressed: () => context.go('/my-tickets'),
            child: const Text('My Tickets'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _buildBodyWithNotices(context),
    );
  }

  Widget _buildBodyWithNotices(BuildContext context) {
    final marquees = _notifications.where((n) {
      if (_dismissed.contains(n.id)) return false;
      if (resolveSiteNoticeVariant(n.notificationTypeName) != SiteNoticeVariant.marquee) return false;
      return htmlToPlainText(n.notificationHtml).trim().isNotEmpty;
    }).toList();

    final inline = _notifications.where((n) {
      if (_dismissed.contains(n.id)) return false;
      if (resolveSiteNoticeVariant(n.notificationTypeName) != SiteNoticeVariant.inBetween) return false;
      return hasRenderableRichNotificationHtml(n.notificationHtml);
    }).toList();

    final footer = _notifications.where((n) {
      if (_dismissed.contains(n.id)) return false;
      if (resolveSiteNoticeVariant(n.notificationTypeName) != SiteNoticeVariant.footerBased) return false;
      return hasRenderableRichNotificationHtml(n.notificationHtml);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...marquees.map(
          (n) => SiteNoticeMarqueeRow(
            item: n,
            onDismiss: () => _dismissNotice(n.id),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...inline.map(
                    (n) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SiteNoticeRichCard(
                        item: n,
                        onDismiss: () => _dismissNotice(n.id),
                      ),
                    ),
                  ),
                  if (_featured.isNotEmpty) ...[
                    const Text('Featured', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _FeaturedCarousel(events: _featured),
                    const SizedBox(height: 24),
                  ],
                  if (_today.isNotEmpty) ...[
                    const Text('Happening today', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _EventList(events: _today),
                    const SizedBox(height: 24),
                  ],
                  const Text('Upcoming', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _EventList(events: _upcoming),
                  if (footer.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    ...footer.map(
                      (n) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SiteNoticeRichCard(
                          item: n,
                          denseBottom: true,
                          onDismiss: () => _dismissNotice(n.id),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EventList extends StatelessWidget {
  const _EventList({required this.events});

  final List<Event> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No events'),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final e = events[i];
        return _EventCard(event: e);
      },
    );
  }
}

class _FeaturedCarousel extends StatelessWidget {
  const _FeaturedCarousel({required this.events});

  final List<Event> events;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 282,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: events.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          return SizedBox(width: 300, child: _CarouselCard(event: events[i]));
        },
      ),
    );
  }
}

class _CarouselCard extends StatelessWidget {
  const _CarouselCard({required this.event});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(event.eventDate);
    final dateStr = date != null ? DateFormat.yMMMd().add_Hm().format(date) : event.eventDate;
    final venueName = event.venue?.name ?? event.venueInfo?.name;
    final secondary = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
    const cardHeight = 280.0;
    const imageHeight = 112.0;
    return SizedBox(
      height: cardHeight,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/events/${event.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (event.eventPromotionPhoto != null && event.eventPromotionPhoto!.isNotEmpty)
                Image.network(
                  event.eventPromotionPhoto!,
                  height: imageHeight,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => SizedBox(height: imageHeight, child: Center(child: Icon(Icons.image_not_supported, color: secondary))),
                )
              else
                Container(height: imageHeight, color: Theme.of(context).colorScheme.surfaceContainerHighest, child: Icon(Icons.event, size: 48, color: secondary)),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [Expanded(child: Text(event.eventTitle, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis)), const SizedBox(width: 8), _priceChip(context, event, fontSize: 10)]),
                      const SizedBox(height: 4),
                      Row(children: [Icon(Icons.schedule, size: 12, color: secondary), const SizedBox(width: 4), Expanded(child: Text(dateStr, style: TextStyle(color: secondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis))]),
                      if (venueName != null && venueName.isNotEmpty) ...[const SizedBox(height: 2), Row(children: [Icon(Icons.place, size: 12, color: secondary), const SizedBox(width: 4), Expanded(child: Text(venueName, style: TextStyle(color: secondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis))])],
                      if (event.eventLocationAddress != null && event.eventLocationAddress!.isNotEmpty) ...[const SizedBox(height: 2), Text(event.eventLocationAddress!, style: TextStyle(color: secondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)],
                      if (event.city != null && event.city!.isNotEmpty) ...[const SizedBox(height: 2), Text(event.city!, style: TextStyle(color: secondary, fontSize: 11))],
                      if (event.merchant != null && (event.merchant!.name != null && event.merchant!.name!.isNotEmpty)) ...[const SizedBox(height: 4), Row(children: [Icon(Icons.business, size: 12, color: secondary), const SizedBox(width: 4), Expanded(child: Text(event.merchant!.name!, style: TextStyle(color: secondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis))])],
                      if ((event.videoUrl != null && event.videoUrl!.isNotEmpty) || (event.transportLink != null && event.transportLink!.isNotEmpty)) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            if (event.videoUrl != null && event.videoUrl!.isNotEmpty)
                              GestureDetector(
                                onTap: () => _openUrl(event.videoUrl!),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.videocam, size: 12, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 4), Text('Watch video', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary))]),
                              ),
                            if (event.transportLink != null && event.transportLink!.isNotEmpty)
                              GestureDetector(
                                onTap: () => _openUrl(event.transportLink!),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.directions, size: 12, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 4), Text('Transport', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary))]),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(event.eventDate);
    final dateStr = date != null ? DateFormat.yMMMd().add_Hm().format(date) : event.eventDate;
    final venueName = event.venue?.name ?? event.venueInfo?.name;
    final secondary = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
    return Card(
      child: InkWell(
        onTap: () => context.push('/events/${event.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (event.eventPromotionPhoto != null && event.eventPromotionPhoto!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    event.eventPromotionPhoto!,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 80, height: 80, child: Icon(Icons.image_not_supported)),
                  ),
                )
              else
                const SizedBox(width: 80, height: 80, child: Icon(Icons.event)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [Expanded(child: Text(event.eventTitle, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16), maxLines: 3, overflow: TextOverflow.ellipsis)), const SizedBox(width: 8), _priceChip(context, event)]),
                    const SizedBox(height: 4),
                    Row(children: [Icon(Icons.schedule, size: 12, color: secondary), const SizedBox(width: 4), Expanded(child: Text(dateStr, style: TextStyle(color: secondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis))]),
                    if (venueName != null && venueName.isNotEmpty) ...[const SizedBox(height: 2), Row(children: [Icon(Icons.place, size: 12, color: secondary), const SizedBox(width: 4), Expanded(child: Text(venueName, style: TextStyle(color: secondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis))])],
                    if (event.eventLocationAddress != null && event.eventLocationAddress!.isNotEmpty) ...[const SizedBox(height: 2), Text(event.eventLocationAddress!, style: TextStyle(color: secondary, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis)],
                    if (event.city != null && event.city!.isNotEmpty) ...[const SizedBox(height: 2), Text(event.city!, style: TextStyle(color: secondary, fontSize: 12))],
                    if (event.merchant != null && event.merchant!.name != null && event.merchant!.name!.isNotEmpty) ...[const SizedBox(height: 2), Row(children: [Icon(Icons.business, size: 12, color: secondary), const SizedBox(width: 4), Expanded(child: Text(event.merchant!.name!, style: TextStyle(color: secondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis))])],
                    if ((event.videoUrl != null && event.videoUrl!.isNotEmpty) || (event.transportLink != null && event.transportLink!.isNotEmpty)) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          if (event.videoUrl != null && event.videoUrl!.isNotEmpty)
                            GestureDetector(
                              onTap: () => _openUrl(event.videoUrl!),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.videocam, size: 14, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 4), Text('Watch video', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary))]),
                            ),
                          if (event.transportLink != null && event.transportLink!.isNotEmpty)
                            GestureDetector(
                              onTap: () => _openUrl(event.transportLink!),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.directions, size: 14, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 4), Text('Transport', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary))]),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
