import 'package:ngoda/services/number_conversion_service.dart';

class TransactionV {
  const TransactionV({required this.v, required this.timeInSeconds});

  final String v;

  final int timeInSeconds;

  factory TransactionV.fromJson(Map<String, dynamic> json) {
    final version = json['v']?.toString().trim().toLowerCase() ?? '';

    final timeInSeconds = NumberConversionService.toNullableInt(json['time']);

    if (version.isEmpty) {
      throw const FormatException('Transaction version is required.');
    }

    if (timeInSeconds == null || timeInSeconds <= 0) {
      throw const FormatException(
        'Transaction validity time '
        'is required.',
      );
    }

    return TransactionV(v: version, timeInSeconds: timeInSeconds);
  }

  static List<TransactionV> fromList(List<dynamic> json) {
    return List.unmodifiable(
      json
          .whereType<Map>()
          .map((item) => TransactionV.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}
