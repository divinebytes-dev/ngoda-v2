import 'package:ngoda/data_models/fee/cash_transfer_fee_configuration.dart';

class TransferFeePaymentQuote {
  final double feeAmount;
  final String currencyCode;
  final double feeAmountUsd;
  final int pointsRequired;
  final int availablePoints;
  final bool canPayWithPoints;

  const TransferFeePaymentQuote({
    required this.feeAmount,
    required this.currencyCode,
    required this.feeAmountUsd,
    required this.pointsRequired,
    required this.availablePoints,
    required this.canPayWithPoints,
  });

  int get pointsShortfall {
    final shortfall = pointsRequired - availablePoints;

    return shortfall > 0 ? shortfall : 0;
  }
}

class TransferFeePointsCalculator {
  final CashTransferFeeConfiguration configuration;

  const TransferFeePointsCalculator({required this.configuration});

  static const int _usdMicros = 1000000;

  TransferFeePaymentQuote calculate({
    required double feeAmount,
    required String currencyCode,
    required int availablePoints,
  }) {
    final currency = currencyCode.trim().toLowerCase();

    if (currency.isEmpty || currency == 'gold') {
      throw ArgumentError.value(
        currencyCode,
        'currencyCode',
        'Only fiat currencies are supported',
      );
    }

    if (!feeAmount.isFinite || feeAmount <= 0) {
      throw ArgumentError.value(
        feeAmount,
        'feeAmount',
        'Fee amount must be greater than zero',
      );
    }

    final currencyConfiguration = configuration.currency(currency);

    if (!currencyConfiguration.pointsPaymentAvailable ||
        currencyConfiguration.pointsPerUsd == null) {
      throw StateError('TRANSFER_FEE_POINT_REDEMPTION_NOT_AVAILABLE');
    }

    final rawFeeAmountUsd = currency == 'usd'
        ? feeAmount
        : feeAmount / currencyConfiguration.rateToUsd;

    final feeAmountUsdMicros = (rawFeeAmountUsd * _usdMicros).round();

    if (feeAmountUsdMicros <= 0) {
      throw ArgumentError('Converted transfer fee must be greater than zero');
    }

    final pointsNumerator =
        feeAmountUsdMicros * currencyConfiguration.pointsPerUsd!;

    final pointsRequired = (pointsNumerator + _usdMicros - 1) ~/ _usdMicros;

    final safeAvailablePoints = availablePoints > 0 ? availablePoints : 0;

    final canPayWithPoints =
        configuration.loyaltyRedemptionEnabled &&
        pointsRequired > 0 &&
        safeAvailablePoints >= pointsRequired;

    return TransferFeePaymentQuote(
      feeAmount: feeAmount,
      currencyCode: currency,
      feeAmountUsd: feeAmountUsdMicros / _usdMicros,
      pointsRequired: pointsRequired,
      availablePoints: safeAvailablePoints,
      canPayWithPoints: canPayWithPoints,
    );
  }
}
