import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:ngoda/ui/screens/agent/providers/agent_dashboard_provider.dart';
import 'package:ngoda/ui/screens/auth/providers/supported_countries_provider.dart';
import 'package:ngoda/ui/screens/customer/provider/customer_dashboard_provider.dart';
import 'package:ngoda/ui/screens/finance/providers/finance_dashboard_provider.dart';
import 'package:ngoda/ui/screens/merchant/provider/merchant_dashboard_provider.dart';
import 'package:ngoda/ui/screens/vendor/provider/vendor_dashboard_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ngoda/core/providers/app_lifecycle_service_provider.dart';
import 'package:ngoda/core/providers/crashlytics_service_provider.dart';
import 'package:ngoda/core/providers/hive_service_provider.dart';
import 'package:ngoda/core/providers/idle_service_provider.dart';
import 'package:ngoda/core/providers/nfc_supported_provider.dart';
import 'package:ngoda/ngoda_app.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/hive_service.dart';
import 'package:ngoda/services/nfc_router_service.dart';
import 'package:ngoda/services/nfc_support_service.dart';
import 'package:ngoda/services/notification_listener_service.dart';
import 'package:ngoda/services/notification_service.dart';

class AppInitializer extends ConsumerStatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const AppInitializer({super.key, required this.navigatorKey});

  @override
  ConsumerState<AppInitializer> createState() {
    return _AppInitializerState();
  }
}

class _AppInitializerState extends ConsumerState<AppInitializer> {
  final Logger _log = Logger('AppInitializer');

  bool _authenticatedServicesInitialized = false;

  bool _nfcDialogShowing = false;

  late final NotificationService _notificationService;

  late final NotificationListenerService _notificationListenerService;

  late final IdleService _idleService;

  // late final AuthNotifier _authNotifier;

  late final StreamSubscription<Map<String, dynamic>> _notificationSubscription;

  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();

    _idleService = ref.read(idleServiceProvider);

    /*
     * Reading the lifecycle provider creates
     * and starts the lifecycle service.
     *
     * The provider owns its disposal.
     */
    ref.read(appLifecycleServiceProvider(widget.navigatorKey));

    // _authNotifier = ref.read(authProvider.notifier);

    /*
     * Warm the supported-country provider.
     */
    ref.read(supportedCountriesProvider);

    _notificationService = NotificationService(
      supabase: Supabase.instance.client,
    );

    _notificationListenerService = NotificationListenerService(
      supabase: Supabase.instance.client,
      notificationService: _notificationService,
      onWalletChanged: _refreshDashboard,
    );

    _notificationSubscription = _notificationService.notificationStream.listen(
      _onNotification,
    );

    _initializeAuthentication();

