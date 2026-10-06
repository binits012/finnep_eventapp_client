import 'package:go_router/go_router.dart';

import 'models/checkout_payload.dart';
import 'navigation/adaptive_navigation.dart';
import 'screens/checkout_screen.dart';
import 'screens/event_detail_screen.dart';
import 'screens/events_screen.dart';
import 'screens/home_screen.dart';
import 'screens/my_ticket_detail_screen.dart';
import 'screens/my_tickets_screen.dart';
import 'screens/seat_selection_screen.dart';
import 'screens/success_screen.dart';
import 'screens/third_parties_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (_, state) => adaptivePage(
        key: state.pageKey,
        child: const HomeScreen(),
      ),
    ),
    GoRoute(
      path: '/events',
      pageBuilder: (_, state) => adaptivePage(
        key: state.pageKey,
        child: const EventsScreen(),
      ),
    ),
    GoRoute(
      path: '/events/:id',
      pageBuilder: (_, state) {
        final id = state.pathParameters['id']!;
        return adaptivePage(
          key: state.pageKey,
          child: EventDetailScreen(eventId: id),
        );
      },
    ),
    GoRoute(
      path: '/events/:id/seats',
      pageBuilder: (_, state) {
        final id = state.pathParameters['id']!;
        return adaptivePage(
          key: state.pageKey,
          child: SeatSelectionScreen(eventId: id),
        );
      },
    ),
    GoRoute(
      path: '/checkout',
      pageBuilder: (_, state) {
        final data = state.extra as CheckoutPayload?;
        return adaptivePage(
          key: state.pageKey,
          child: CheckoutScreen(payload: data),
        );
      },
    ),
    GoRoute(
      path: '/success',
      pageBuilder: (_, state) {
        final data = state.extra as Map<String, dynamic>?;
        return adaptivePage(
          key: state.pageKey,
          child: SuccessScreen(ticketData: data),
        );
      },
    ),
    GoRoute(
      path: '/third-parties',
      pageBuilder: (_, state) => adaptivePage(
        key: state.pageKey,
        child: const ThirdPartiesScreen(),
      ),
    ),
    GoRoute(
      path: '/my-tickets',
      pageBuilder: (_, state) => adaptivePage(
        key: state.pageKey,
        child: const MyTicketsScreen(),
      ),
    ),
    GoRoute(
      path: '/my-tickets/:id',
      pageBuilder: (_, state) {
        final id = state.pathParameters['id']!;
        return adaptivePage(
          key: state.pageKey,
          child: MyTicketDetailScreen(ticketId: id),
        );
      },
    ),
  ],
);
