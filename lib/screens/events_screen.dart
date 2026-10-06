import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/event.dart';
import '../services/event_service.dart';
import '../navigation/adaptive_navigation.dart';
import '../theme_scope.dart';
import '../widgets/legal_overflow_menu_button.dart';
import '../utils/currency.dart';
import '../utils/event_listing_pricing.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

enum _EventsScope { today, tomorrow, all }

class _EventsScreenState extends State<EventsScreen> {
  List<Event> _events = [];
  bool _loading = true;
  String? _error;
  _EventsScope _scope = _EventsScope.all;

  bool _eventIsFree(Event e) {
    if (e.ticketInfo.isEmpty) return true;
    return e.ticketInfo.every((t) => t.price == 0);
  }

  String _eventPriceLabel(Event e) {
    if (e.isListingOnWaitlist) return 'Waitlist';
    if (_eventIsFree(e)) return 'Free';
    if (e.ticketInfo.isEmpty) return '';
    final minPrice = eventListingMinPayable(e);
    if (minPrice == null) return '';
    final currency = currencyFromCountry(e.country);
    return 'From ${formatPrice(minPrice, currency)}';
  }

  Widget _priceChip(
    BuildContext context,
    Event event, {
    double fontSize = 12,
    bool showFootnote = true,
  }) {
    // Web events listing: hides price/free label for strict external —
    // no replacement chip (matches empty `<span />` in TS).
    if (event.isExternalEvent) return const SizedBox.shrink();
    if (event.hasSeatSelection && !event.isListingOnWaitlist) {
      return const SizedBox.shrink();
    }
    final label = _eventPriceLabel(event);
    if (label.isEmpty) return const SizedBox.shrink();
    final onWaitlist = event.isListingOnWaitlist;
    final isFree = !onWaitlist && _eventIsFree(event);
    final includedFeesFootnote = isFree || onWaitlist || !showFootnote
        ? null
        : eventListingIncludedFeesFootnote(event);

    if (includedFeesFootnote == null) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: fontSize > 11 ? 8 : 6,
          vertical: fontSize > 11 ? 4 : 2,
        ),
        decoration: BoxDecoration(
          color: isFree
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(fontSize > 11 ? 8 : 6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: isFree
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: fontSize > 11 ? 8 : 6,
            vertical: fontSize > 11 ? 4 : 2,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(fontSize > 11 ? 8 : 6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          includedFeesFootnote,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  DateTime _localDayStart(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  DateTime? _eventDateLocalOrNull(Event e) =>
      DateTime.tryParse(e.eventDate)?.toLocal();
  DateTime? _eventEndDateLocalOrNull(Event e) => e.eventEndDate == null
      ? null
      : DateTime.tryParse(e.eventEndDate!)?.toLocal();

  bool _isEventActiveNow(Event e, DateTime nowLocal) {
    final start = _eventDateLocalOrNull(e);
    if (start == null) return false;
    final end = _eventEndDateLocalOrNull(e) ?? start;
    return !start.isAfter(nowLocal) && !end.isBefore(nowLocal);
  }

  _EventsBuckets _bucketEvents(List<Event> events) {
    final nowLocal = DateTime.now().toLocal();
    final todayStart = _localDayStart(nowLocal);
    final tomorrowStart = todayStart.add(const Duration(days: 1));
    final dayAfterTomorrowStart = tomorrowStart.add(const Duration(days: 1));

    final today = <Event>[];
    final tomorrow = <Event>[];
    final later = <Event>[];
    final undated = <Event>[];

    for (final e in events) {
      final dtLocal = _eventDateLocalOrNull(e);
      if (dtLocal == null) {
        undated.add(e);
        continue;
      }

      // Running multi-day events belong to "today" while active.
      if (_isEventActiveNow(e, nowLocal)) {
        today.add(e);
        continue;
      }

      if (!dtLocal.isBefore(todayStart) && dtLocal.isBefore(tomorrowStart)) {
        today.add(e);
      } else if (!dtLocal.isBefore(tomorrowStart) &&
          dtLocal.isBefore(dayAfterTomorrowStart)) {
        tomorrow.add(e);
      } else {
        later.add(e);
      }
    }

    int dateAsc(Event a, Event b) {
      final da = _eventDateLocalOrNull(a);
      final db = _eventDateLocalOrNull(b);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    }

    today.sort(dateAsc);
    tomorrow.sort(dateAsc);
    later.sort(dateAsc);
    undated.sort((a, b) => a.eventTitle.compareTo(b.eventTitle));

    return _EventsBuckets(
      today: today,
      tomorrow: tomorrow,
      later: later,
      undated: undated,
    );
  }

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
      final list = await getEvents();
      setState(() {
        _events = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Widget _buildEventCard(Event e, {bool isHorizontal = false, double? width}) {
    final date = DateTime.tryParse(e.eventDate);
    final dateStr = date != null
        ? DateFormat.yMMMd().add_Hm().format(date.toLocal())
        : e.eventDate;
    final venueName = e.venue?.name ?? e.venueInfo?.name;
    final secondary = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.7);

    final card = Card(
      margin: isHorizontal
          ? EdgeInsets.zero
          : const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.push('/events/${e.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (e.eventPromotionPhoto != null &&
                  e.eventPromotionPhoto!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    e.eventPromotionPhoto!,
                    width: isHorizontal ? 72 : 80,
                    height: isHorizontal ? 72 : 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => SizedBox(
                      width: isHorizontal ? 72 : 80,
                      height: isHorizontal ? 72 : 80,
                      child: const Icon(Icons.image_not_supported),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: isHorizontal ? 72 : 80,
                  height: isHorizontal ? 72 : 80,
                  child: const Icon(Icons.event),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.eventTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: isHorizontal ? 15 : 16,
                      ),
                      maxLines: isHorizontal ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_eventPriceLabel(e).isNotEmpty &&
                        !e.isExternalEvent &&
                        (!e.hasSeatSelection || e.isListingOnWaitlist)) ...[
                      const SizedBox(height: 6),
                      _priceChip(
                        context,
                        e,
                        fontSize: isHorizontal ? 10 : 12,
                        showFootnote: !isHorizontal,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 12, color: secondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            dateStr,
                            style: TextStyle(color: secondary, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (!isHorizontal && venueName != null && venueName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.place, size: 12, color: secondary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              venueName,
                              style: TextStyle(color: secondary, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (!isHorizontal &&
                        e.eventLocationAddress != null &&
                        e.eventLocationAddress!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        e.eventLocationAddress!,
                        style: TextStyle(color: secondary, fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (!isHorizontal && e.city != null && e.city!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        e.city!,
                        style: TextStyle(color: secondary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (!isHorizontal) const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );

    if (width == null) return card;
    return SizedBox(width: width, child: card);
  }

  @override
  Widget build(BuildContext context) {
    final buckets = _bucketEvents(_events);
    final nextUpEvents = [...buckets.today, ...buckets.tomorrow];

    final List<Event> verticalEvents;
    switch (_scope) {
      case _EventsScope.today:
        verticalEvents = buckets.today;
        break;
      case _EventsScope.tomorrow:
        verticalEvents = buckets.tomorrow;
        break;
      case _EventsScope.all:
        verticalEvents = [
          ...buckets.today,
          ...buckets.tomorrow,
          ...buckets.later,
          ...buckets.undated,
        ];
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Events'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => popOrGoHome(context),
        ),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              ThemeScope.of(context).themeMode == ThemeMode.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            onPressed: ThemeScope.of(context).toggleTheme,
          ),
          const LegalOverflowMenuButton(),
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
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                key: const PageStorageKey('events_scroll'),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (nextUpEvents.isNotEmpty) ...[
                            Text(
                              'Next up',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 156,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: nextUpEvents.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (context, i) {
                                  final e = nextUpEvents[i];
                                  return _buildEventCard(
                                    e,
                                    isHorizontal: true,
                                    width: 280,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('Today'),
                                selected: _scope == _EventsScope.today,
                                onSelected: (selected) {
                                  if (!selected) return;
                                  setState(() => _scope = _EventsScope.today);
                                },
                              ),
                              ChoiceChip(
                                label: const Text('Tomorrow'),
                                selected: _scope == _EventsScope.tomorrow,
                                onSelected: (selected) {
                                  if (!selected) return;
                                  setState(
                                    () => _scope = _EventsScope.tomorrow,
                                  );
                                },
                              ),
                              ChoiceChip(
                                label: const Text('All'),
                                selected: _scope == _EventsScope.all,
                                onSelected: (selected) {
                                  if (!selected) return;
                                  setState(() => _scope = _EventsScope.all);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (verticalEvents.isEmpty)
                    const SliverFillRemaining(
                      child: Center(child: Text('No events found')),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, i) {
                          final e = verticalEvents[i];
                          return _buildEventCard(e);
                        }, childCount: verticalEvents.length),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _EventsBuckets {
  final List<Event> today;
  final List<Event> tomorrow;
  final List<Event> later;
  final List<Event> undated;

  const _EventsBuckets({
    required this.today,
    required this.tomorrow,
    required this.later,
    required this.undated,
  });
}