    Future.microtask(_initializeCrashlytics);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeNfc();
    });
  }

  Future<void> _initializeCrashlytics() async {
    if (!mounted) {
      return;
    }

    final crashlyticsService = ref.read(crashlyticsServiceProvider);

    await crashlyticsService.initialize();
  }

  Future<void> _initializeNfc() async {
    if (!mounted) {
      return;
    }

    /*
     * NFCRouterService handles incoming NFC/HCE
     * events through TapReaderService.
     */
    NFCRouterService.initialize(
      ProviderScope.containerOf(context),
      widget.navigatorKey,
    );

    /*
     * Device NFC capability is a separate concern
     * and belongs to NfcSupportService.
     */
    await _checkNfcAvailability();
  }

  Future<void> _checkNfcAvailability() async {
    /*
     * The current HCE implementation is Android
     * specific.
     */
    if (!Platform.isAndroid) {
      _setNfcSupported(false);

      return;
    }

    final hiveService = ref.read(hiveServiceProvider);

    /*
     * NFC support is a device capability.
     *
     * Once determined it can be cached because
     * the device does not gain or lose NFC
     * hardware between launches.
     */
    final checkedResult = hiveService.getItem<bool>(
      HiveBoxName.nfcSupport,
      'nfcSupportChecked',
    );

    final supportedResult = hiveService.getItem<bool>(
      HiveBoxName.nfcSupport,
      'nfcSupported',
    );

    final hasCachedCapability =
        checkedResult.result == true && supportedResult.result != null;

    late final bool supported;

    if (hasCachedCapability) {
      supported = supportedResult.result ?? false;
    } else {
      supported = await NfcSupportService.isSupported();

      await hiveService.saveItem<bool>(
        HiveBoxName.nfcSupport,
        'nfcSupportChecked',
        true,
      );

      await hiveService.saveItem<bool>(
        HiveBoxName.nfcSupport,
        'nfcSupported',
        supported,
      );
    }

    if (!mounted) {
      return;
    }

    _setNfcSupported(supported);

    if (!supported) {
      /*
       * Only show the unsupported-device message
       * the first time capability is checked.
       *
       * The cached provider value still allows
       * NFC screens/features to remain disabled
       * on subsequent launches.
       */
      if (!hasCachedCapability) {
        await _showNfcUnsupportedDialog();
      }

      return;
    }

    /*
     * Enabled state is deliberately NOT cached.
     *
     * Unlike hardware support, the user can turn
     * NFC on or off in Android settings at any
     * time, so check the current state.
     */
    final enabled = await NfcSupportService.isEnabled();

    if (!mounted || enabled) {
      return;
    }

    await _showNfcDisabledDialog();
  }

  void _setNfcSupported(bool supported) {
    ref.read(nfcSupportedProvider.notifier).setSupported(supported);
  }

  Future<void> _showNfcUnsupportedDialog() async {
    if (_nfcDialogShowing) {
      return;
    }

    final context = widget.navigatorKey.currentContext;

    if (context == null || !context.mounted) {
      return;
    }

    _nfcDialogShowing = true;

    try {
      await DialogService.error(
        context,
        message:
            'This phone does not support NFC. '
            'Tap payments are unavailable on this device.',
      );
    } finally {
      _nfcDialogShowing = false;
    }
  }

  Future<void> _showNfcDisabledDialog() async {
    if (_nfcDialogShowing) {
      return;
    }

    final context = widget.navigatorKey.currentContext;

    if (context == null || !context.mounted) {
      return;
    }

    _nfcDialogShowing = true;

    try {
      final openSettings = await DialogService.confirm(
        context,
        title: 'Enable NFC',
        message:
            'NFC is supported on this phone, '
            'but it is currently turned off. '
            'Enable NFC to use tap payments.',
        confirmText: 'Open Settings',
        cancelText: 'Not Now',
      );

      if (openSettings != true) {
        return;
      }

      final opened = await NfcSupportService.openSettings();

      if (!opened) {
        _log.warning('Unable to open NFC settings.');
      }
    } finally {
      _nfcDialogShowing = false;
    }
  }

  Future<void> _onNotification(Map<String, dynamic> notification) async {
    final context = widget.navigatorKey.currentContext;

    if (context == null || !context.mounted) {
      return;
    }

    await DialogService.success(
      context,
      title: notification['title']?.toString() ?? 'Notification',
      message: notification['body']?.toString() ?? '',
    );
  }

  void _initializeAuthentication() {
    _log.info('Initialising authentication');

    // _authNotifier.initialize();

    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      _onAuthStateChanged,
    );
  }

  Future<void> _onAuthStateChanged(AuthState data) async {
    final session = data.session;

    _log.info('AUTH EVENT: ${data.event}');

    /*
     * PASSWORD RECOVERY
     *
     * Supabase has processed the recovery link
     * and established a recovery session.
     *
     * Handle this before normal authenticated
     * session initialization.
     */
    if (data.event == AuthChangeEvent.passwordRecovery && session != null) {
      _log.info('Password recovery session established');

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        final context = widget.navigatorKey.currentContext;

        if (context == null || !context.mounted) {
          return;
        }

        context.go('/new-password');
      });

      return;
    }

    if (session != null) {
      await _startAuthenticatedServices();

      return;
    }

    _stopAuthenticatedServices();
  }

  Future<void> _startAuthenticatedServices() async {
    if (_authenticatedServicesInitialized) {
      return;
    }

    _authenticatedServicesInitialized = true;

    _log.info('Initialising authenticated services');

    try {
      await _notificationService.initialize();

      await _notificationService.startAuthenticatedServices(ref);

      if (!mounted) {
        return;
      }

      _notificationListenerService.start();

      _idleService.start();
    } catch (error, stackTrace) {
      /*
       * Initialization did not complete.
       *
       * Reset the guard so a later authenticated
       * session event can retry.
       */
      _authenticatedServicesInitialized = false;

      _log.warning(
        'Unable to initialise authenticated services.',
        error,
        stackTrace,
      );
    }
  }

  void _stopAuthenticatedServices() {
    _authenticatedServicesInitialized = false;

    _notificationListenerService.stop();

    _idleService.stop();
  }

  void _refreshDashboard() {
    if (!mounted) {
      return;
    }

    final role = Supabase.instance.client.auth.currentUser?.appMetadata['role']
        ?.toString();

    _log.info('Refreshing dashboard for $role');

    switch (role) {
      case 'customer':
        ref.invalidate(customerDashboardProvider);
        break;

      case 'agent':
        ref.invalidate(agentDashboardProvider);
        break;

      case 'merchant':
        ref.invalidate(merchantDashboardProvider);
        break;

      case 'finance':
        ref.invalidate(financeDashboardProvider);
        break;

      case 'vendor':
        ref.invalidate(vendorDashboardProvider);
        break;
    }
  }

  @override
  void dispose() {
    _notificationListenerService.stop();

    _notificationSubscription.cancel();

    _authSubscription?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const NgodaApp();
  }
}
