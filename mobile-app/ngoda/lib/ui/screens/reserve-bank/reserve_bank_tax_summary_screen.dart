import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/reserve-bank/reserve_bank_tax_summary.dart';

import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/reserve-bank/providers/tax_payable_summary_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';

class ReserveBankTaxSummaryScreen extends ConsumerWidget {
  const ReserveBankTaxSummaryScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(taxPayableSummaryProvider);
    await ref.read(taxPayableSummaryProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taxSummary = ref.watch(taxPayableSummaryProvider);

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 2),
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'Tax Summary'),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _refresh(ref),
                child: taxSummary.when(
                  loading: () => const AppLoader(
                    message: 'Loading tax summary',
                    fullScreen: true,
                  ),
                  error: (error, _) =>
                      _RefreshableError(message: error.toString()),
                  data: (response) {
                    final error = response.error;
                    if (error != null) {
                      return _RefreshableError(message: error.toString());
                    }

                    final summary = response.result;
                    if (summary == null) {
                      return const _RefreshableEmpty();
                    }

                    return _TaxSummaryContent(summary: summary);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaxSummaryContent extends StatelessWidget {
  const _TaxSummaryContent({required this.summary});

  final ReserveBankTaxSummary summary;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.sm,
        spacing.md,
        spacing.lg,
      ),
      children: [
        _TotalTaxCard(
          totalUsd: summary.totalUsd,
          fiscalYear: summary.fiscalYear,
        ),
        SizedBox(height: spacing.lg),
        if (summary.currencies.isEmpty)
          const AppEmptyState()
        else ...[
          Text(
            'Tax by currency',
            style: AppTextStyles.medium(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: spacing.sm),
          for (final balance in summary.currencies)
            Padding(
              padding: EdgeInsets.only(bottom: spacing.sm),
              child: _CurrencyTaxCard(
                balance: balance,
                onTap: () {
                  final currency = Uri.encodeComponent(balance.currency);
                  context.push('/tax/$currency');
                },
              ),
            ),
        ],
      ],
    );
  }
}

String _formatAmount(String? value, String currency) {
  final amount = double.tryParse(value ?? '');
  if (amount == null || !amount.isFinite) {
    return 'Unavailable';
  }

  return NumberFormatService.formatAmount(amount, currency: currency);
}

class _TotalTaxCard extends StatelessWidget {
  const _TotalTaxCard({required this.totalUsd, required this.fiscalYear});

  final String? totalUsd;
  final int fiscalYear;

  static const Color _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(spacing.md),
        border: Border.all(color: _gold.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(spacing.sm),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.receipt_long_outlined,
                  color: _gold,
                  size: iconSize.large,
                ),
              ),

              SizedBox(width: spacing.sm),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total tax',
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),

                    SizedBox(height: spacing.xs),

                    Text(
                      'Fiscal year $fiscalYear · USD equivalent',
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: spacing.lg),

          Text(
            _formatAmount(totalUsd, 'usd'),
            style: AppTextStyles.mediumNumber(context),
          ),
        ],
      ),
    );
  }
}

class _CurrencyTaxCard extends StatelessWidget {
  const _CurrencyTaxCard({required this.balance, required this.onTap});

  final ReserveBankTaxCurrencySummary balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final currencyCode = balance.currency;
    final currencyName = CurrencyService.name(currencyCode);
    final currencySymbol = CurrencyService.symbol(currencyCode);

    return Material(
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius.cardRadius),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius.cardRadius),
        child: Padding(
          padding: EdgeInsets.all(spacing.md),
          child: Row(
            children: [
              _CurrencyIcon(code: currencyCode, symbol: currencySymbol),

              SizedBox(width: spacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currencyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),

                    SizedBox(height: spacing.xs),

                    Text(
                      currencyCode.toUpperCase(),
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),

              SizedBox(width: spacing.sm),

              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatAmount(balance.taxAmount, currencyCode),
                    style: AppTextStyles.smallNumber(context),
                  ),

                  SizedBox(height: spacing.xs),

                  Text(
                    _formatAmount(balance.usdValue, 'usd'),
                    style: AppTextStyles.tinyNumber(
                      context,
                    ).copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),

              SizedBox(width: spacing.sm),

              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrencyIcon extends StatelessWidget {
  const _CurrencyIcon({required this.code, required this.symbol});

  final String code;
  final String symbol;

  static const Color _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final fallback = code.isEmpty
        ? '?'
        : code.substring(0, code.length >= 2 ? 2 : code.length).toUpperCase();

    return Container(
      width: spacing.xxxl,
      height: spacing.xxxl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: _gold.withValues(alpha: 0.25)),
      ),
      child: Text(
        symbol.isNotEmpty ? symbol : fallback,
        style: symbol == 'GOLD'
            ? AppTextStyles.tiny(
                context,
              ).copyWith(color: _gold, fontWeight: FontWeight.w700)
            : AppTextStyles.small(
                context,
              ).copyWith(color: _gold, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _RefreshableError extends StatelessWidget {
  const _RefreshableError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: AppErrorState(message: message),
        ),
      ],
    );
  }
}

class _RefreshableEmpty extends StatelessWidget {
  const _RefreshableEmpty();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: const AppEmptyState(),
        ),
      ],
    );
  }
}
