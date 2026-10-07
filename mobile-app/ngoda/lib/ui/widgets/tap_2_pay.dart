import 'package:flutter/material.dart';

import 'package:ngoda/data_models/transaction/transaction_data.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class Tap2Pay extends StatelessWidget {
  final TransactionData data;

  const Tap2Pay({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(spacing.lg),
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(radius.cardRadius),
          ),
          child: Icon(
            Icons.contactless_rounded,
            size: iconSize.xl,
            color: colorScheme.onPrimary,
          ),
        ),

        SizedBox(height: spacing.sm),

        Text(
          NumberFormatService.formatAmount(data.a / 100, currency: data.c),
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
