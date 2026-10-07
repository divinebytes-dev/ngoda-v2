import 'package:ngoda/data_models/gl/gl_account_balance.dart';

class GLCategoryBucket {
  GLCategoryBucket({required List<GLAccountBalance> accounts})
    : accounts = List.unmodifiable(accounts);

  final List<GLAccountBalance> accounts;

  factory GLCategoryBucket.fromJson(dynamic json) {
    if (json is! List) {
      return GLCategoryBucket(accounts: const []);
    }

    return GLCategoryBucket(
      accounts: json
          .whereType<Map>()
          .map(
            (account) =>
                GLAccountBalance.fromJson(Map<String, dynamic>.from(account)),
          )
          .toList(),
    );
  }

  double get totalOpening {
    return accounts.fold(0.0, (total, account) => total + account.opening);
  }

  double get totalDebit {
    return accounts.fold(0.0, (total, account) => total + account.debit);
  }

  double get totalCredit {
    return accounts.fold(0.0, (total, account) => total + account.credit);
  }

  double get totalClosing {
    return accounts.fold(0.0, (total, account) => total + account.closing);
  }

  bool get isEmpty => accounts.isEmpty;
  bool get isNotEmpty => accounts.isNotEmpty;
}
