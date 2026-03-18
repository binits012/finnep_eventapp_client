import 'package:go_router/go_router.dart';

import 'models/checkout_payload.dart';
import 'screens/checkout_screen.dart';
import 'screens/event_detail_screen.dart';
import 'screens/events_screen.dart';
import 'screens/home_screen.dart';
import 'screens/my_ticket_detail_screen.dart';
import 'screens/my_tickets_screen.dart';
import 'screens/seat_selection_screen.dart';
import 'screens/success_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/events', builder: (_, __) => const EventsScreen()),
    GoRoute(
      path: '/events/:id',
      builder: (_, state) {
        final id = state.pathParameters['id']!;
        return EventDetailScreen(eventId: id);
      },
    ),
    GoRoute(
      path: '/events/:id/seats',
      builder: (_, state) {
        final id = state.pathParameters['id']!;
        return SeatSelectionScreen(eventId: id);
      },
    ),
    GoRoute(
      path: '/checkout',
      builder: (_, state) {
        final data = state.extra as CheckoutPayload?;
        return CheckoutScreen(payload: data);
      },
    ),
    GoRoute(
      path: '/success',
      builder: (_, state) {
        final data = state.extra as Map<String, dynamic>?;
        return SuccessScreen(ticketData: data);
      },
    ),
    GoRoute(path: '/my-tickets', builder: (_, __) => const MyTicketsScreen()),
    GoRoute(
      path: '/my-tickets/:id',
      builder: (_, state) {
        final id = state.pathParameters['id']!;
        return MyTicketDetailScreen(ticketId: id);
      },
    ),
  ],
);
