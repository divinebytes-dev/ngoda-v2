import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web3dart/web3dart.dart';

abstract final class WalletKeyService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _privateKeyStorageKey = 'wallet_private_key';

  static Future<void> savePrivateKey(String privateKey) async {
    final normalizedKey = _normalizePrivateKey(privateKey);

    /*
     * Validate before persisting.
     *
     * This prevents malformed key material from
     * entering secure storage and failing much
     * later during signing.
     */
    _privateKeyBytes(normalizedKey);

    await _storage.write(key: _privateKeyStorageKey, value: normalizedKey);
  }

  static Future<bool> hasPrivateKey() async {
    final value = await _storage.read(key: _privateKeyStorageKey);

    return value != null && value.trim().isNotEmpty;
  }

  static Future<void> clearPrivateKey() async {
    await _storage.delete(key: _privateKeyStorageKey);
  }

  static Future<String> signCanonicalString(String canonical) async {
    final privateKey = await _readPrivateKey();

    final privateKeyBytes = _privateKeyBytes(privateKey);

    final messageHash = _ethereumMessageHash(canonical);

    final signature = sign(messageHash, privateKeyBytes);

    final signatureBytes = Uint8List.fromList([
      ...unsignedIntToBytes(signature.r),
      ...unsignedIntToBytes(signature.s),
      signature.v,
    ]);

    return base64Encode(signatureBytes);
  }

  static String verifySignature({
    required String canonical,
    required String signature,
  }) {
    final signatureBytes = _decodeSignature(signature);

    final r = bytesToUnsignedInt(signatureBytes.sublist(0, 32));

    final s = bytesToUnsignedInt(signatureBytes.sublist(32, 64));

    final v = signatureBytes[64];

    final messageSignature = MsgSignature(r, s, v);

    try {
      final publicKey = ecRecover(
        _ethereumMessageHash(canonical),
        messageSignature,
      );

      final address = publicKeyToAddress(publicKey);

      return bytesToHex(address, include0x: true);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        const WalletKeyException(
          'INVALID_SIGNATURE',
          'Unable to recover wallet address '
              'from signature.',
        ),
        stackTrace,
      );
    }
  }

  static Future<String> getAddress() async {
    final privateKey = await _readPrivateKey();

    final privateKeyBytes = _privateKeyBytes(privateKey);

    try {
      final publicKey = privateKeyBytesToPublic(privateKeyBytes);

      final address = publicKeyToAddress(publicKey);

      return bytesToHex(address, include0x: true);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        const WalletKeyException(
          'INVALID_PRIVATE_KEY',
          'Unable to derive wallet address.',
        ),
        stackTrace,
      );
    }
  }

  static Future<String> _readPrivateKey() async {
    final value = await _storage.read(key: _privateKeyStorageKey);

    if (value == null || value.trim().isEmpty) {
      throw const WalletKeyException(
        'PRIVATE_KEY_NOT_FOUND',
        'Wallet private key was not found.',
      );
    }

    return _normalizePrivateKey(value);
  }

  static Uint8List _privateKeyBytes(String privateKey) {
    final normalized = _normalizePrivateKey(privateKey);

    /*
     * A secp256k1 private key is exactly
     * 32 bytes = 64 hexadecimal characters.
     */
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(normalized)) {
      throw const WalletKeyException(
        'INVALID_PRIVATE_KEY',
        'Wallet private key must be a '
            '32-byte hexadecimal value.',
      );
    }

    final bytes = hexToBytes(normalized);

    if (bytes.length != 32) {
      throw const WalletKeyException(
        'INVALID_PRIVATE_KEY',
        'Wallet private key must be 32 bytes.',
      );
    }

    /*
     * Let the Ethereum/secp256k1 implementation
     * perform the final scalar validity check when
     * deriving/signing with the key.
     */
    return bytes;
  }

  static Uint8List _ethereumMessageHash(String canonical) {
    /*
     * Ethereum personal-sign prefix:
     *
     * "\x19Ethereum Signed Message:\n"
     * + UTF-8 byte length
     * + message bytes
     *
     * Use UTF-8 byte length rather than Dart
     * String.length. String.length counts UTF-16
     * code units and is incorrect for non-ASCII
     * canonical values.
     */
    final messageBytes = utf8.encode(canonical);

    return keccakUtf8(
      '\u0019Ethereum Signed Message:\n'
      '${messageBytes.length}'
      '$canonical',
    );
  }

  static Uint8List _decodeSignature(String signature) {
    final normalized = signature.trim();

    if (normalized.isEmpty) {
      throw const WalletKeyException(
        'INVALID_SIGNATURE',
        'Signature cannot be empty.',
      );
    }

    late final Uint8List bytes;

    try {
      bytes = Uint8List.fromList(base64Decode(normalized));
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        const WalletKeyException(
          'INVALID_SIGNATURE',
          'Signature is not valid Base64.',
        ),
        stackTrace,
      );
    }

    if (bytes.length != 65) {
      throw WalletKeyException(
        'INVALID_SIGNATURE',
        'Signature must be 65 bytes; '
            'received ${bytes.length}.',
      );
    }

    return bytes;
  }

  static String _normalizePrivateKey(String value) {
    var normalized = value.trim();

    if (normalized.startsWith('0x') || normalized.startsWith('0X')) {
      normalized = normalized.substring(2);
    }

    return normalized;
  }
}

class WalletKeyException implements Exception {
  const WalletKeyException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() {
    return 'WalletKeyException'
        '($code): $message';
  }
}
