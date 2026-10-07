import 'package:ngoda/data_models/transaction/transaction_v.dart';

abstract final class TransactionVService {
  static const int defaultTimeInSeconds = 30;

  static final Map<String, TransactionV> _versions = {};

  static bool _isInitialized = false;

  static bool get isInitialized => _isInitialized;

  static void initialize(List<TransactionV> versions) {
    _versions
      ..clear()
      ..addEntries(
        versions.map((version) => MapEntry(_normalize(version.v), version)),
      );

    _isInitialized = true;
  }

  static TransactionV? get(String version) {
    final key = _normalize(version);

    if (key.isEmpty) {
      return null;
    }

    return _versions[key];
  }

  static bool contains(String version) {
    final key = _normalize(version);

    if (key.isEmpty) {
      return false;
    }

    return _versions.containsKey(key);
  }

  static int timeInSeconds(String version) {
    return get(version)?.timeInSeconds ?? defaultTimeInSeconds;
  }

  static Duration duration(String version) {
    return Duration(seconds: timeInSeconds(version));
  }

  static List<TransactionV> get all => List.unmodifiable(_versions.values);

  static List<String> get names => List.unmodifiable(_versions.keys);

  static void clear() {
    _versions.clear();
    _isInitialized = false;
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase();
  }
}
