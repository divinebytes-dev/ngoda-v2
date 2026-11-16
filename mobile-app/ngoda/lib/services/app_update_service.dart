import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:upgrader/upgrader.dart';

import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/snackbar_service.dart';

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  return AppUpdateService();
});

class AppUpdateService {
  final Logger _log = Logger('AppUpdateService');

  bool _busy = false;

  /// Manual check:
  ///   checkUpdates(context)
  ///
  /// Automatic check after login:
  ///   checkUpdates(context, silent: true)
  ///
  /// Silent checks still display the update dialog when an update exists.
  Future<void> checkUpdates(BuildContext context, {bool silent = false}) async {
    if (_busy || !context.mounted) {
      return;
    }

    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    _busy = true;

    final upgrader = Upgrader(
      checkOnResume: false,
      countryCode: const String.fromEnvironment(
        'NGODA_STORE_COUNTRY',
        defaultValue: 'ZA',
      ),
    );

    try {
      final initialized = await upgrader.initialize();

      if (!context.mounted) {
        return;
      }

      final storeVersion = upgrader.currentAppStoreVersion;
      final installedVersion = upgrader.currentInstalledVersion;
      _log.info(
        'Update check: '
        'initialized=$initialized, '
        'installedVersion=$installedVersion, '
        'storeVersion=$storeVersion, '
        'listingUrl=${upgrader.currentAppStoreListingURL}',
      );

      if (!initialized || storeVersion == null || installedVersion == null) {
        _log.warning(
          'Update check could not obtain version information. '
          'The store listing may be unavailable, or the lookup failed.',
        );

        _showError(context, silent: silent);
        return;
      }

      // if (!initialized || storeVersion == null || installedVersion == null) {
      //   _showError(context, silent: silent);
      //   return;
      // }

      if (!upgrader.isUpdateAvailable()) {
        if (!silent) {
          SnackbarService.info(
            context,
            'You are using the latest available store version.',
          );
        }

        return;
      }

      final confirmed = await DialogService.confirm(
        context,
        title: 'Update Ngoda',
        message:
            'Version $storeVersion is available. '
            'You are using $installedVersion.',
        confirmText: 'Update',
        cancelText: 'Later',
      );

      if (confirmed != true || !context.mounted) {
        return;
      }

      await upgrader.sendUserToAppStore();
    } catch (error, stackTrace) {
      _log.warning('Unable to check for app updates.', error, stackTrace);

      if (context.mounted) {
        _showError(context, silent: silent);
      }
    } finally {
      upgrader.dispose();
      _busy = false;
    }
  }

  void _showError(BuildContext context, {required bool silent}) {
    if (silent) {
      return;
    }

    SnackbarService.error(
      context,
      'Unable to check for updates. Please try again later.',
    );
  }
}

// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:logging/logging.dart';
// import 'package:ngoda/services/snackbar_service.dart';
// import 'package:ngoda/services/dialog_service.dart';
// import 'package:upgrader/upgrader.dart';

// final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
//   return AppUpdateService();
// });

// class AppUpdateService {
//   final _log = Logger('AppUpdateService');
//   bool _busy = false;

//   Future<void> checkUpdates(BuildContext context, {bool silent = false}) async {
//     if (_busy) {
//       return;
//     }
//     _busy = true;
//     final upgrader = Upgrader(
//       checkOnResume: false,
//       countryCode: const String.fromEnvironment(
//         'NGODA_STORE_COUNTRY',
//         defaultValue: 'ZW',
//       ),
//     );
//     try {
//       if (kIsWeb ||
//           (defaultTargetPlatform != TargetPlatform.android &&
//               defaultTargetPlatform != TargetPlatform.iOS)) {
//         return;
//       }
//       final initialized = await upgrader.initialize();
//       if (!context.mounted) {
//         return;
//       }
//       if (!initialized ||
//           upgrader.currentAppStoreVersion == null ||
//           upgrader.currentInstalledVersion == null) {
//         SnackbarService.error(
//           context,
//           'Unable to check for updates. Please try again later.',
//         );
//         return;
//       }
//       if (!upgrader.isUpdateAvailable()) {
//         _message(context, 'You are using the latest available store version.');
//         return;
//       }
//       final update = await DialogService.confirm(
//         context,
//         title: 'Update Ngoda',
//         message:
//             'Version ${upgrader.currentAppStoreVersion} is available. '
//             'You are using ${upgrader.currentInstalledVersion}.',
//         confirmText: 'Update',
//         cancelText: 'Later',
//       );
//       if (update == true) {
//         await upgrader.sendUserToAppStore();
//       }
//     } catch (error, stack) {
//       _log.warning('App update check failed.', error, stack);
//       if (context.mounted) {
//         SnackbarService.error(
//           context,
//           'Unable to check for updates. Please try again later.',
//         );
//       }
//     } finally {
//       upgrader.dispose();
//       _busy = false;
//     }
//   }

//   void _message(BuildContext context, String message) {
//     SnackbarService.info(context, message);
//   }
// }
