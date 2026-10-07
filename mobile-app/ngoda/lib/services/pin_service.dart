import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

abstract final class PinService {
  static const String _version = 'v1';
  static const String _algorithm = 'pbkdf2-sha256';

  /*
   * PBKDF2 intentionally makes PIN verification expensive
   * compared with hashing the PIN once with SHA-256.
   *
   * The iteration count is stored with each hash so the
   * work factor can be increased for newly-created PINs
   * without invalidating existing hashes.
   */
  static const int _iterations = 210000;

  static const int _saltLength = 16;
  static const int _derivedKeyLength = 32;

  static final Random _secureRandom = Random.secure();

  static String hashPin(String pin) {
    final normalizedPin = _normalizePin(pin);

    if (normalizedPin.isEmpty) {
      throw ArgumentError.value(pin, 'pin', 'PIN cannot be empty.');
    }

    final salt = _generateSalt();

    final derivedKey = _deriveKey(
      pin: normalizedPin,
      salt: salt,
      iterations: _iterations,
      length: _derivedKeyLength,
    );

    return [
      _version,
      _algorithm,
      _iterations.toString(),
      base64UrlEncode(salt),
      base64UrlEncode(derivedKey),
    ].join(r'$');
  }

  static bool verifyPin(String input, String storedHash) {
    final normalizedPin = _normalizePin(input);

    final normalizedHash = storedHash.trim();

    if (normalizedPin.isEmpty || normalizedHash.isEmpty) {
      return false;
    }

    final parts = normalizedHash.split(r'$');

    /*
     * Compatibility with PINs created by the
     * previous SHA-256 implementation.
     *
     * A successful legacy verification should
     * subsequently be migrated by the caller.
     */
    if (parts.length != 5) {
      return _verifyLegacySha256(normalizedPin, normalizedHash);
    }

    try {
      final version = parts[0];
      final algorithm = parts[1];

      if (version != _version || algorithm != _algorithm) {
        return false;
      }

      final iterations = int.tryParse(parts[2]);

      if (iterations == null || iterations <= 0) {
        return false;
      }

      final salt = base64Url.decode(parts[3]);

      final expectedKey = base64Url.decode(parts[4]);

      if (salt.isEmpty || expectedKey.isEmpty) {
        return false;
      }

      final actualKey = _deriveKey(
        pin: normalizedPin,
        salt: salt,
        iterations: iterations,
        length: expectedKey.length,
      );

      return _constantTimeEquals(actualKey, expectedKey);
    } on FormatException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static bool needsRehash(String storedHash) {
    final normalizedHash = storedHash.trim();

    if (normalizedHash.isEmpty) {
      return true;
    }

    final parts = normalizedHash.split(r'$');

    /*
     * Anything outside the current structured
     * format should be upgraded after successful
     * verification.
     */
    if (parts.length != 4) {
      return true;
    }

    final version = parts[0];
    final algorithm = parts[1];

    if (version != _version || algorithm != _algorithm) {
      return true;
    }

    final iterations = int.tryParse(parts[2]);

    if (iterations == null) {
      return true;
    }

    return iterations < _iterations;
  }

  static String _normalizePin(String pin) {
    return pin.trim();
  }

  static Uint8List _generateSalt() {
    return Uint8List.fromList(
      List<int>.generate(_saltLength, (_) => _secureRandom.nextInt(256)),
    );
  }

  static Uint8List _deriveKey({
    required String pin,
    required Uint8List salt,
    required int iterations,
    required int length,
  }) {
    final password = Uint8List.fromList(utf8.encode(pin));

    final hmac = Hmac(sha256, password);

    final hashLength = sha256.convert(const <int>[]).bytes.length;

    final blockCount = (length / hashLength).ceil();

    final output = BytesBuilder(copy: false);

    for (var blockIndex = 1; blockIndex <= blockCount; blockIndex++) {
      final block = ByteData(4)..setUint32(0, blockIndex, Endian.big);

      final initialInput = Uint8List.fromList([
        ...salt,
        ...block.buffer.asUint8List(),
      ]);

      var u = Uint8List.fromList(hmac.convert(initialInput).bytes);

      final result = Uint8List.fromList(u);

      for (var iteration = 1; iteration < iterations; iteration++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);

        for (var index = 0; index < result.length; index++) {
          result[index] ^= u[index];
        }
      }

      output.add(result);
    }

    final bytes = output.takeBytes();

    return Uint8List.fromList(bytes.take(length).toList());
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }

    var difference = 0;

    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }

    return difference == 0;
  }

  static bool _verifyLegacySha256(String pin, String storedHash) {
    final digest = sha256.convert(utf8.encode(pin));

    final legacyHash = digest.toString();

    return _constantTimeEquals(
      utf8.encode(legacyHash),
      utf8.encode(storedHash),
    );
  }
}
