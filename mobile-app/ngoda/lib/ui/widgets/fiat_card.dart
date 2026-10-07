import 'package:flutter/material.dart';
import 'package:ngoda/data_models/wallet/wallet.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_display_card.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';

class FiatCard extends StatelessWidget {
  final Wallet wallet;
  final Wallet? agentWallet;

  const FiatCard({super.key, required this.wallet, this.agentWallet});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final fiatEntries = wallet.currencies.entries
        .where((entry) => entry.key.toLowerCase() != 'gold')
        .toList();

    final totalUsd = fiatEntries.fold<double>(
      0,
      (total, entry) => total + entry.value.usdValue,
    );

    return AppDisplayCard(
      accentColor: colorScheme.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total Balance',
            style: AppTextStyles.small(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),

          SizedBox(height: spacing.xs),

          Text(
            NumberFormatService.formatUsd(totalUsd),
            style: AppTextStyles.largeNumber(context).copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.secondary,
            ),
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

          ...fiatEntries.map((entry) {
            final currency = entry.key.toUpperCase();

            final balance = entry.value.balance;

            final usd = entry.value.usdValue;

            return AppValueRow(
              label: currency,
              value: NumberFormatService.formatAmount(
                balance,
                currency: currency,
              ),
              secondaryValue: currency == 'USD'
                  ? null
                  : '≈ ${NumberFormatService.formatUsd(usd)}',
              secondaryValueStyle: AppTextStyles.tinyNumber(
                context,
              ).copyWith(color: colorScheme.onSurfaceVariant),
            );
          }),
        ],
      ),
    );
  }
}
