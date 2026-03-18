import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'app_router.dart';
import 'config/app_theme.dart';
import 'models/checkout_payload.dart';
import 'services/payment_service.dart';
import 'theme_scope.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  late final AppLinks _appLinks;
  bool _handlingPaytrailLink = false;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();

    // Cold start: handle Paytrail return link, or clear pending payload so hot restart doesn't reopen flow
    _appLinks.getInitialLink().then((uri) async {
      if (uri != null &&
          uri.scheme == 'okazzo' &&
          uri.host == 'paytrail-return') {
        await _handleIncomingUri(uri, source: 'initial');
      } else {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.containsKey('pendingPaytrailCheckoutPayload')) {
          await prefs.remove('pendingPaytrailCheckoutPayload');
          debugPrint('[DeepLink] Cleared pendingPaytrailCheckoutPayload (no paytrail-return link).');
        }
      }
    }).catchError((e) {
      debugPrint('[DeepLink] getInitialLink error: $e');
    });

    // Warm start / foreground
    _appLinks.uriLinkStream.listen((uri) {
      _handleIncomingUri(uri, source: 'stream');
    }, onError: (e) {
      debugPrint('[DeepLink] uriLinkStream error: $e');
    });
  }

  Future<void> _handleIncomingUri(Uri uri, {required String source}) async {
    debugPrint('[DeepLink][$source] uri=$uri');
    if (uri.scheme != 'okazzo') return;
    if (uri.host != 'paytrail-return') return;

    final stamp = uri.queryParameters['stamp'] ?? '';
    final transactionId = uri.queryParameters['transactionId'] ?? '';
    final status = (uri.queryParameters['status'] ?? 'ok').toLowerCase();
    debugPrint('[DeepLink][paytrail-return] status=$status stamp=$stamp transactionId=$transactionId');

    if (status == 'cancel') {
      // User cancelled or Paytrail returned cancel; keep user in app (no auto success).
      return;
    }
    if (stamp.isEmpty || transactionId.isEmpty) {
      debugPrint('[DeepLink][paytrail-return] Missing stamp/transactionId, cannot verify.');
      return;
    }
    if (_handlingPaytrailLink) return;

    _handlingPaytrailLink = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final payloadJson = prefs.getString('pendingPaytrailCheckoutPayload');
      if (payloadJson == null || payloadJson.isEmpty) {
        debugPrint('[DeepLink][paytrail-return] No pendingPaytrailCheckoutPayload in storage.');
        return;
      }
      final payload = CheckoutPayload.fromJson(jsonDecode(payloadJson) as Map<String, dynamic>);
      debugPrint('[DeepLink][paytrail-return] Restored payload: $payload');

      final fullName = (payload.fullName ?? '').trim();
      final checkoutData = <String, dynamic>{
        'status': status,
        'eventId': payload.eventId,
        'merchantId': payload.merchantId,
        'externalMerchantId': payload.externalMerchantId,
        'email': payload.email,
        'fullName': fullName,
        'customerName': fullName.isNotEmpty
            ? fullName
            : (payload.email.contains('@') ? payload.email.split('@').first : payload.email),
        'quantity': payload.quantity,
        'ticketTypeId': payload.ticketId.isEmpty ? null : payload.ticketId,
        'ticketName': payload.ticketName,
        'eventName': payload.eventName,
        'sessionId': payload.sessionId,
        'seats': payload.placeIds,
        'placeIds': payload.placeIds,
        'seatTickets': payload.seatTickets,
        'amount': payload.totalCents,
        'currency': payload.currency.toUpperCase(),
        'basePrice': payload.price,
        'serviceFee': payload.serviceFee,
        'vatRate': payload.vat,
        'serviceTax': payload.serviceTax,
        'orderFee': payload.orderFee,
        'country': payload.country,
      };

      debugPrint('[DeepLink][paytrail-return] Verifying Paytrail payment…');
      final result = await verifyPaytrailPayment(
        stamp: stamp,
        transactionId: transactionId,
        checkoutData: checkoutData,
      );
      debugPrint('[DeepLink][paytrail-return] Verified OK, navigating to /success');

      final extra = <String, dynamic>{
        ...result,
        '_clientCurrency': payload.currency,
        '_clientTotalAmountOverride': payload.totalAmountOverride,
        '_clientTotalCents': payload.totalCents,
        '_clientTicketName': payload.ticketName,
        '_clientPlaceIds': payload.placeIds,
        '_clientEmail': payload.email,
      };
      appRouter.go('/success', extra: extra);
      // Clear so hot restart / next launch doesn't treat as pending Paytrail return
      await prefs.remove('pendingPaytrailCheckoutPayload');
    } catch (e) {
      debugPrint('[DeepLink][paytrail-return] Verify failed: $e');
    } finally {
      _handlingPaytrailLink = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      themeMode: _themeMode,
      toggleTheme: _toggleTheme,
      child: MaterialApp.router(
        title: 'Okazzo',
        theme: appThemeLight,
        darkTheme: appThemeDark,
        themeMode: _themeMode,
        routerConfig: appRouter,
      ),
    );
  }
}
