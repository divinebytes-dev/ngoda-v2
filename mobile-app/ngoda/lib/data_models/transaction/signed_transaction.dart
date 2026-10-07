import 'package:ngoda/data_models/transaction/sender_approval.dart';
import 'package:ngoda/data_models/transaction/transaction_data.dart';

class SignedTransaction {
  const SignedTransaction({
    required this.transactionData,
    required this.senderApproval,
  });

  final TransactionData transactionData;
  final SenderApproval senderApproval;

  factory SignedTransaction.fromJson(Map<String, dynamic> json) {
    return SignedTransaction(
      transactionData: TransactionData.fromJson(_asMap(json['transaction'])),
      senderApproval: SenderApproval.fromJson(_asMap(json['sender_approval'])),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transaction': transactionData.toJson(),
      'sender_approval': senderApproval.toJson(),
    };
  }

  bool get hasMatchingReference {
    return transactionData.reference == senderApproval.reference;
  }

  bool get hasMatchingCurrency {
    return transactionData.currencyCode == senderApproval.currencyCode;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
