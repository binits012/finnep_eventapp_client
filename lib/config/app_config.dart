import 'package:flutter_dotenv/flutter_dotenv.dart';

String get apiBaseUrl {
  return dotenv.env['API_BASE_URL'] ?? 'http://localhost:3001/front';
}

String get stripePublishableKey =>
    dotenv.env['STRIPE_PUBLISHABLE_KEY'] ?? '';
