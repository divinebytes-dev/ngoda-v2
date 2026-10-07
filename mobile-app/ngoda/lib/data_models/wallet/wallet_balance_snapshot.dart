import 'package:ngoda/data_models/wallet/wallet_periodic_balance.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class WalletBalanceSnapshot {
  WalletBalanceSnapshot({
    required this.currencyCode,
    required this.fiscalYear,
    required List<WalletBalancePeriod> periods,
  }) : periods = List.unmodifiable(periods);

  final String currencyCode;

  final int fiscalYear;

  final List<WalletBalancePeriod> periods;

  factory WalletBalanceSnapshot.fromJson(Map<String, dynamic> json) {
    final rawData = json['wallet_balance_snapshot'];

    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : json;

    return WalletBalanceSnapshot(
      currencyCode:
          data['currency_code']?.toString().trim().toLowerCase() ?? '',
      fiscalYear: NumberConversionService.toInt(
        data['fiscalYear'] ?? data['fiscal_year'],
      ),
      periods: _parsePeriods(data['periods']),
    );
  }

  bool get isEmpty => periods.isEmpty;

  bool get isNotEmpty => periods.isNotEmpty;

  static List<WalletBalancePeriod> _parsePeriods(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (period) =>
              WalletBalancePeriod.fromJson(Map<String, dynamic>.from(period)),
        )
        .toList();
  }
}
