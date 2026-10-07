import 'package:flutter/material.dart';
import 'package:ngoda/data_models/currency/currency.dart';

import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_search_dropdown_field.dart';

class CurrencyField extends StatelessWidget {
  final Currency? selected;
  final List<Currency> currencies;
  final Map<String, double> balances;

  final ValueChanged<Currency> onSelect;

  final bool showBalance;

  const CurrencyField({
    super.key,
    required this.selected,
    required this.currencies,
    required this.onSelect,
    this.balances = const {},
    this.showBalance = true,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return AppSearchDropdownField<Currency>(
      selected: selected,
      values: currencies,
      hint: 'Select currency',
      displayText: (currency) {
        return currency.code.toUpperCase();
      },
      filter: (currency, query) {
        return currency.code.toLowerCase().contains(query) ||
            currency.name.toLowerCase().contains(query);
      },
      onSelect: onSelect,
      itemBuilder: (context, currency) {
        final balance = balances[currency.code] ?? 0;

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.padding,
            vertical: spacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currency.code.toUpperCase(),
                      style: AppTextStyles.small(context),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      currency.name,
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),

              if (showBalance) ...[
                SizedBox(width: spacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      NumberFormatService.formatAmount(
                        balance,
                        currency: currency.code,
                      ),
                      style: AppTextStyles.smallNumber(context),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      'Available',
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
