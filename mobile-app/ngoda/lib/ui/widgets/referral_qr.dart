import 'package:flutter/material.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_qr_code.dart';

class ReferralQr extends StatelessWidget {
  final String referralLink;
  final double size;

  const ReferralQr({super.key, required this.referralLink, this.size = 250});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppQrCode(data: referralLink, size: size),

        SizedBox(height: spacing.sm),

        Text(
          'Gold is still the measure of wealth',
          textAlign: TextAlign.center,
          style: AppTextStyles.small(
            context,
          ).copyWith(color: colorScheme.secondary),
        ),
      ],
    );
  }
}
