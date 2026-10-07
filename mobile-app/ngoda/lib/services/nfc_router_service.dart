import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:ngoda/data_models/transaction/transaction_data.dart';
import 'package:ngoda/services/tap_reader_service.dart';

// import 'package:ngoda/ui/screens/wallet/transactions/provider/tap_payment_provider.dart';

abstract final class NFCRouterService {
  static const String _paymentRoute = '/customer-cash/make-nfc-payment';

  static final Logger _log = Logger('NFCRouterService');

  static ProviderContainer? _container;

  static GlobalKey<NavigatorState>? _navigatorKey;

  static StreamSubscription<Map<String, dynamic>>? _subscription;

  /*
   * Prevents two NFC payloads from being parsed
   * at exactly the same time.
   *
   * This lock covers payload handling only.
   * It must not remain locked while the payment
   * screen is open.
   */
  static bool _isHandlingPayload = false;

  /*
   * Prevents more than one NFC payment route
   * from being pushed at the same time.
   */
  static bool _isPaymentScreenOpen = false;

  /*
   * Reference currently associated with the
   * active/pending physical NFC tap.
   *
   * Android/native EventChannel delivery can
   * send the same payload more than once while
   * the devices are still touching.
   */
  static String? _lastPaymentReference;

  /*
   * Payment waiting for navigation.
   *
   * This can happen when:
   *
   * - the application is paused/inactive
   * - the navigator is not mounted yet
   * - another NFC payment screen is open
   */
  static TransactionData? _pendingPayment;

  static bool get isInitialized {
    return _container != null && _navigatorKey != null;
  }

  static bool get isPaymentScreenOpen {
    return _isPaymentScreenOpen;
  }

  static bool get hasPendingPayment {
    return _pendingPayment != null;
  }

  static void initialize(
    ProviderContainer container,
    GlobalKey<NavigatorState> navigatorKey,
  ) {
    _container = container;
    _navigatorKey = navigatorKey;

    _startListening();

    /*
     * Android may already have delivered an NFC
     * intent before Flutter attached the stream
     * listener.
     */
    unawaited(_readCurrentPayload());
  }

  static Future<void> restart(
    ProviderContainer container,
    GlobalKey<NavigatorState> navigatorKey,
  ) async {
    _container = container;
    _navigatorKey = navigatorKey;

    /*
     * Recreate only the native event listener.
     *
     * Do not clear pending payment state because
     * the application may have been resumed by
     * the NFC transaction itself.
     */
    await _subscription?.cancel();

    _subscription = null;
    _isHandlingPayload = false;

    _startListening();

    /*
     * Check whether Android delivered an intent
     * before the new EventChannel subscription
     * became active.
     */
    await _readCurrentPayload();

    /*
     * A payment may already have been captured
     * while the application was inactive.
     */
    await _openPendingPayment();
  }

  static void _startListening() {
    if (_subscription != null) {
      return;
    }

    _subscription = TapReaderService.stream.listen(
      (payload) {
        unawaited(_handlePayload(payload));
      },
      onError: (Object error, StackTrace stackTrace) {
        _log.warning('NFC event stream failed.', error, stackTrace);
      },
      onDone: () {
        /*
         * Allow initialize() or restart() to
         * establish a new subscription later.
         */
        _subscription = null;
      },
      cancelOnError: false,
    );
  }

  static Future<void> _readCurrentPayload() async {
    try {
      final payload = await TapReaderService.getPayload();

      if (payload == null || payload.isEmpty) {
        return;
      }

      await _handlePayload(payload);
    } catch (error, stackTrace) {
      _log.warning('Unable to read current NFC payload.', error, stackTrace);
    }
  }

  static Future<void> _handlePayload(Map<String, dynamic> payload) async {
    if (_isHandlingPayload) {
      _log.fine(
        'Ignoring NFC payload while another '
        'payload is being handled.',
      );

      return;
    }

    final container = _container;

    if (container == null) {
      _log.warning(
        'NFC payload received before '
        'NFCRouterService was initialized.',
      );

      return;
    }

    _isHandlingPayload = true;

    try {
      final payment = TransactionData.fromJson(payload);

      /*
       * Prefer the parsed transaction reference.
       *
       * Fall back to the raw payload only if the
       * transaction model does not expose one.
       */
      final reference =
          _normalizeReference(payment.r) ?? _extractReference(payload);

      /*
       * The native side may deliver the same
       * physical tap through both the event
       * stream and getPayload().
       *
       * Ignore it while that transaction is
       * already pending or displayed.
       */
      if (_isDuplicateActivePayment(reference)) {
        _log.fine(
          'Ignoring duplicate NFC payment '
          'reference: $reference',
        );

        return;
      }

      _lastPaymentReference = reference;

      /*
       * Publish the newest transaction before
       * attempting navigation so the destination
       * screen can read it immediately.
       */
      // container
      //     .read(
      //       tapPaymentProvider.notifier,
      //     )
      //     .state = payment;

      /*
       * Keep the transaction pending until route
       * navigation has actually succeeded.
       */
      _pendingPayment = payment;

      await _openPendingPayment();
    } catch (error, stackTrace) {
      _log.warning('Invalid NFC payment payload.', error, stackTrace);
    } finally {
      _isHandlingPayload = false;
    }
  }

