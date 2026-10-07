import 'package:ngoda/data_models/payment/max_tap_payment_amount.dart';

class MaxTapPaymentAmountList {
  MaxTapPaymentAmountList({required Map<String, MaxTapPaymentAmount> data})
    : data = Map.unmodifiable(
        data.map(
          (currency, amount) => MapEntry(currency.trim().toLowerCase(), amount),
        ),
      );

  final Map<String, MaxTapPaymentAmount> data;

  factory MaxTapPaymentAmountList.fromJson(List<dynamic> json) {
    final data = <String, MaxTapPaymentAmount>{};

    for (final item in json) {
      if (item is! Map) {
        continue;
      }

      final amount = MaxTapPaymentAmount.fromJson(
        Map<String, dynamic>.from(item),
      );

      if (amount.currencyCode.isEmpty) {
        continue;
      }

      data[amount.currencyCode] = amount;
    }

    return MaxTapPaymentAmountList(data: data);
  }

  factory MaxTapPaymentAmountList.empty() {
    return MaxTapPaymentAmountList(data: const {});
  }

  MaxTapPaymentAmount? operator [](String currency) {
    return getByCurrency(currency);
  }

  MaxTapPaymentAmount? getByCurrency(String currency) {
    return data[currency.trim().toLowerCase()];
  }

  bool containsCurrency(String currency) {
    return data.containsKey(currency.trim().toLowerCase());
  }

  bool isActive(String currency) {
    return getByCurrency(currency)?.isActive ?? false;
  }

  List<String> get currencies {
    return List.unmodifiable(data.keys);
  }

  bool get isEmpty => data.isEmpty;

  bool get isNotEmpty => data.isNotEmpty;
}
