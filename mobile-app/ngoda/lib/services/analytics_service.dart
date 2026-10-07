import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:logging/logging.dart';
import 'package:ngoda/services/crashlytics_service.dart';

class AnalyticsService {
  AnalyticsService(this._crashlytics);

  final CrashlyticsService _crashlytics;

  final Logger _log = Logger('AnalyticsService');

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  FirebaseAnalyticsObserver getAnalyticsObserver() {
    return FirebaseAnalyticsObserver(analytics: _analytics);
  }

  Future<void> _execute(
    String operation,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error, stackTrace) {
      _log.warning('Analytics operation failed: $operation', error, stackTrace);

      await _crashlytics.recordError(
        error,
        stackTrace,
        reason: 'analytics_$operation',
      );
    }
  }

  Future<void> _logEvent({
    required String event,
    Map<String, Object>? parameters,
  }) async {
    await _execute('event_failed', () async {
      await _analytics.logEvent(name: event, parameters: parameters);

      _log.fine('Logged analytics event: $event');
    });
  }

  Future<void> logUserSignup({required String platform}) async {
    await _execute('signup_failed', () {
      return _analytics.logSignUp(signUpMethod: platform);
    });
  }

  Future<void> logUserRegistration({
    required Map<String, String> userData,
  }) async {
    await _logEvent(
      event: 'user_registration',
      parameters: {
        'country': userData['country'] ?? '',
        'platform': userData['platform'] ?? '',
        'source': userData['source'] ?? '',
      },
    );
  }

  Future<void> logUserLocation({required String country}) async {
    await _logEvent(event: 'user_location', parameters: {'country': country});
  }

  Future<void> logUserLogin(String platform, String userId) async {
    await _execute('login_failed', () async {
      await _analytics.logLogin(loginMethod: platform);

      await _analytics.setUserId(id: userId);
    });
  }

  Future<void> logUserScreen(String screen) async {
    await _execute('screen_view_failed', () {
      return _analytics.logScreenView(screenName: screen);
    });
  }

  Future<void> setUserCountry(String country) async {
    await _execute('user_country_failed', () {
      return _analytics.setUserProperty(name: 'country', value: country);
    });
  }

  Future<void> setUserKyc(String kyc) async {
    await _execute('user_kyc_failed', () {
      return _analytics.setUserProperty(name: 'kyc_level', value: kyc);
    });
  }

  Future<void> logUserLogout(String platform) async {
    await _logEvent(event: 'user_logout', parameters: {'platform': platform});

    await _execute('clear_user_id_failed', () {
      return _analytics.setUserId(id: null);
    });
  }

  Future<void> logTransactionStarted({
    required String transactionType,
    required Map<String, String> transactionData,
  }) async {
    await _logTransaction(
      event: 'transaction_started',
      transactionType: transactionType,
      transactionData: transactionData,
    );
  }

  Future<void> logTransactionCompleted({
    required String transactionType,
    required Map<String, String> transactionData,
  }) async {
    await _logTransaction(
      event: 'transaction_completed',
      transactionType: transactionType,
      transactionData: transactionData,
    );
  }

  Future<void> logTransactionFailed({
    required String transactionType,
    required Map<String, String> transactionData,
  }) async {
    await _logTransaction(
      event: 'transaction_failed',
      transactionType: transactionType,
      transactionData: transactionData,
    );
  }

  Future<void> _logTransaction({
    required String event,
    required String transactionType,
    required Map<String, String> transactionData,
  }) async {
    final amount = double.tryParse(transactionData['amount'] ?? '');

    await _logEvent(
      event: event,
      parameters: {
        'type': transactionType,
        'currency': transactionData['currency'] ?? '',
        if (amount != null) 'amount': amount,
      },
    );
  }

  Future<void> logCustomEvent({
    required String name,
    Map<String, Object>? parameters,
  }) async {
    await _logEvent(event: name, parameters: parameters);
  }
}