  static bool _isDuplicateActivePayment(String? reference) {
    if (reference == null) {
      return false;
    }

    return reference == _lastPaymentReference &&
        (_isPaymentScreenOpen || _pendingPayment != null);
  }

  static Future<void> _openPendingPayment() async {
    final payment = _pendingPayment;

    if (payment == null) {
      return;
    }

    /*
     * Keep the new payment pending while another
     * NFC payment screen is active.
     */
    if (_isPaymentScreenOpen) {
      return;
    }

    /*
     * Navigation should only occur when Flutter
     * is fully resumed.
     *
     * AppLifecycleService can call
     * retryPendingPayment() after resume.
     */
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      _log.fine(
        'NFC payment remains pending because '
        'the application is not resumed.',
      );

      return;
    }

    final navigatorState = _navigatorKey?.currentState;

    /*
     * Do not create a repeating post-frame
     * callback here.
     *
     * If the navigator is not ready, retain the
     * payment and let startup/lifecycle code call
     * retryPendingPayment().
     */
    if (navigatorState == null || !navigatorState.mounted) {
      _log.fine(
        'NFC payment remains pending because '
        'the navigator is not ready.',
      );

      return;
    }

    final context = navigatorState.context;

    /*
     * We are committed to opening this payment.
     *
     * Remove it from the pending slot before
     * navigation so a second tap can become the
     * next pending transaction.
     */
    _pendingPayment = null;
    _isPaymentScreenOpen = true;

    var navigationSucceeded = false;

    try {
      await context.push(_paymentRoute, extra: payment);

      navigationSucceeded = true;
    } catch (error, stackTrace) {
      _log.warning('Unable to open NFC payment screen.', error, stackTrace);

      /*
       * Navigation failed, so restore this
       * transaction unless another NFC event has
       * already occupied the pending slot.
       */
      _pendingPayment ??= payment;
    } finally {
      _isPaymentScreenOpen = false;

      /*
       * Once a route has completed normally, the
       * physical tap has finished and the same
       * reference may be used by a genuine future
       * tap.
       *
       * On failed navigation, retain the reference
       * while the transaction remains pending so
       * duplicate native delivery is still ignored.
       */
      if (navigationSucceeded) {
        _lastPaymentReference = null;
      }

      /*
       * Another payment may have arrived while the
       * current payment screen was open.
       *
       * Process it once after the current route
       * closes. This is deliberately not a
       * frame-by-frame retry loop.
       */
      if (_pendingPayment != null) {
        await _openPendingPayment();
      }
    }
  }

  static Future<void> retryPendingPayment() async {
    if (_pendingPayment == null) {
      return;
    }

    await _openPendingPayment();
  }

  static String? _extractReference(Map<String, dynamic> payload) {
    final reference =
        payload['r'] ??
        payload['reference'] ??
        payload['transaction_reference'];

    return _normalizeReference(reference);
  }

  static String? _normalizeReference(Object? reference) {
    final value = reference?.toString().trim();

    if (value == null || value.isEmpty) {
      return null;
    }

    return value;
  }

  static void clearCurrentTap() {
    _pendingPayment = null;
    _lastPaymentReference = null;
    _isHandlingPayload = false;

    final container = _container;

    if (container != null) {
      // container.read(tapPaymentProvider.notifier).state = null;
    }
  }

  static Future<void> dispose() async {
    await _subscription?.cancel();

    _subscription = null;

    final container = _container;

    if (container != null) {
      // container.read(tapPaymentProvider.notifier).state = null;
    }

    _container = null;
    _navigatorKey = null;

    _pendingPayment = null;
    _lastPaymentReference = null;

    _isHandlingPayload = false;
    _isPaymentScreenOpen = false;
  }
}
