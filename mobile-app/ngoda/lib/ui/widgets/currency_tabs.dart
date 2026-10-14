import 'package:flutter/material.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class CurrencyTabs extends StatelessWidget {
  final TabController controller;
  final List<String> currencies;

  const CurrencyTabs({
    super.key,
    required this.controller,
    required this.currencies,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: spacing.margin),
      padding: EdgeInsets.all(spacing.xs),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: TabBar(
        controller: controller,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(radius.cardRadius),
        ),
        labelColor: colorScheme.onPrimary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: AppTextStyles.tiny(
          context,
        ).copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: AppTextStyles.tiny(context),
        tabs: currencies.map((currency) {
          return Tab(
            child: SizedBox(
              width: double.infinity,
              child: Center(child: Text(currency.toUpperCase())),
            ),
          );
        }).toList(),
      ),
    );
  }
}
