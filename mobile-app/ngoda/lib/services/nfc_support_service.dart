import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

abstract final class NfcSupportService {
  static const String _channelName = 'ngoda.tap.hce';

  static const String _isSupportedMethod = 'isNfcSupported';

  static const String _isEnabledMethod = 'isNfcEnabled';

  static const String _openSettingsMethod = 'openNfcSettings';

  static const MethodChannel _channel = MethodChannel(_channelName);

  static final Logger _log = Logger('NfcSupportService');

  static Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>(_isSupportedMethod) ?? false;
    } on PlatformException catch (error, stackTrace) {
      _log.warning('Unable to determine NFC support.', error, stackTrace);

      return false;
    } on MissingPluginException catch (error, stackTrace) {
      _log.warning('NFC support method is unavailable.', error, stackTrace);

      return false;
    }
  }

  static Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>(_isEnabledMethod) ?? false;
    } on PlatformException catch (error, stackTrace) {
      _log.warning(
        'Unable to determine whether NFC is enabled.',
        error,
        stackTrace,
      );

      return false;
    } on MissingPluginException catch (error, stackTrace) {
      _log.warning(
        'NFC enabled-state method is unavailable.',
        error,
        stackTrace,
      );

      return false;
    }
  }

  static Future<bool> openSettings() async {
    try {
      await _channel.invokeMethod<void>(_openSettingsMethod);

      return true;
    } on PlatformException catch (error, stackTrace) {
      _log.warning('Unable to open NFC settings.', error, stackTrace);

      return false;
    } on MissingPluginException catch (error, stackTrace) {
      _log.warning('NFC settings method is unavailable.', error, stackTrace);

      return false;
    }
  }
}
