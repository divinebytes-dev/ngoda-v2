import 'dart:io';

import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

class PermissionHandlerService {
  final Logger _log = Logger('PermissionHandlerService');

  Future<bool> requestGalleryPermission() async {
    if (!Platform.isAndroid) {
      return true;
    }

    try {
      final photos = await permissions.Permission.photos.status;

      if (photos.isGranted || photos.isLimited) {
        return true;
      }

      final result = await permissions.Permission.photos.request();

      if (result.isGranted || result.isLimited) {
        return true;
      }

      final storage = await permissions.Permission.storage.status;

      if (storage.isGranted) {
        return true;
      }

      final storageResult = await permissions.Permission.storage.request();

      return storageResult.isGranted;
    } catch (error, stackTrace) {
      _log.warning('Unable to request gallery permission.', error, stackTrace);

      return false;
    }
  }

  Future<bool> isGalleryPermissionGranted() async {
    if (!Platform.isAndroid) {
      return true;
    }

    try {
      final photos = await permissions.Permission.photos.status;

      if (photos.isGranted || photos.isLimited) {
        return true;
      }

      final storage = await permissions.Permission.storage.status;

      return storage.isGranted;
    } catch (error, stackTrace) {
      _log.warning(
        'Unable to determine gallery permission status.',
        error,
        stackTrace,
      );

      return false;
    }
  }

  Future<bool> openSettings() async {
    try {
      return await permissions.openAppSettings();
    } catch (error, stackTrace) {
      _log.warning('Unable to open application settings.', error, stackTrace);

      return false;
    }
  }
}
