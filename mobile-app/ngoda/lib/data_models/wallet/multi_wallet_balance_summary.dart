import 'package:ngoda/data_models/wallet/wallet_balance_summary.dart';

class MultiWalletBalanceSummary {
  const MultiWalletBalanceSummary({
    required this.merchantWallet,
    required this.customerWallet,
    required this.agentWallet,
    this._commissionWallet,
  });

  final WalletBalanceSummary merchantWallet;

  final WalletBalanceSummary customerWallet;

  final WalletBalanceSummary agentWallet;

  final WalletBalanceSummary? _commissionWallet;

  WalletBalanceSummary get commissionWallet =>
      _commissionWallet ?? WalletBalanceSummary.empty();

  factory MultiWalletBalanceSummary.fromJson(Map<String, dynamic> json) {
    return MultiWalletBalanceSummary(
      merchantWallet: _parseWallet(json['merchantWallet']),
      customerWallet: _parseWallet(json['customerWallet']),
      agentWallet: _parseWallet(json['agentWallet']),
      commissionWallet: _parseWallet(json['commissionWallet']),
    );
  }

  static WalletBalanceSummary _parseWallet(dynamic value) {
    if (value is Map) {
      return WalletBalanceSummary.fromJson(Map<String, dynamic>.from(value));
    }

    return WalletBalanceSummary.empty();
  }
}

// import 'package:ngoda/data_models/wallet/wallet_balance_summary.dart';

// class MultiWalletBalanceSummary {
//   const MultiWalletBalanceSummary({
//     required this.merchantWallet,
//     required this.customerWallet,
//     required this.agentWallet,
//   });

//   final WalletBalanceSummary merchantWallet;

//   final WalletBalanceSummary customerWallet;

//   final WalletBalanceSummary agentWallet;

//   factory MultiWalletBalanceSummary.fromJson(Map<String, dynamic> json) {
//     return MultiWalletBalanceSummary(
//       merchantWallet: _parseWallet(json['merchantWallet']),
//       customerWallet: _parseWallet(json['customerWallet']),
//       agentWallet: _parseWallet(json['agentWallet']),
//     );
//   }

//   static WalletBalanceSummary _parseWallet(dynamic value) {
//     if (value is Map) {
//       return WalletBalanceSummary.fromJson(Map<String, dynamic>.from(value));
//     }

//     return WalletBalanceSummary.empty();
//   }
// }
