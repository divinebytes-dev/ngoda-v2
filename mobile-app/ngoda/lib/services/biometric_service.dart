import 'package:local_auth/local_auth.dart';
import 'package:logging/logging.dart';

class BiometricService {
  BiometricService._();

  static final Logger _log = Logger('BiometricService');

  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> isAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;

      final isSupported = await _auth.isDeviceSupported();

      final available = canCheck && isSupported;

      _log.fine(
        'Biometric availability: '
        'canCheck=$canCheck, '
        'isSupported=$isSupported, '
        'available=$available',
      );

      return available;
    } catch (error, stackTrace) {
      _log.warning(
        'Unable to determine biometric availability.',
        error,
        stackTrace,
      );

      return false;
    }
  }

  static Future<bool> authenticate() async {
    try {
      final available = await isAvailable();

      if (!available) {
        return false;
      }

      final authenticated = await _auth.authenticate(
        localizedReason: 'Authenticate to unlock wallet',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      _log.fine(
        'Biometric authentication result: '
        '$authenticated',
      );

      return authenticated;
    } catch (error, stackTrace) {
      _log.warning('Biometric authentication failed.', error, stackTrace);

      return false;
    }
  }
}
