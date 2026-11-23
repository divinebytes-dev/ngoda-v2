import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/params/tax_entry_params.dart';
import 'package:ngoda/data_models/reserve-bank/reserve_bank_periodic_tax.dart';

import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/reserve-bank/providers/reserve_bank_periodic_tax_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class ReserveBankTaxPeriodScreen extends ConsumerWidget {
  const ReserveBankTaxPeriodScreen({super.key, required this.currency});

  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencyCode = currency.trim().toLowerCase();
    final provider = periodicTaxBalanceProvider(currencyCode);
    final periodsAsync = ref.watch(provider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Tax Payable Periods',
              onClose: () => context.pop(),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(provider);
                  await ref.read(provider.future);
                },
                child: periodsAsync.when(
                  loading: () => const AppLoader(
                    message: 'Loading tax periods',
                    fullScreen: false,
                  ),
                  error: (error, _) => _RefreshableState(
                    child: AppErrorState(message: error.toString()),
                  ),
                  data: (response) {
                    final error = response.error;
                    if (error != null) {
                      return _RefreshableState(
                        child: AppErrorState(message: error.toString()),
                      );
                    }

                    final snapshot = response.result;
                    if (snapshot == null || snapshot.periods.isEmpty) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _TaxPeriodContent(
                      fiscalYear: snapshot.fiscalYear,
                      currency: currencyCode,
                      periods: snapshot.periods,
                    );
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

class _TaxPeriodContent extends StatelessWidget {
  const _TaxPeriodContent({
    required this.fiscalYear,
    required this.currency,
    required this.periods,
  });

  final int fiscalYear;
  final String currency;
  final List<ReserveBankTaxPeriodBalance> periods;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.sm,
        spacing.md,
        spacing.lg,
      ),
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(spacing.lg),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(spacing.md),
            border: Border.all(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              _CurrencyIcon(
                currency: currency,
                symbol: CurrencyService.symbol(currency),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      CurrencyService.name(currency),
                      style: AppTextStyles.medium(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      '${currency.toUpperCase()} • Fiscal year $fiscalYear',
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.lg),
        Text(
          'Fiscal periods',
          style: AppTextStyles.medium(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: spacing.sm),
        for (final period in periods)
          Padding(
            padding: EdgeInsets.only(bottom: spacing.sm),
            child: _TaxPeriodCard(
              period: period,
              currency: currency,
              onTap: () {
                final code = Uri.encodeComponent(currency);

                context.push(
                  '/tax/$code/tax-entry',
                  extra: TaxEntryParams(
                    currency: currency,
                    fiscalYear: fiscalYear,
                    period: period.period,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _TaxPeriodCard extends StatelessWidget {
  const _TaxPeriodCard({
    required this.period,
    required this.currency,
    required this.onTap,
  });

  final ReserveBankTaxPeriodBalance period;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Material(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(spacing.md),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(spacing.md),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Period ${period.period}',
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              SizedBox(height: spacing.md),
              _TaxMetric(
                label: 'Gross amount',
                value: NumberFormatService.formatAmount(
                  period.grossAmount,
                  currency: currency,
                ),
              ),
              SizedBox(height: spacing.sm),
              _TaxMetric(
                label: 'Tax amount',
                value: NumberFormatService.formatAmount(
                  period.taxAmount,
                  currency: currency,
                ),
              ),
              SizedBox(height: spacing.sm),
              _TaxMetric(
                label: 'Effective tax rate',
                value: period.taxRate == null ? '—' : '${period.taxRate}%',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaxMetric extends StatelessWidget {
  const _TaxMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTextStyles.small(context))),
        Text(value, style: AppTextStyles.small(context)),
      ],
    );
  }
}

class _CurrencyIcon extends StatelessWidget {
  const _CurrencyIcon({required this.currency, required this.symbol});

  final String currency;
  final String symbol;

  static const Color _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final fallback = currency.isEmpty
        ? '?'
        : currency
              .substring(0, currency.length >= 2 ? 2 : currency.length)
              .toUpperCase();

    return Container(
      width: spacing.xxl,
      height: spacing.xxl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: _gold.withValues(alpha: 0.25)),
      ),
      child: Text(
        symbol.isNotEmpty ? symbol : fallback,
        style: currency.toLowerCase() == "gold"
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

class _RefreshableState extends StatelessWidget {
  const _RefreshableState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: Center(child: child),
        ),
      ],
    );
  }
}
