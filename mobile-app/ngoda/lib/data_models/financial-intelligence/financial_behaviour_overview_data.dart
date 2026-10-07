import 'package:ngoda/data_models/financial-intelligence/financial_behaviour.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_behaviour_identity.dart';

class FinancialBehaviourOverviewData {
  const FinancialBehaviourOverviewData({
    required this.summary,
    required this.identity,
  });

  final FinancialBehaviour summary;
  final FinancialBehaviourIdentity identity;

  factory FinancialBehaviourOverviewData.fromJson(Map<String, dynamic> json) {
    final summaryJson = _asMap(json['summary']);

    final resolvedSummary = summaryJson.isNotEmpty ? summaryJson : json;

    final summaryScores = _asMap(resolvedSummary['behavior_scores']);

    final rootScores = _asMap(json['behavior_scores']);

    final behaviorScores = summaryScores.isNotEmpty
        ? summaryScores
        : rootScores;

    final behavior =
        resolvedSummary['behavior']?.toString() ?? json['behavior']?.toString();

    return FinancialBehaviourOverviewData(
      summary: FinancialBehaviour.fromJson(resolvedSummary),
      identity: FinancialBehaviourIdentity.fromSummaryJson(
        behavior: behavior,
        scores: behaviorScores,
      ),
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
