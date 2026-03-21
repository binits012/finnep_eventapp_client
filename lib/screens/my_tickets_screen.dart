import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/ticket.dart';
import '../services/api_client.dart';
import '../services/guest_service.dart';

class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen> {
  List<GuestTicket> _tickets = [];
  bool _loading = false;
  String? _error;
  bool _showLogin = false;
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  String _step = 'email';

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final year = DateTime.now().year;
      final list = await getTickets(year: year);
      setState(() {
        _tickets = list;
        _loading = false;
      });
    } on ApiException catch (e) {
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
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
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

  @override
  Widget build(BuildContext context) {
    if (_showLogin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('My Tickets'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/'),
          ),
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
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
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
              : _tickets.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('No tickets yet'),
                          const SizedBox(height: 16),
                          ElevatedButton(onPressed: () => context.go('/'), child: const Text('Browse events')),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _tickets.length,
                        itemBuilder: (context, i) {
                          final t = _tickets[i];
                          final date = t.eventDate != null ? DateTime.tryParse(t.eventDate!) : null;
                          final dateStr = date != null ? DateFormat.yMMMd().format(date) : t.eventDate ?? '';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              title: Text(t.eventTitle ?? 'Event'),
                              subtitle: Text(dateStr),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push('/my-tickets/${t.id}'),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
