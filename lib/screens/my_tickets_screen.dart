import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/ticket.dart';
import '../navigation/adaptive_navigation.dart';
import '../services/api_client.dart';
import '../services/guest_service.dart';
import '../services/guest_token_store.dart';
import '../widgets/legal_overflow_menu_button.dart';

enum _TicketPeriod { all, upcoming, past }

class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen> {
  List<GuestTicket> _tickets = [];
  bool _loading = true;
  String? _error;
  bool _showLogin = false;
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _searchController = TextEditingController();
  String _step = 'email';

  _TicketPeriod _period = _TicketPeriod.all;
  bool _sortNewestFirst = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  static int _eventDateMillis(GuestTicket t) {
    final d = _parseEventDate(t);
    if (d != null) return d.millisecondsSinceEpoch;
    return 0;
  }

  /// Earliest plausible instant for this ticket's event (for ordering / upcoming).
  static DateTime? _parseEventDate(GuestTicket t) {
    if (t.eventDate == null || t.eventDate!.trim().isEmpty) return null;
    return DateTime.tryParse(t.eventDate!.trim());
  }

  static DateTime? _parseEventEnd(GuestTicket t) {
    final raw = t.raw;
    final eventMap = raw?['event'];
    if (eventMap is Map<String, dynamic>) {
      final end = eventMap['eventEndDate'] ?? eventMap['event_end_date'];
      if (end is String && end.trim().isNotEmpty) return DateTime.tryParse(end.trim());
    }
    return _parseEventDate(t);
  }

  static DateTime _startOfLocalDay(DateTime d) {
    return DateTime(d.year, d.month, d.day);
  }

  static bool _matchesPeriod(GuestTicket t, _TicketPeriod p) {
    if (p == _TicketPeriod.all) return true;
    final now = DateTime.now();
    final startToday = _startOfLocalDay(now);
    final start = _parseEventDate(t);
    if (p == _TicketPeriod.upcoming) {
      if (start == null) return false;
      final localStart = start.toLocal();
      return !localStart.isBefore(startToday);
    }
    if (p == _TicketPeriod.past) {
      final end = _parseEventEnd(t);
      if (end != null) {
        final localEnd = end.toLocal();
        return localEnd.isBefore(now);
      }
      if (start == null) return false;
      final localStart = start.toLocal();
      return localStart.isBefore(startToday);
    }
    return true;
  }

  static bool _matchesSearch(GuestTicket t, String q) {
    if (q.isEmpty) return true;
    final title = (t.eventTitle ?? '').toLowerCase();
    final venue = (t.venue ?? '').toLowerCase();
    return title.contains(q) || venue.contains(q);
  }

  List<GuestTicket> get _filteredSorted {
    final q = _searchController.text.trim().toLowerCase();
    final filtered =
        _tickets.where((t) => _matchesSearch(t, q) && _matchesPeriod(t, _period)).toList();
    filtered.sort((a, b) {
      final cmp = _eventDateMillis(a).compareTo(_eventDateMillis(b));
      return _sortNewestFirst ? -cmp : cmp;
    });
    return filtered;
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _showLogin = false;
    });

    try {
      final token = await GuestTokenStore.get();
      if (token == null || token.trim().isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _showLogin = true;
        });
        return;
      }

      final now = DateTime.now();
      final years = <int>{
        now.year - 1,
        now.year,
        now.year + 1,
      };

      final merged = <String, GuestTicket>{};
      ApiException? unauthorized;
      Object? firstNonAuthError;

      for (final y in years) {
        try {
          final batch = await getTickets(year: y);
          for (final t in batch) {
            if (t.id.isEmpty) continue;
            merged[t.id] = t;
          }
        } on ApiException catch (e) {
          if (e.statusCode == 401) {
            unauthorized ??= e;
            break;
          } else {
            firstNonAuthError ??= e;
          }
        } catch (e) {
          firstNonAuthError ??= e;
        }
      }

      if (!mounted) return;

      if (merged.isEmpty && unauthorized != null) {
        setState(() {
          _loading = false;
          _showLogin = true;
        });
        return;
      }
      if (merged.isEmpty && firstNonAuthError != null) {
        throw firstNonAuthError;
      }

      final list = merged.values.toList()
        ..sort((a, b) => _eventDateMillis(a).compareTo(_eventDateMillis(b)));

      setState(() {
        _tickets = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) {
        setState(() {
          _loading = false;
          _showLogin = true;
        });
      } else {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    // Let the push animation finish before network / prefs work.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) return;
    setState(() => _error = null);
    try {
      await sendCode(email);
      setState(() {
        _step = 'code';
      });
      _codeController.clear();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    setState(() => _error = null);
    try {
      await verifyCode(_emailController.text.trim(), code);
      setState(() {
        _showLogin = false;
        _step = 'email';
      });
      _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Widget _periodChip(String label, _TicketPeriod value) {
    final selected = _period == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _period = value),
    );
  }

  Widget _ticketListBody(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredSorted;

    if (_tickets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'No tickets yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => context.go('/'), child: const Text('Browse events')),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search by event or venue',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
              labelStyle: const TextStyle(textBaseline: TextBaseline.alphabetic),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _periodChip('All', _TicketPeriod.all),
              _periodChip('Upcoming', _TicketPeriod.upcoming),
              _periodChip('Past', _TicketPeriod.past),
              const SizedBox(width: 4),
              ActionChip(
                avatar: Icon(
                  _sortNewestFirst ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 18,
                ),
                label: Text(_sortNewestFirst ? 'Newest first' : 'Oldest first'),
                onPressed: () => setState(() => _sortNewestFirst = !_sortNewestFirst),
              ),
            ],
          ),
        ),
        if (filtered.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.filter_alt_off, size: 48, color: theme.colorScheme.outline),
                    const SizedBox(height: 12),
                    Text(
                      'No tickets match your filters',
                      style: theme.textTheme.titleSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _period = _TicketPeriod.all;
                          _searchController.clear();
                        });
                      },
                      child: const Text('Clear filters'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final t = filtered[i];
                  final date = _parseEventDate(t);
                  final local = date?.toLocal();
                  final dateStr = local != null
                      ? '${DateFormat.yMMMd().format(local)} · ${DateFormat.jm().format(local)}'
                      : (t.eventDate ?? '');
                  final venue = (t.venue ?? '').trim();
                  final sub = venue.isEmpty ? dateStr : '$dateStr · $venue';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text(t.eventTitle ?? 'Event'),
                      subtitle: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/my-tickets/${t.id}'),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showLogin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('My Tickets'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => popOrGoHome(context),
          ),
          actions: const [LegalOverflowMenuButton()],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: _step == 'email'
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Enter your email to view tickets'),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      controller: _emailController,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      enableSuggestions: false,
                      autocorrect: false,
                    ),
                    if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: _sendCode, child: const Text('Send code')),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Enter the code sent to your email'),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('my_tickets_code_input'),
                      decoration: const InputDecoration(labelText: 'Code', hintText: 'Numbers only'),
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: _verifyCode, child: const Text('Verify')),
                  ],
                ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tickets'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => popOrGoHome(context)),
        actions: const [LegalOverflowMenuButton()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _ticketListBody(context),
    );
  }
}
