import 'package:flutter/material.dart';
import 'package:ngoda/data_models/transaction/transaction_data.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/services/transaction_qr_codec_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_qr_code.dart';

class QrPayment extends StatelessWidget {
  final TransactionData data;
  final double size;

  const QrPayment({super.key, required this.data, this.size = 250});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final qrData = TransactionQrCodecService.encode(data);

    final amount = (data.f / 100) + (data.a / 100);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppQrCode(data: qrData, size: size),

        SizedBox(height: spacing.sm),

        Text(
          NumberFormatService.formatAmount(amount, currency: data.c),
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
