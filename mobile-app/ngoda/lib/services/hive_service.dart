import 'dart:async';

import 'package:hive/hive.dart';
import 'package:logging/logging.dart';
import 'package:ngoda/data_models/core/result.dart';

import 'package:path_provider/path_provider.dart';

class HiveService {
  final Logger _log = Logger('HiveService');

  static Future<void>? _initializationFuture;

  bool get isInitialized {
    return _initializationFuture != null;
  }

  Future<void> init() {
    return _initializationFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      _log.fine('Initializing Hive.');

      final directory = await getApplicationDocumentsDirectory();

      Hive.init(directory.path);

      await Future.wait([
        _openBox<bool>(HiveBoxName.themeSettings),
        _openBox<String>(HiveBoxName.auth),
        _openBox<String>(HiveBoxName.referralCode),
        _openBox<bool>(HiveBoxName.nfcSupport),
        _openBox<String>(HiveBoxName.lastLoginIdentifier),
      ]);

      _log.fine('Hive initialized successfully.');
    } catch (error, stackTrace) {
      /*
       * Allow initialization to be retried if
       * startup failed.
       */
      _initializationFuture = null;

      _log.severe('Failed to initialize Hive.', error, stackTrace);

      rethrow;
    }
  }

  Future<Box<T>> _openBox<T>(String name) async {
    if (Hive.isBoxOpen(name)) {
      return Hive.box<T>(name);
    }

    return Hive.openBox<T>(name);
  }

  Box<T> _box<T>(String name) {
    if (_initializationFuture == null) {
      throw StateError(
        'HiveService has not been initialized. '
        'Call init() before accessing Hive boxes.',
      );
    }

    if (!Hive.isBoxOpen(name)) {
      throw StateError('Hive box "$name" is not open.');
    }

    return Hive.box<T>(name);
  }

  Future<R<bool>> saveItem<T>(String boxName, String key, T item) async {
    try {
      await _box<T>(boxName).put(key, item);

      return const R(result: true);
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to save item '
        '[$boxName][$key].',
        error,
        stackTrace,
      );

      return R(error: error.toString());
    }
  }

  Future<R<bool>> saveAt<T>(String boxName, int index, T item) async {
    try {
      await _box<T>(boxName).put(index, item);

      return const R(result: true);
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to save item at index '
        '[$boxName][$index].',
        error,
        stackTrace,
      );

      return R(error: error.toString());
    }
  }

  R<T?> getItem<T>(String boxName, String key) {
    try {
      final value = _box<T>(boxName).get(key);

      return R(result: value);
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to get item '
        '[$boxName][$key].',
        error,
        stackTrace,
      );

      return R(error: error.toString());
    }
  }

  R<T?> getAt<T>(String boxName, int index) {
    try {
      final value = _box<T>(boxName).getAt(index);

      return R(result: value);
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to get item at index '
        '[$boxName][$index].',
        error,
        stackTrace,
      );

      return R(error: error.toString());
    }
  }

  R<List<T>> getAll<T>(String boxName) {
    try {
      final values = _box<T>(boxName).values.toList(growable: false);

      return R(result: values);
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to get all items '
        '[$boxName].',
        error,
        stackTrace,
      );

      return R(error: error.toString());
    }
  }

  Future<R<bool>> deleteItem<T>(String boxName, String key) async {
    try {
      await _box<T>(boxName).delete(key);

      return const R(result: true);
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to delete item '
        '[$boxName][$key].',
        error,
        stackTrace,
      );

      return R(error: error.toString());
    }
  }

  Future<R<bool>> deleteAt<T>(String boxName, int index) async {
    try {
      await _box<T>(boxName).deleteAt(index);

      return const R(result: true);
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to delete item at index '
        '[$boxName][$index].',
        error,
        stackTrace,
      );

      return R(error: error.toString());
    }
  }
}

abstract final class HiveBoxName {
  static const String themeSettings = 'themeSettings';

  static const String auth = 'auth';

  static const String referralCode = 'referralCode';

  static const String nfcSupport = 'nfcSupportChecked';
  static const String lastLoginIdentifier = 'lastLoginIdentifier';
}
