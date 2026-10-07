import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/gl/gl_drilldown.dart';
import 'package:ngoda/data_models/gl/gl_period_balance.dart';
import 'package:ngoda/data_models/params/gl_drilldown_params.dart';
import 'package:ngoda/data_models/params/gl_entry_params.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_entry_color.dart';
import 'package:ngoda/ui/screens/finance/providers/gl_drilldown_balance_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class GlAccountDrilldownScreen extends ConsumerWidget {
  final GlDrilldownParams params;

  const GlAccountDrilldownScreen({super.key, required this.params});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(glDrilldownBalanceProvider(params));

    await ref.read(glDrilldownBalanceProvider(params).future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glDrilldownAsync = ref.watch(glDrilldownBalanceProvider(params));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'GL Account Periodic Balances',
              onClose: () {
                ref.invalidate(glDrilldownBalanceProvider(params));

                context.pop();
              },
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _refresh(ref),
                child: glDrilldownAsync.when(
                  loading: () => const AppLoader(
                    message: 'Loading GL periodic balances',
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

                    final drill = response.result;

                    if (drill == null || drill.periods.isEmpty) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _DrillContent(drill: drill, params: params);
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

class _DrillContent extends StatelessWidget {
  final GLDrilldown drill;
  final GlDrilldownParams params;

  const _DrillContent({required this.drill, required this.params});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _DrillHeader(drill: drill, currency: params.currency),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            spacing.padding,
            0,
            spacing.padding,
            spacing.xl,
          ),
          sliver: SliverList.builder(
            itemCount: drill.periods.length,
            itemBuilder: (context, index) {
              final period = drill.periods[index];

              return _PeriodCard(
                period: period,
                gl: drill.accountCode,
                currency: params.currency,
                fiscalYear: drill.fiscalYear,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DrillHeader extends StatelessWidget {
  final GLDrilldown drill;
  final String currency;

  const _DrillHeader({required this.drill, required this.currency});

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
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            drill.description,
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: spacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  drill.accountCode,
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
              SizedBox(width: spacing.sm),
              Text(
                currency.toUpperCase(),
                style: AppTextStyles.small(context).copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.md),
          _HeaderRow(label: 'Fiscal Year', value: drill.fiscalYear.toString()),
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

class _PeriodCard extends StatelessWidget {
  final GLPeriodBalance period;
  final String gl;
  final String currency;
  final int fiscalYear;

  const _PeriodCard({
    required this.period,
    required this.gl,
    required this.currency,
    required this.fiscalYear,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(radius.borderRadius),
      onTap: () {
        final params = GlEntryParams(
          gl: gl,
          currency: currency,
          fiscalYear: fiscalYear,
          period: period.period,
        );

        context.push('/gl-balances/$gl/entries', extra: params);
      },
      child: Container(
        margin: EdgeInsets.only(bottom: spacing.sm),
        padding: EdgeInsets.all(spacing.sm),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(radius.borderRadius),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                  Icons.chevron_right,
                  size: iconSize.small,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            SizedBox(height: spacing.sm),
            _AmountRow(
              label: 'Opening',
              value: period.opening,
              currency: currency,
              strong: true,
            ),
            SizedBox(height: spacing.xs),
            _DebitCreditRow(
              debit: period.debit,
              credit: period.credit,
              currency: currency,
              debitColor: getEntryColor(accountCode: gl, isDebit: true),
              creditColor: getEntryColor(accountCode: gl, isDebit: false),
            ),
            SizedBox(height: spacing.xs),
            _AmountRow(
              label: 'Closing',
              value: period.closing,
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
                  textAlign: TextAlign.right,
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
                  textAlign: TextAlign.right,
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
