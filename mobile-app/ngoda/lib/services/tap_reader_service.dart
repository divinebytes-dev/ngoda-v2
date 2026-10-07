import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

abstract final class TapReaderService {
  static const MethodChannel _methodChannel = MethodChannel('ngoda.tap.hce');

  static const EventChannel _eventChannel = EventChannel('ngoda.tap.events');

  static final Logger _log = Logger('TapReaderService');

  static Stream<Map<String, dynamic>>? _stream;

  static Stream<Map<String, dynamic>> get stream {
    return _stream ??= _createEventStream();
  }

  static Stream<Map<String, dynamic>> _createEventStream() {
    if (!Platform.isAndroid) {
      return const Stream<Map<String, dynamic>>.empty();
    }

    return _eventChannel
        .receiveBroadcastStream()
        .transform(
          StreamTransformer<dynamic, Map<String, dynamic>>.fromHandlers(
            handleData: (event, sink) {
              if (event is! String) {
                _log.warning(
                  'Ignoring NFC event with '
                  'unsupported payload type: '
                  '${event.runtimeType}',
                );

                return;
              }

              final payload = _decodePayload(event);

              if (payload != null) {
                sink.add(payload);
              }
            },
            handleError: (Object error, StackTrace stackTrace, sink) {
              _log.warning('NFC event stream error.', error, stackTrace);
            },
          ),
        )
        .asBroadcastStream();
  }

  static Map<String, dynamic>? _decodePayload(String raw) {
    final value = raw.trim();

    if (value.isEmpty) {
      _log.fine('Ignoring empty NFC payload.');

      return null;
    }

    try {
      final decoded = jsonDecode(value);

      if (decoded is! Map<String, dynamic>) {
        if (decoded is Map) {
          try {
            return Map<String, dynamic>.from(decoded);
          } catch (error, stackTrace) {
            _log.warning(
              'NFC payload contains invalid '
              'JSON object keys.',
              error,
              stackTrace,
            );

            return null;
          }
        }

        _log.warning(
          'Ignoring NFC payload because '
          'the JSON root is not an object.',
        );

        return null;
      }

      return decoded;
    } on FormatException catch (error, stackTrace) {
      _log.warning('Unable to decode NFC payload.', error, stackTrace);

      return null;
    } catch (error, stackTrace) {
      _log.warning('Unexpected NFC payload decode error.', error, stackTrace);

      return null;
    }
  }

  static Future<Map<String, dynamic>?> getPayload() async {
    if (!Platform.isAndroid) {
      return null;
    }

    try {
      final raw = await _methodChannel.invokeMethod<String>('getPayload');

      if (raw == null) {
        return null;
      }

      return _decodePayload(raw);
    } on MissingPluginException catch (error, stackTrace) {
      _log.warning('NFC payload retrieval is unavailable.', error, stackTrace);

      return null;
    } on PlatformException catch (error, stackTrace) {
      _log.warning(
        'Unable to retrieve NFC payload. '
        'Code: ${error.code}',
        error,
        stackTrace,
      );

      return null;
    } catch (error, stackTrace) {
      _log.warning(
        'Unexpected NFC payload retrieval error.',
        error,
        stackTrace,
      );

      return null;
    }
  }

  static Future<void> setPayload(Map<String, dynamic> payload) async {
    if (!Platform.isAndroid) {
      return;
    }

    if (payload.isEmpty) {
      throw const FormatException('NFC payload cannot be empty.');
    }

    final encoded = jsonEncode(payload);

    try {
      final success = await _methodChannel.invokeMethod<bool>('setPayload', {
        'payload': encoded,
      });

      if (success != true) {
        throw PlatformException(
          code: 'NFC_PAYLOAD_NOT_SET',
          message:
              'Android did not confirm '
              'the NFC payload.',
        );
      }

      _log.fine(
        'NFC payload prepared '
        '(${encoded.length} characters).',
      );
    } on PlatformException catch (error, stackTrace) {
      _log.warning(
        'Unable to set NFC payload. '
        'Code: ${error.code}',
        error,
        stackTrace,
      );

      rethrow;
    } on MissingPluginException catch (error, stackTrace) {
      _log.warning(
        'NFC payload configuration '
        'is unavailable.',
        error,
        stackTrace,
      );

      rethrow;
    } catch (error, stackTrace) {
      _log.warning('Unexpected NFC set-payload error.', error, stackTrace);

      rethrow;
    }
  }

  static Future<void> clearPayload() async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      final success = await _methodChannel.invokeMethod<bool>('clearPayload');

      if (success != true) {
        throw PlatformException(
          code: 'NFC_PAYLOAD_NOT_CLEARED',
          message:
              'Android did not confirm '
              'that the NFC payload was cleared.',
        );
      }

      _log.fine('NFC payload cleared.');
    } on PlatformException catch (error, stackTrace) {
      _log.warning(
        'Unable to clear NFC payload. '
        'Code: ${error.code}',
        error,
        stackTrace,
      );

      rethrow;
    } on MissingPluginException catch (error, stackTrace) {
      _log.warning(
        'NFC payload clearing '
        'is unavailable.',
        error,
        stackTrace,
      );

      rethrow;
    } catch (error, stackTrace) {
      _log.warning('Unexpected NFC clear-payload error.', error, stackTrace);

      rethrow;
    }
  }
}
