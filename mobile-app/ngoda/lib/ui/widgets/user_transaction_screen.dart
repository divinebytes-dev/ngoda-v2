import 'package:flutter/material.dart';
import 'package:ngoda/data_models/transaction/transaction_data.dart';
import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/number_format_service.dart';

import 'package:ngoda/services/transaction_qr_codec_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_qr_code.dart';

class UserTransactionScreen extends StatelessWidget {
  final TransactionData data;

  /// Determines whether the transaction uses the
  /// deposit-side amount calculation.
  ///
  /// This is retained for compatibility until transaction
  /// display amounts are derived directly from the
  /// transaction type.
  final bool isDeposit;

  final double size;

  const UserTransactionScreen({
    super.key,
    required this.data,
    this.size = 250,
    this.isDeposit = false,
  });

  double _minorUnitsToAmount(int amount) {
    return amount / 100;
  }

  double _displayAmount() {
    if (isDeposit) {
      return _minorUnitsToAmount(data.f) + _minorUnitsToAmount(data.a);
    }

    return _minorUnitsToAmount(data.g) + _minorUnitsToAmount(data.a);
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final qrData = TransactionQrCodecService.encode(data);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppQrCode(data: qrData, size: size),

        SizedBox(height: spacing.sm),

        Text(
          NumberFormatService.formatAmount(
            _displayAmount(),
            currency: CurrencyService.symbol(data.c),
          ),
          style: AppTextStyles.mediumNumber(context),
        ),

        SizedBox(height: spacing.xs),

        Text(
          data.s,
          textAlign: TextAlign.center,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
