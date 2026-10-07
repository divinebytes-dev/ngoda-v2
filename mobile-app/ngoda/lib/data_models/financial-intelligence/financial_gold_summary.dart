import 'package:ngoda/services/number_conversion_service.dart';

class FinancialGoldSummary {
  const FinancialGoldSummary({
    required this.openingQuantity,
    required this.purchased,
    required this.sold,
    required this.transferredIn,
    required this.transferredOut,
    required this.closingQuantity,
  });

  final double openingQuantity;

  final double purchased;
  final double sold;

  final double transferredIn;
  final double transferredOut;

  final double closingQuantity;

  factory FinancialGoldSummary.fromJson(Map<String, dynamic> json) {
    return FinancialGoldSummary(
      openingQuantity: NumberConversionService.toDouble(
        json['opening_quantity'],
      ),
      purchased: NumberConversionService.toDouble(json['purchased']),
      sold: NumberConversionService.toDouble(json['sold']),
      transferredIn: NumberConversionService.toDouble(json['transferred_in']),
      transferredOut: NumberConversionService.toDouble(json['transferred_out']),
      closingQuantity: NumberConversionService.toDouble(
        json['closing_quantity'],
      ),
    );
  }

  double get totalIn => purchased + transferredIn;

  double get totalOut => sold + transferredOut;

  double get netMovement => totalIn - totalOut;

  bool get increased => netMovement > 0;

  bool get decreased => netMovement < 0;

  bool get unchanged => netMovement == 0;

  bool get hasActivity =>
      purchased != 0 || sold != 0 || transferredIn != 0 || transferredOut != 0;

  Map<String, double> get movementChart {
    return {
      'purchased': purchased,
      'sold': sold,
      'transfer_in': transferredIn,
      'transfer_out': transferredOut,
    };
  }

  Map<String, double> get flowChart {
    return {'in': totalIn, 'out': totalOut};
  }

  Map<String, double> get nonZeroMovementChart {
    return Map.unmodifiable(
      Map.fromEntries(movementChart.entries.where((entry) => entry.value > 0)),
    );
  }
}
