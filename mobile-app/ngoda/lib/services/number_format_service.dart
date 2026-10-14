import 'package:intl/intl.dart';
import 'package:ngoda/services/currency_service.dart';

abstract final class NumberFormatService {
  static const int defaultDecimals = 2;

  static String formatUsd(dynamic value) {
    return formatAmount(value, currency: 'usd');
  }

  static String formatAmount(
    dynamic value, {
    String currency = 'usd',
    int? decimals,
  }) {
    final number = anyToDouble(value);

    final currencyCode = currency.trim().toLowerCase();

    final currencyData = CurrencyService.get(currencyCode);

    int decimalPlaces = decimals ?? currencyData?.decimals ?? defaultDecimals;

    if (currencyCode == 'gold') {
      decimalPlaces = 4;
    }

    final symbol = currencyData?.symbol ?? CurrencyService.symbol(currencyCode);

    final amount = _format(number, decimals: decimalPlaces);

    if (_requiresSymbolSpacing(currencyCode)) {
      return '$symbol $amount';
    }

    return '$symbol$amount';
  }

  static String formatNumber(dynamic value, {int decimals = defaultDecimals}) {
    return _format(anyToDouble(value), decimals: decimals);
  }

  static String formatPoints(dynamic value) {
    return _format(anyToDouble(value), decimals: 0);
  }

  static String formatBalance(dynamic value, {int decimals = defaultDecimals}) {
    final number = anyToDouble(value);

    final formatted = _format(number.abs(), decimals: decimals);

    return number >= 0 ? '$formatted DR' : '$formatted CR';
  }

  static double anyToDouble(dynamic value) {
    if (value == null) {
      return 0;
    }

    if (value is double) {
      return value;
    }

    if (value is int) {
      return value.toDouble();
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value.trim()) ?? 0;
    }

    return 0;
  }

  static String _format(double value, {required int decimals}) {
    assert(decimals >= 0, 'Decimals cannot be negative.');

    if (decimals == 0) {
      return NumberFormat('#,##0').format(value);
    }

    return NumberFormat('#,##0.${'0' * decimals}').format(value);
  }

  static bool _requiresSymbolSpacing(String currency) {
    return currency == 'zig' || currency == 'gold';
  }
}
