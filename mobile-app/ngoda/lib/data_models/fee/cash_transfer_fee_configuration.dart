import 'package:ngoda/services/number_conversion_service.dart';

class CashTransferFeeCurrencyConfiguration {
  const CashTransferFeeCurrencyConfiguration({
    required this.currencyCode,
    required this.rateToUsd,
    required this.pointsPerUsd,
    required this.pointsPaymentAvailable,
  });

  final String currencyCode;

  final double rateToUsd;

  final int? pointsPerUsd;

  final bool pointsPaymentAvailable;

  factory CashTransferFeeCurrencyConfiguration.fromJson(
    Map<String, dynamic> json,
  ) {
    final currencyCode =
        json['currency_code']?.toString().trim().toLowerCase() ?? '';

    final rateToUsd = NumberConversionService.toDouble(json['rate_to_usd']);

    if (currencyCode.isEmpty) {
      throw const FormatException('INVALID_CURRENCY_CONFIGURATION');
    }

    if (rateToUsd <= 0) {
      throw FormatException(
        'INVALID_RATE_TO_USD_'
        '${currencyCode.toUpperCase()}',
      );
    }

    return CashTransferFeeCurrencyConfiguration(
      currencyCode: currencyCode,
      rateToUsd: rateToUsd,
      pointsPerUsd: json['points_per_usd'] == null
          ? null
          : NumberConversionService.toInt(json['points_per_usd']),
      pointsPaymentAvailable: json['points_payment_available'] == true,
    );
  }
}

class CashTransferFeeConfiguration {
  CashTransferFeeConfiguration({
    required this.countryCode,
    required this.loyaltyRedemptionEnabled,
    required Map<String, CashTransferFeeCurrencyConfiguration> currencies,
  }) : currencies = Map.unmodifiable(
         currencies.map(
           (currency, configuration) =>
               MapEntry(currency.trim().toLowerCase(), configuration),
         ),
       );

  final String countryCode;

  final bool loyaltyRedemptionEnabled;

  final Map<String, CashTransferFeeCurrencyConfiguration> currencies;

  factory CashTransferFeeConfiguration.fromJson(Map<String, dynamic> json) {
    final rawRows = json['currencies'];

    if (rawRows is! List) {
      throw const FormatException('INVALID_CASH_TRANSFER_FEE_CONFIGURATION');
    }

    final rows = rawRows
        .whereType<Map>()
        .map(
          (row) => CashTransferFeeCurrencyConfiguration.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList();

    return CashTransferFeeConfiguration(
      countryCode: json['country_code']?.toString().trim().toLowerCase() ?? '',
      loyaltyRedemptionEnabled: json['loyalty_redemption_enabled'] == true,
      currencies: {for (final row in rows) row.currencyCode: row},
    );
  }

  CashTransferFeeCurrencyConfiguration? getByCurrency(String currency) {
    return currencies[currency.trim().toLowerCase()];
  }

  CashTransferFeeCurrencyConfiguration currency(String currency) {
    final normalized = currency.trim().toLowerCase();

    final configuration = currencies[normalized];

    if (configuration == null) {
      throw StateError(
        'CURRENCY_CONFIGURATION_NOT_FOUND_'
        '${normalized.toUpperCase()}',
      );
    }

    return configuration;
  }

  bool containsCurrency(String currency) {
    return currencies.containsKey(currency.trim().toLowerCase());
  }

  List<String> get currencyList {
    return List.unmodifiable(currencies.keys);
  }
}
