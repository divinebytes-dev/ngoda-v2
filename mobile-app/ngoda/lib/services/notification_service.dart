import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:ngoda/core/providers/deep_link_service_provider.dart';
import 'package:ngoda/core/providers/hive_service_provider.dart';
import 'package:ngoda/services/hive_service.dart';
import 'package:ngoda/services/user_presence_service.dart';
import 'package:ngoda/services/wallet_key_service.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/screens/customer/services/customer_api_service_provider.dart';
import 'package:ngoda/ui/screens/finance/providers/transactions_config_provider.dart';
import 'package:ngoda/ui/screens/finance/providers/transactions_v_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/max_tap_payment_amount_provider.dart';
// import 'package:ngoda/ui/screens/customer/services/customer_api_service_provider.dart';
// import 'package:ngoda/ui/screens/finance/provider/transactions_config_provider.dart';
// import 'package:ngoda/ui/screens/finance/provider/transactions_v_provider.dart';
// import 'package:ngoda/ui/screens/wallet/transactions/provider/max_tap_payment_amount_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  NotificationService({required this._supabase});

  final SupabaseClient _supabase;

  static const String _notificationChannelId = 'wallet_notifications';

  static const String _notificationChannelName = 'Wallet Notifications';

  static const String _notificationChannelDescription =
      'Realtime wallet alerts';

  static const String _notificationGroupKey = 'ngoda_wallet_notifications';

  static const int _summaryNotificationId = 0;

  static const String _referralCodeKey = 'referralCode';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final StreamController<Map<String, dynamic>> _notificationStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  final Logger _log = Logger('NotificationService');

  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;

  bool _initialized = false;

  bool get isInitialized => _initialized;

  Stream<Map<String, dynamic>> get notificationStream =>
      _notificationStreamController.stream;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    await _initializeLocalNotifications();
    await _setupFirebaseMessaging();

    _initialized = true;
  }

  Future<void> startAuthenticatedServices(WidgetRef ref) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      _log.warning(
        'Authenticated services cannot start '
        'without an authenticated user.',
      );

      return;
    }

    /*
     * Presence and notification token registration
     * belong to the authenticated application
     * lifecycle.
     */
    await UserPresenceService.start();

    await _registerCurrentDeviceToken();

    /*
     * Only notifications that have never been
     * delivered should produce a new local
     * notification on startup.
     *
     * Unread-but-already-delivered notifications
     * remain unread in the database/UI, but should
     * not be shown again every time the app starts.
     */
    await showPendingNotifications();

    /*
     * These calls currently bootstrap authenticated
     * wallet/application state.
     *
     * They are retained here to preserve existing
     * behavior. Once the application/session
     * bootstrap service is reviewed, these should
     * move out of NotificationService.
     */
    await _initializeWalletState(ref);

    await _initializeReferralCode(ref);

    await _initializeDeepLinks(ref);
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const iosSettings = DarwinInitializationSettings();

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _handleLocalNotificationResponse,
    );

    _log.fine('Local notifications initialized.');
  }

  Future<void> _handleLocalNotificationResponse(
    NotificationResponse response,
  ) async {
    final notificationId = response.payload?.trim();

    if (notificationId == null || notificationId.isEmpty) {
      return;
    }

    try {
      await markAsRead(notificationId);

      final notification = await fetchNotification(notificationId);

      if (!_notificationStreamController.isClosed) {
        _notificationStreamController.add(notification);
      }
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to process local notification tap.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _setupFirebaseMessaging() async {
    final messaging = FirebaseMessaging.instance;

    try {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      _log.fine(
        'Firebase Messaging authorization status: '
        '${settings.authorizationStatus}',
      );
    } catch (error, stackTrace) {
      _log.warning(
        'Unable to request notification permission.',
        error,
        stackTrace,
      );
    }

    await _messageOpenedSubscription?.cancel();

    _messageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) {
        unawaited(_handleRemoteNotificationOpen(message));
      },
      onError: (Object error, StackTrace stackTrace) {
        _log.warning(
          'Firebase Messaging open stream failed.',
          error,
          stackTrace,
        );
      },
    );

    try {
      final initialMessage = await messaging.getInitialMessage();

      if (initialMessage != null) {
        await _handleRemoteNotificationOpen(initialMessage);
      }
    } catch (error, stackTrace) {
      _log.warning(
        'Unable to read initial Firebase message.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _handleRemoteNotificationOpen(RemoteMessage message) async {
    final notificationId = message.data['notification_id']?.toString().trim();

    if (notificationId == null || notificationId.isEmpty) {
      return;
    }

    try {
      await markAsRead(notificationId);

      final notification = await fetchNotification(notificationId);

      if (!_notificationStreamController.isClosed) {
        _notificationStreamController.add(notification);
      }
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to process remote notification open.',
        error,
        stackTrace,
      );
    }
  }

  Future<Map<String, dynamic>> fetchNotification(String notificationId) async {
    final response = await _supabase
        .from('notifications')
        .select()
        .eq('id', notificationId)
        .single();

    return Map<String, dynamic>.from(response);
  }

  Future<void> showLocalNotification({
    required String id,
    required String title,
    required String body,
  }) async {
    final normalizedId = id.trim();
    final normalizedTitle = title.trim();
    final normalizedBody = body.trim();

    if (normalizedId.isEmpty ||
        normalizedTitle.isEmpty ||
        normalizedBody.isEmpty) {
      _log.warning(
        'Local notification ignored because '
        'required data is missing.',
      );

      return;
    }

    const androidDetails = AndroidNotificationDetails(
      _notificationChannelId,
      _notificationChannelName,
      channelDescription: _notificationChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      groupKey: _notificationGroupKey,
      autoCancel: true,
    );

    const details = NotificationDetails(android: androidDetails);

    /*
     * Do not use seconds-since-epoch as the ID.
     * Two notifications arriving in the same
     * second could overwrite each other.
     *
     * Reserve 0 for the Android group summary.
     */
    final localNotificationId = _notificationIdFor(normalizedId);

    await _localNotifications.show(
      id: localNotificationId,
      title: normalizedTitle,
      body: normalizedBody,
      notificationDetails: details,
      payload: normalizedId,
    );

    await _showUnreadSummary();
  }

  int _notificationIdFor(String notificationId) {
    /*
     * Flutter local notifications requires an
     * integer ID.
     *
     * Derive a stable positive 31-bit value from
     * the backend notification ID. This prevents
     * duplicate delivery of the same backend
     * notification from creating another local
     * notification.
     */
    final value = notificationId.hashCode & 0x7fffffff;

    return value == _summaryNotificationId ? 1 : value;
  }

  Future<void> _showUnreadSummary() async {
    final count = await unreadCount();

    if (count <= 0) {
      await _localNotifications.cancel(id: _summaryNotificationId);

      return;
    }

    final summaryAndroidDetails = AndroidNotificationDetails(
      _notificationChannelId,
      _notificationChannelName,
      channelDescription: _notificationChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      groupKey: _notificationGroupKey,
      setAsGroupSummary: true,
      styleInformation: InboxStyleInformation(
        const <String>[],
        contentTitle:
            '$count new ${count == 1 ? 'notification' : 'notifications'}',
        summaryText: 'Ngoda',
      ),
    );

    final summaryDetails = NotificationDetails(android: summaryAndroidDetails);

    await _localNotifications.show(
      id: _summaryNotificationId,
      title: 'Ngoda',
      body: '$count unread ${count == 1 ? 'notification' : 'notifications'}',
      notificationDetails: summaryDetails,
    );
  }

  Future<void> showPendingNotifications() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      return;
    }

    try {
      final response = await _supabase
          .from('notifications')
          .select()
          .eq('user_id', user.id)
          .eq('is_delivered', false)
          .order('created_at', ascending: true);

      final notifications = List<Map<String, dynamic>>.from(response);

      _log.fine(
        'Pending notifications: '
        '${notifications.length}',
      );

      for (final notification in notifications) {
        final id = notification['id']?.toString().trim();

        final title = notification['title']?.toString().trim();

        final body = notification['body']?.toString().trim();

        if (id == null ||
            id.isEmpty ||
            title == null ||
            title.isEmpty ||
            body == null ||
            body.isEmpty) {
          _log.warning('Skipping malformed pending notification.');

          continue;
        }

        try {
          await showLocalNotification(id: id, title: title, body: body);

          await markAsDelivered(id);
        } catch (error, stackTrace) {
          /*
           * One malformed/unavailable notification
           * should not prevent the remaining queue
           * from being processed.
           */
          _log.warning(
            'Failed to deliver pending '
            'notification $id.',
            error,
            stackTrace,
          );
        }
      }
    } catch (error, stackTrace) {
      _log.warning('Unable to load pending notifications.', error, stackTrace);
    }
  }

  Future<void> markAsDelivered(String notificationId) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      return;
    }

    await _supabase
        .from('notifications')
        .update({
          'is_delivered': true,
          'delivered_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', notificationId)
        .eq('user_id', user.id);
  }

  Future<void> markAsRead(String notificationId) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      return;
    }

    try {
      await _supabase
          .from('notifications')
          .update({
            'is_read': true,
            'is_delivered': true,
            'read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', notificationId)
          .eq('user_id', user.id);

      await _showUnreadSummary();
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to mark notification '
        '$notificationId as read.',
        error,
        stackTrace,
      );
    }
  }

  Future<int> unreadCount() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      return 0;
    }

    try {
      final response = await _supabase
          .from('notifications')
          .select('id')
          .eq('user_id', user.id)
          .eq('is_read', false);

      return response.length;
    } catch (error, stackTrace) {
      _log.warning(
        'Unable to retrieve unread '
        'notification count.',
        error,
        stackTrace,
      );

      return 0;
    }
  }

  Future<void> _registerCurrentDeviceToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();

      await saveDeviceToken(token);
    } catch (error, stackTrace) {
      _log.warning(
        'Unable to retrieve Firebase '
        'Messaging token.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> saveDeviceToken(String? token) async {
    final user = _supabase.auth.currentUser;

    final normalizedToken = token?.trim();

    if (user == null || normalizedToken == null || normalizedToken.isEmpty) {
      return;
    }

    final platform = switch (Platform.operatingSystem) {
      'android' => 'android',
      'ios' => 'ios',
      _ => Platform.operatingSystem,
    };

    await _supabase.from('device_tokens').upsert({
      'country_code': user.appMetadata['country_code'],
      'user_id': user.id,
      'token': normalizedToken,
      'platform': platform,
    }, onConflict: 'token');
  }

  Future<void> _initializeWalletState(WidgetRef ref) async {
    /*
     * Trigger configuration providers now so
     * transaction configuration is available to
     * the authenticated wallet flow.
     */
    ref.read(transactionsConfigProvider);

    ref.read(transactionVProvider);

    ref.read(maxTapPaymentAmountProvider);

    try {
      final hasKey = await WalletKeyService.hasPrivateKey();

      if (hasKey) {
        return;
      }

      final api = ref.read(customerApiServiceProvider);

      final userKey = await api.getUserKey();

      if (userKey.isEmpty) {
        return;
      }

      await WalletKeyService.savePrivateKey(userKey);
    } catch (error, stackTrace) {
      /*
       * Do not log the key or other wallet-secret
       * values.
       */
      _log.warning('Unable to initialize wallet key.', error, stackTrace);
    }
  }

  Future<void> _initializeReferralCode(WidgetRef ref) async {
    final hive = ref.read(hiveServiceProvider);

    final cached = hive.getItem<String>(
      HiveBoxName.referralCode,
      _referralCodeKey,
    );

    if (cached.result?.trim().isNotEmpty == true) {
      return;
    }

    try {
      final api = ref.read(customerApiServiceProvider);

      final referralCode = (await api.getReferralCode()).trim();

      if (referralCode.isEmpty) {
        return;
      }

      await hive.saveItem<String>(
        HiveBoxName.referralCode,
        _referralCodeKey,
        referralCode,
      );
    } catch (error, stackTrace) {
      _log.warning('Unable to initialize referral code.', error, stackTrace);
    }
  }

  Future<void> _initializeDeepLinks(WidgetRef ref) async {
    try {
      final deepLinks = ref.read(deepLinkServiceProvider);

      final auth = ref.read(authProvider.notifier);

      final initialUri = await deepLinks.getInitialLink();

      if (initialUri != null) {
        final code = deepLinks.extractReferralCode(initialUri);

        if (code != null) {
          auth.setUplinerCode(code);
        }
      }

      await deepLinks.initialize(
        onLinkReceived: (uri) async {
          final code = deepLinks.extractReferralCode(uri);

          if (code != null) {
            auth.setUplinerCode(code);
          }
        },
      );
    } catch (error, stackTrace) {
      _log.warning('Deep-link initialization failed.', error, stackTrace);
    }
  }

  Future<void> dispose() async {
    await _messageOpenedSubscription?.cancel();

    _messageOpenedSubscription = null;

    if (!_notificationStreamController.isClosed) {
      await _notificationStreamController.close();
    }

    _initialized = false;
  }
}
