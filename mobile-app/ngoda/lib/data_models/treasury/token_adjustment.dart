import 'package:ngoda/services/number_conversion_service.dart';

class TokenAdjustment {
  const TokenAdjustment({
    required this.id,
    required this.documentNumber,
    required this.adjustmentType,
    required this.quantity,
    required this.uom,
    required this.status,
    required this.description,
    required this.totalTokens,
    required this.availableGold,
  });

  final String id;
  final String documentNumber;

  /// Dynamic backend adjustment type.
  final String adjustmentType;

  final double quantity;

  final String uom;

  /// Dynamic backend status.
  final String status;

  final String? description;

  /// Backend state snapshot.
  final double totalTokens;
  final double availableGold;

  factory TokenAdjustment.fromJson(Map<String, dynamic> json) {
    return TokenAdjustment(
      id: _requiredString(json['id'], 'id'),
      documentNumber: _requiredString(
        json['document_number'],
        'document_number',
      ),
      adjustmentType: _requiredString(
        json['adjustment_type'],
        'adjustment_type',
      ).toLowerCase(),
      quantity: NumberConversionService.toDouble(json['quantity']),
      uom: _requiredString(json['uom'], 'uom'),
      status: _requiredString(json['status'], 'status').toLowerCase(),
      description: _nullableString(json['description']),
      totalTokens: NumberConversionService.toDouble(json['total_tokens']),
      availableGold: NumberConversionService.toDouble(json['available_gold']),
    );
  }

  double? get currentCoverage {
    if (totalTokens == 0) {
      return null;
    }

    return availableGold / totalTokens;
  }
}

String _requiredString(dynamic value, String field) {
  final result = value?.toString().trim();

  if (result == null || result.isEmpty) {
    throw FormatException('TokenAdjustment.$field is required.');
  }

  return result;
}

String? _nullableString(dynamic value) {
  final result = value?.toString().trim();

  if (result == null || result.isEmpty) {
    return null;
  }

  return result;
}

extension GoldAdjustmentX on TokenAdjustment {
  /// coverage ratio = gold / tokens
  double get currentCoverage {
    if (totalTokens == 0) return 0;
    return availableGold / totalTokens;
  }

  double get projectedTokens {
    if (adjustmentType == 'minting') {
      return totalTokens + quantity;
    } else {
      return totalTokens - quantity;
    }
  }

  double get projectedGold {
    return availableGold;
    // if (adjustmentType == 'minting') {
    //   return availableGold + quantity;
    // } else {
    //   return availableGold - quantity;
    // }
  }

  double get projectedCoverage {
    final tokens = projectedTokens;
    if (tokens == 0) return 0;

    return projectedGold / tokens;
  }

  double get currentCoveragePercent => currentCoverage * 100;

  double get projectedCoveragePercent => projectedCoverage * 100;

  bool get isSafeAfterApproval => projectedCoverage >= 1;
}
