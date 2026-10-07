import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/transaction/transaction_data.dart';

class TapPaymentNotifier extends Notifier<TransactionData?> {
  @override
  TransactionData? build() {
    return null;
  }

  void setTransaction(TransactionData transaction) {
    state = transaction;
  }

  void clear() {
    state = null;
  }
}

final tapPaymentProvider =
    NotifierProvider<TapPaymentNotifier, TransactionData?>(
      TapPaymentNotifier.new,
    );
