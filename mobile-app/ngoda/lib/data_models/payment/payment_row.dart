import 'package:ngoda/ui/enums/enums.dart';

class PaymentRow {
  const PaymentRow(
    this.label,
    this.value, {
    this.isBold = false,
    this.isMuted = false,
    this.type = PaymentRowType.amount,
  });

  final String label;
  final String value;

  final bool isBold;
  final bool isMuted;

  final PaymentRowType type;
}
