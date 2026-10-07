import 'package:ngoda/data_models/gl/gl_category_bucket.dart';

class GLCurrencyBalance {
  const GLCurrencyBalance({
    required this.asset,
    required this.liability,
    required this.equity,
    required this.revenue,
    required this.expense,
  });

  final GLCategoryBucket asset;
  final GLCategoryBucket liability;
  final GLCategoryBucket equity;
  final GLCategoryBucket revenue;
  final GLCategoryBucket expense;

  factory GLCurrencyBalance.fromJson(Map<String, dynamic> json) {
    return GLCurrencyBalance(
      asset: GLCategoryBucket.fromJson(json['asset']),
      liability: GLCategoryBucket.fromJson(json['liability']),
      equity: GLCategoryBucket.fromJson(json['equity']),
      revenue: GLCategoryBucket.fromJson(json['revenue']),
      expense: GLCategoryBucket.fromJson(json['expense']),
    );
  }

  double get totalDebit =>
      asset.totalDebit +
      liability.totalDebit +
      equity.totalDebit +
      revenue.totalDebit +
      expense.totalDebit;

  double get totalCredit =>
      asset.totalCredit +
      liability.totalCredit +
      equity.totalCredit +
      revenue.totalCredit +
      expense.totalCredit;

  bool get balanced => (totalDebit - totalCredit).abs() <= 0.000001;
}
