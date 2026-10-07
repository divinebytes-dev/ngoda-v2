import 'package:flutter/material.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_colors.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_display_card.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';

class LoanCard extends StatelessWidget {
  final double principal;
  final double interest;
  final double requiredCollateral;
  final double ltv;
  final double svaUtilisation;

  const LoanCard({
    super.key,
    required this.principal,
    required this.interest,
    required this.requiredCollateral,
    required this.ltv,
    required this.svaUtilisation,
  });

  Color _ltvColor(BuildContext context) {
    if (ltv >= 75) {
      return context.colorScheme.error;
    }

    if (ltv >= 65) {
      return AppColors.warning;
    }

    return AppColors.success;
  }

  Color _svaColor(BuildContext context) {
    if (svaUtilisation >= 100) {
      return context.colorScheme.error;
    }

    if (svaUtilisation > 50) {
      return AppColors.warning;
    }

    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final total = principal + interest;

    final ltvColor = _ltvColor(context);

    final svaColor = _svaColor(context);

    return AppDisplayCard(
      accentColor: colorScheme.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Secured Value Access Balance',
            style: AppTextStyles.small(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),

          SizedBox(height: spacing.xs),

          Text(
            NumberFormatService.formatNumber(total, decimals: 6),
            style: AppTextStyles.mediumNumber(context),
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
            label: 'Access Balance',
            value: NumberFormatService.formatNumber(principal, decimals: 6),
          ),

          AppValueRow(
            label: 'Accrued Liquidity Fee',
            value: NumberFormatService.formatNumber(interest, decimals: 6),
          ),

          if (ltv >= 65)
            AppValueRow(
              label: 'Topup collateral',
              value: NumberFormatService.formatNumber(
                requiredCollateral,
                decimals: 6,
              ),
            ),

          AppValueRow(
            label: 'Access Ratio',
            value: '${ltv.toStringAsFixed(2)}%',
            labelStyle: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w600, color: ltvColor),
            valueStyle: AppTextStyles.smallNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w600, color: ltvColor),
          ),

          AppValueRow(
            label: 'SVA Utilisation',
            value: '${svaUtilisation.toStringAsFixed(2)}%',
            labelStyle: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w600, color: svaColor),
            valueStyle: AppTextStyles.smallNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w600, color: svaColor),
            addBottomSpacing: false,
          ),
        ],
      ),
    );
  }
}
