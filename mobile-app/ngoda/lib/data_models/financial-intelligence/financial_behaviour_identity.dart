import 'package:ngoda/services/number_conversion_service.dart';
import 'package:ngoda/ui/enums/enums.dart';

class FinancialBehaviourIdentity {
  const FinancialBehaviourIdentity({
    required this.type,
    this.shopperScorePercentage = 0,
    this.saverScorePercentage = 0,
    this.investorScorePercentage = 0,
    this.borrowerScorePercentage = 0,
  });

  const FinancialBehaviourIdentity.neutral()
    : this(type: FinancialBehaviourType.neutral);

  final FinancialBehaviourType type;

  final double shopperScorePercentage;
  final double saverScorePercentage;
  final double investorScorePercentage;
  final double borrowerScorePercentage;

  /// Parses the nested behaviour identity structure.
  ///
  /// Expected score fields:
  /// shopper_score_percentage
  /// saver_score_percentage
  /// investor_score_percentage
  /// borrower_score_percentage
  factory FinancialBehaviourIdentity.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};

    return FinancialBehaviourIdentity(
      type: FinancialBehaviourType.fromJson(data['type']?.toString()),
      shopperScorePercentage: NumberConversionService.toDouble(
        data['shopper_score_percentage'],
      ),
      saverScorePercentage: NumberConversionService.toDouble(
        data['saver_score_percentage'],
      ),
      investorScorePercentage: NumberConversionService.toDouble(
        data['investor_score_percentage'],
      ),
      borrowerScorePercentage: NumberConversionService.toDouble(
        data['borrower_score_percentage'],
      ),
    );
  }

  /// Parses behaviour information returned as part of the
  /// financial summary response.
  ///
  /// Expected score fields:
  /// shopper_percentage
  /// saver_percentage
  /// investor_percentage
  /// borrower_percentage
  factory FinancialBehaviourIdentity.fromSummaryJson({
    required String? behavior,
    required Map<String, dynamic> scores,
  }) {
    return FinancialBehaviourIdentity(
      type: FinancialBehaviourType.fromJson(behavior),
      shopperScorePercentage: NumberConversionService.toDouble(
        scores['shopper_percentage'],
      ),
      saverScorePercentage: NumberConversionService.toDouble(
        scores['saver_percentage'],
      ),
      investorScorePercentage: NumberConversionService.toDouble(
        scores['investor_percentage'],
      ),
      borrowerScorePercentage: NumberConversionService.toDouble(
        scores['borrower_percentage'],
      ),
    );
  }

  bool get hasScores =>
      shopperScorePercentage != 0 ||
      saverScorePercentage != 0 ||
      investorScorePercentage != 0 ||
      borrowerScorePercentage != 0;
}

extension FinancialBehaviourIdentityX on FinancialBehaviourIdentity {
  String get title => switch (type) {
    FinancialBehaviourType.saver => 'Saver',
    FinancialBehaviourType.investor => 'Investor',
    FinancialBehaviourType.shopper => 'Shopper',
    FinancialBehaviourType.borrower => 'Borrower',
    FinancialBehaviourType.balanced => 'Balanced',
    FinancialBehaviourType.neutral => 'Neutral',
  };

  String get description => switch (type) {
    FinancialBehaviourType.saver =>
      'You are retaining more of your money for the future.',
    FinancialBehaviourType.investor =>
      'Investing is your strongest financial behaviour this year.',
    FinancialBehaviourType.shopper =>
      'Spending is your strongest financial behaviour this year.',
    FinancialBehaviourType.borrower =>
      'Loan repayment is your strongest financial behaviour this year.',
    FinancialBehaviourType.balanced =>
      'Your strongest financial behaviours are closely balanced.',
    FinancialBehaviourType.neutral =>
      'There is not enough activity to identify a clear behaviour yet.',
  };
}
