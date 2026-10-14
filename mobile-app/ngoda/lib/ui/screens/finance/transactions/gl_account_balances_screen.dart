import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_sticky_header/flutter_sticky_header.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/gl/gl_account_balance.dart';
import 'package:ngoda/data_models/gl/gl_balance_summary.dart';
import 'package:ngoda/data_models/gl/gl_category_bucket.dart';
import 'package:ngoda/data_models/gl/gl_currency_balance.dart';
import 'package:ngoda/data_models/params/gl_drilldown_params.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_entry_color.dart';
import 'package:ngoda/ui/screens/finance/providers/gl_balances_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class GlAccountBalancesScreen extends ConsumerWidget {
  const GlAccountBalancesScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(glBalancesProvider);

    await ref.read(glBalancesProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glBalancesAsync = ref.watch(glBalancesProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'GL Account Balances',
              onClose: () {
                ref.invalidate(glBalancesProvider);

                context.pop();
              },
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _refresh(ref),
                child: glBalancesAsync.when(
                  loading: () => const AppLoader(
                    message: 'Loading GL balances',
                    fullScreen: true,
                  ),
                  error: (error, stackTrace) {
                    return _RefreshableState(
                      child: AppErrorState(message: error.toString()),
                    );
                  },
                  data: (response) {
                    if (response.error != null) {
                      return _RefreshableState(
                        child: AppErrorState(
                          message: response.error.toString(),
                        ),
                      );
                    }

                    final summary = response.result;

                    if (summary == null || summary.currencies.isEmpty) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _GlBalancesContent(summary: summary);
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

class _GlBalancesContent extends StatelessWidget {
  final GLBalanceSummary summary;

  const _GlBalancesContent({required this.summary});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final currencies = summary.currencies;

    return DefaultTabController(
      length: currencies.length,
      child: Column(
        children: [
          _GlHeader(summary: summary),
          Container(
            margin: EdgeInsets.symmetric(horizontal: spacing.padding),
            padding: EdgeInsets.all(spacing.xs),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(radius.cardRadius),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.09),
              ),
            ),
            child: TabBar(
              isScrollable: currencies.length > 4,
              tabAlignment: currencies.length > 4
                  ? TabAlignment.start
                  : TabAlignment.fill,
              indicator: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(radius.cardRadius),
              ),
              labelStyle: AppTextStyles.small(context),
              dividerColor: Colors.transparent,
              labelColor: colorScheme.onPrimary,
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: currencies
                  .map((currency) => Tab(text: currency.toUpperCase()))
                  .toList(),
            ),
          ),
          SizedBox(height: spacing.sm),
          Expanded(
            child: TabBarView(
              children: currencies.map((currency) {
                final currencyData = summary.byCurrency(currency);

                if (currencyData == null) {
                  return const Center(child: AppEmptyState());
                }

                return _GLCurrencyView(data: currencyData, currency: currency);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _GLCurrencyView extends StatelessWidget {
  final GLCurrencyBalance data;
  final String currency;

  const _GLCurrencyView({required this.data, required this.currency});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        _section(
          title: 'Assets',
          bucket: data.asset,
          currency: currency,
          context: context,
        ),
        _section(
          title: 'Liabilities',
          bucket: data.liability,
          currency: currency,
          context: context,
        ),
        _section(
          title: 'Equity',
          bucket: data.equity,
          currency: currency,
          context: context,
        ),
        _section(
          title: 'Revenue',
          bucket: data.revenue,
          currency: currency,
          context: context,
        ),
        _section(
          title: 'Expense',
          bucket: data.expense,
          currency: currency,
          context: context,
        ),
        SliverToBoxAdapter(child: SizedBox(height: spacing.xl)),
      ],
    );
  }

  Widget _section({
    required String title,
    required GLCategoryBucket bucket,
    required String currency,
    required BuildContext context,
  }) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return SliverStickyHeader(
      header: Container(
        margin: EdgeInsets.fromLTRB(
          spacing.padding,
          spacing.md,
          spacing.padding,
          0,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.sm,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(radius.cardRadius),
          ),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.09),
          ),
        ),
        child: Text(
          title,
          style: AppTextStyles.medium(context).copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      sliver: SliverToBoxAdapter(
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: spacing.padding),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(radius.cardRadius),
            ),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.09),
            ),
          ),
          child: Column(
            children: [
              if (bucket.accounts.isEmpty)
                Padding(
                  padding: EdgeInsets.all(spacing.xl),
                  child: const AppEmptyState(),
                )
              else
                ...bucket.accounts.map(
                  (account) => _GLRow(account: account, currency: currency),
                ),
              _SectionSummary(bucket: bucket, title: title, currency: currency),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlHeader extends StatelessWidget {
  final GLBalanceSummary summary;

  const _GlHeader({required this.summary});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      margin: EdgeInsets.fromLTRB(
        spacing.padding,
        0,
        spacing.padding,
        spacing.md,
      ),
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        children: [
          _HeaderRow(
            label: 'Fiscal Year',
            value: summary.fiscalYear.toString(),
          ),
          SizedBox(height: spacing.sm),
          _HeaderRow(label: 'Period', value: summary.period.toString()),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final String label;
  final String value;

  const _HeaderRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.small(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),
        Text(
          value,
          style: AppTextStyles.small(
            context,
          ).copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _GLRow extends StatelessWidget {
  final GLAccountBalance account;
  final String currency;

  const _GLRow({required this.account, required this.currency});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(radius.borderRadius),
      onTap: () {
        final params = GlDrilldownParams(
          gl: account.accountCode.trim(),
          currency: currency,
        );

        context.push('/gl-balances/$params', extra: params);
      },
      child: Container(
        padding: EdgeInsets.all(spacing.sm),
        margin: EdgeInsets.all(spacing.xs),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(radius.borderRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              account.description,
              style: AppTextStyles.tiny(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: spacing.xs),
            Text(
              account.accountCode,
              style: AppTextStyles.tiny(context).copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: spacing.sm),
            _AmountRow(
              label: 'Opening',
              value: account.opening,
              currency: currency,
              strong: true,
            ),
            SizedBox(height: spacing.xs),
            _DebitCreditRow(
              debit: account.debit,
              credit: account.credit,
              currency: currency,
              debitColor: getEntryColor(
                accountCode: account.accountCode,
                isDebit: true,
              ),
              creditColor: getEntryColor(
                accountCode: account.accountCode,
                isDebit: false,
              ),
            ),
            SizedBox(height: spacing.xs),
            _AmountRow(
              label: 'Closing',
              value: account.closing,
              currency: currency,
              strong: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _DebitCreditRow extends StatelessWidget {
  final double debit;
  final double credit;
  final String currency;
  final Color debitColor;
  final Color creditColor;

  const _DebitCreditRow({
    required this.debit,
    required this.credit,
    required this.currency,
    required this.debitColor,
    required this.creditColor,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Dr / Cr',
          style: AppTextStyles.tiny(context).copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        Flexible(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  NumberFormatService.formatAmount(debit, currency: currency),
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.tinyNumber(
                    context,
                  ).copyWith(color: debitColor, fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(width: spacing.xs),
              Text(
                '/',
                style: AppTextStyles.tiny(context).copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: spacing.xs),
              Flexible(
                child: Text(
                  NumberFormatService.formatAmount(credit, currency: currency),
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.tinyNumber(
                    context,
                  ).copyWith(color: creditColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final double value;
  final String currency;
  final bool strong;

  const _AmountRow({
    required this.label,
    required this.value,
    required this.currency,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.tiny(context).copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        Flexible(
          child: Text(
            NumberFormatService.formatAmount(value, currency: currency),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style:
                (strong
                        ? AppTextStyles.smallNumber(context)
                        : AppTextStyles.tinyNumber(context))
                    .copyWith(
                      fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                    ),
          ),
        ),
      ],
    );
  }
}

class _SectionSummary extends StatelessWidget {
  final GLCategoryBucket bucket;
  final String title;
  final String currency;

  const _SectionSummary({
    required this.bucket,
    required this.title,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      margin: EdgeInsets.fromLTRB(
        spacing.sm,
        spacing.sm,
        spacing.sm,
        spacing.md,
      ),
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius.borderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Summary',
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: spacing.sm),
          _AmountRow(
            label: 'Opening',
            value: bucket.totalOpening,
            currency: currency,
            strong: true,
          ),
          SizedBox(height: spacing.xs),
          _DebitCreditRow(
            debit: bucket.totalDebit,
            credit: bucket.totalCredit,
            currency: currency,
            debitColor: getEntryColorByAccountName(
              accountName: title,
              isDebit: true,
            ),
            creditColor: getEntryColorByAccountName(
              accountName: title,
              isDebit: false,
            ),
          ),
          SizedBox(height: spacing.xs),
          _AmountRow(
            label: 'Closing',
            value: bucket.totalClosing,
            currency: currency,
            strong: true,
          ),
        ],
      ),
    );
  }
}

class _RefreshableState extends StatelessWidget {
  final Widget child;

  const _RefreshableState({required this.child});

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
