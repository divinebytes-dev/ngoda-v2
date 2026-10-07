import 'package:flutter/material.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_display_card.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';

class GoldCard extends StatelessWidget {
  final double totalGrams;
  final double totalUsd;

  final double locked;
  final double lockedUsd;

  final double available;
  final double availableUsd;

  const GoldCard({
    super.key,
    required this.totalGrams,
    required this.totalUsd,
    required this.locked,
    required this.lockedUsd,
    required this.available,
    required this.availableUsd,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final goldColor = colorScheme.primary;

    final secondaryNumberStyle = AppTextStyles.tinyNumber(context).copyWith(
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurfaceVariant,
    );

    return AppDisplayCard(
      accentColor: goldColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gold Holdings',
            style: AppTextStyles.small(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),

          SizedBox(height: spacing.xs),

          Text(
            '${NumberFormatService.formatNumber(totalGrams, decimals: 8)} g',
            style: AppTextStyles.mediumNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w700, color: goldColor),
          ),

          SizedBox(height: spacing.xs),

          Text(
            '≈ ${NumberFormatService.formatUsd(totalUsd)}',
            style: AppTextStyles.smallNumber(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),

          SizedBox(height: spacing.sm),

          const Divider(),

          SizedBox(height: spacing.sm),

          Text(
            'Breakdown',
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),

          SizedBox(height: spacing.sm),

          AppValueRow(
            label: 'Locked',
            value: '${NumberFormatService.formatNumber(locked, decimals: 6)} g',
            secondaryValue: '≈ ${NumberFormatService.formatUsd(lockedUsd)}',
            secondaryValueStyle: secondaryNumberStyle,
          ),

          AppValueRow(
            label: 'Available',
            value:
                '${NumberFormatService.formatNumber(available, decimals: 6)} g',
            secondaryValue: '≈ ${NumberFormatService.formatUsd(availableUsd)}',
            secondaryValueStyle: secondaryNumberStyle,
            addBottomSpacing: false,
          ),
        ],
      ),
    );
  }
}
