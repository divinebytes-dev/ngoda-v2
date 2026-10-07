import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:ngoda/core/providers/network_connection_provider.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/refresh_user_dashboard.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class NetworkConnectionListener extends ConsumerStatefulWidget {
  final Widget child;

  const NetworkConnectionListener({super.key, required this.child});

  @override
  ConsumerState<NetworkConnectionListener> createState() {
    return _NetworkConnectionListenerState();
  }
}

class _NetworkConnectionListenerState
    extends ConsumerState<NetworkConnectionListener>
    with WidgetsBindingObserver {
  NetworkStatus? _previousStatus;

  OverlayEntry? _offlineOverlay;

  bool _isCheckingResumeConnection = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _removeOfflineMessage();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkConnectionAfterResume();
    }
  }

  Future<void> _checkConnectionAfterResume() async {
    if (_isCheckingResumeConnection) {
      return;
    }

    _isCheckingResumeConnection = true;

    try {
      final hasInternet = await InternetConnection().hasInternetAccess;

      if (!mounted) {
        return;
      }

      final status = hasInternet
          ? NetworkStatus.connected
          : NetworkStatus.disconnected;

      _handleNetworkStatus(status);
    } finally {
      _isCheckingResumeConnection = false;
    }
  }

  void _handleNetworkStatus(NetworkStatus status) {
    if (!mounted) {
      return;
    }

    final previousStatus = _previousStatus;

    _previousStatus = status;

    if (status == NetworkStatus.disconnected) {
      _showOfflineMessage();
      return;
    }

    _removeOfflineMessage();

    final connectionWasRestored =
        previousStatus == NetworkStatus.disconnected &&
        status == NetworkStatus.connected;

    if (connectionWasRestored) {
      _refreshDashboard();
    }
  }

  void _refreshDashboard() {
    debugPrint('Internet restored: invalidating dashboard provider');

    refreshUserDashboard(ref);
  }

  void _showOfflineMessage() {
    if (!mounted || _offlineOverlay != null) {
      return;
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);

    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _previousStatus != NetworkStatus.disconnected) {
          return;
        }

        _showOfflineMessage();
      });

      return;
    }

    late final OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) {
        return const _OfflineBanner();
      },
    );

    _offlineOverlay = entry;

    overlay.insert(entry);
  }

  void _removeOfflineMessage() {
    final overlay = _offlineOverlay;

    if (overlay != null && overlay.mounted) {
      overlay.remove();
    }

    _offlineOverlay = null;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<NetworkStatus>>(networkConnectionProvider, (
      previous,
      next,
    ) {
      next.whenData(_handleNetworkStatus);
    });

    return widget.child;
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Positioned(
      top: MediaQuery.paddingOf(context).top,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.padding,
            vertical: spacing.sm,
          ),
          color: colorScheme.error,
          child: SafeArea(
            top: false,
            bottom: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.wifi_off_rounded,
                  color: colorScheme.onError,
                  size: iconSize.medium,
                ),
                SizedBox(width: spacing.sm),
                Flexible(
                  child: Text(
                    'No internet connection',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.small(context).copyWith(
                      color: colorScheme.onError,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
