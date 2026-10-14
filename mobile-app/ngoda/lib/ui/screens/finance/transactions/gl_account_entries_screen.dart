import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/data_models/params/gl_entry_params.dart';
import 'package:ngoda/data_models/wallet/periodic_balance_drilldown.dart';
import 'package:ngoda/data_models/wallet/periodic_balance_entry.dart';
import 'package:ngoda/services/date_format_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_entry_color.dart';
import 'package:ngoda/ui/screens/finance/providers/gl_entries_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_pagination.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class GlAccountEntriesScreen extends ConsumerStatefulWidget {
  const GlAccountEntriesScreen({super.key, required this.params});

  final GlEntryParams params;

  @override
  ConsumerState<GlAccountEntriesScreen> createState() =>
      _GlAccountEntriesScreenState();
}

class _GlAccountEntriesScreenState
    extends ConsumerState<GlAccountEntriesScreen> {
  late int currentPage;
  late int pageSize;

  @override
  void initState() {
    super.initState();

    currentPage = widget.params.page;
    pageSize = widget.params.pageSize;
  }

  GlEntryParams get currentParams {
    return widget.params.copyWith(page: currentPage, pageSize: pageSize);
  }

  Future<void> _refresh() async {
    ref.invalidate(glEntriesProvider(currentParams));

    await ref.read(glEntriesProvider(currentParams).future);
  }

  void _goToPreviousPage() {
    if (currentPage <= 1) return;

    setState(() {
      currentPage--;
    });
  }

  void _goToNextPage() {
    setState(() {
      currentPage++;
    });
  }

  void _changePageSize(int newPageSize) {
    if (newPageSize <= 0 || newPageSize == pageSize) return;

    setState(() {
      pageSize = newPageSize;
      currentPage = 1;
    });
  }

  void _closeScreen() {
    ref.invalidate(glEntriesProvider(currentParams));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(glEntriesProvider(currentParams));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(title: 'GL Period Entries', onClose: _closeScreen),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: asyncData.when(
                  loading: () => const AppLoader(
                    message: 'Loading GL entries',
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

                    final drilldown = response.result;

                    if (drilldown == null) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _GlPeriodContent(
                      drilldown: drilldown,
                      onPrevious: _goToPreviousPage,
                      onNext: _goToNextPage,
                      onPageSizeChanged: _changePageSize,
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

class _GlPeriodContent extends StatelessWidget {
  const _GlPeriodContent({
    required this.drilldown,
    required this.onPrevious,
    required this.onNext,
    required this.onPageSizeChanged,
  });

  final PeriodicBalanceDrilldown drilldown;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int> onPageSizeChanged;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final pagination = drilldown.pagination;

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _PeriodHeader(drilldown: drilldown)),

              if (drilldown.entries.isEmpty)
                const SliverToBoxAdapter(
                  child: SizedBox(height: 250, child: AppEmptyState()),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    spacing.padding,
                    0,
                    spacing.padding,
                    spacing.sm,
                  ),
                  sliver: SliverList.builder(
                    itemCount: drilldown.entries.length,
                    itemBuilder: (context, index) {
                      final entry = drilldown.entries[index];

                      return _EntryCard(
                        entry: entry,
                        glAccount: drilldown.glAccountCode,
                        currency: drilldown.currencyCode,
                      );
                    },
                  ),
                ),

              SliverToBoxAdapter(
                child: _PeriodTotalsCard(drilldown: drilldown),
              ),

              SliverToBoxAdapter(
                child: _BalanceStatusCard(drilldown: drilldown),
              ),

              SliverToBoxAdapter(child: SizedBox(height: spacing.xl)),
            ],
          ),
        ),

        if (pagination.totalEntries > 0)
          AppPagination(
            page: pagination.page,
            totalPages: pagination.totalPages,
            totalEntries: pagination.totalEntries,
            hasPrevious: pagination.hasPrevious,
            hasNext: pagination.hasNext,
            pageSize: pagination.pageSize,
            onPrevious: onPrevious,
            onNext: onNext,
            onPageSizeChanged: onPageSizeChanged,
          ),
      ],
    );
  }
}

class _PeriodHeader extends StatelessWidget {
  const _PeriodHeader({required this.drilldown});

  final PeriodicBalanceDrilldown drilldown;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            drilldown.glDescription,
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),

          SizedBox(height: spacing.xs),

          Row(
            children: [
              Expanded(
                child: Text(
                  drilldown.glAccountCode,
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),

              SizedBox(width: spacing.sm),

              Text(
                drilldown.currencyCode.toUpperCase(),
                style: AppTextStyles.small(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),

          SizedBox(height: spacing.md),

          _TextRow(
            label: 'Fiscal Year',
            value: drilldown.fiscalYear.toString(),
          ),

          SizedBox(height: spacing.sm),

          _TextRow(label: 'Period', value: drilldown.period.toString()),

          SizedBox(height: spacing.sm),

          _AmountRow(
            label: 'Opening Balance',
            value: drilldown.openingBalance,
            currency: drilldown.currencyCode,
            strong: true,
          ),
        ],
      ),
    );
  }
}

class _TextRow extends StatelessWidget {
  const _TextRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),
        Text(
          value,
          style: AppTextStyles.small(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.glAccount,
    required this.currency,
  });

  final PeriodicBalanceEntry entry;
  final String glAccount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(radius.borderRadius),
      onTap: entry.documentNumber.isEmpty
          ? null
          : () {
              context.push('/recent-transactions/${entry.documentNumber}');
            },
      child: Container(
        margin: EdgeInsets.only(bottom: spacing.sm),
        padding: EdgeInsets.all(spacing.sm),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(radius.borderRadius),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.09),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.transactionType.replaceAll('_', ' ').toUpperCase(),
                    style: AppTextStyles.tiny(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                ),

                SizedBox(width: spacing.sm),

                Text(
                  DateFormatService.formatDateTime(entry.createdAt),
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),

                if (entry.documentNumber.isNotEmpty) ...[
                  SizedBox(width: spacing.sm),
                  Icon(
                    Icons.chevron_right,
                    size: iconSize.small,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),

            if (entry.documentNumber.isNotEmpty) ...[
              SizedBox(height: spacing.xs),
              Text(
                entry.documentNumber,
                style: AppTextStyles.tiny(context).copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],

            SizedBox(height: spacing.sm),

            Row(
              children: [
                Expanded(
                  child: _EntryAmount(
                    label: 'Debit',
                    value: entry.debit,
                    currency: currency,
                    color: getEntryColor(accountCode: glAccount, isDebit: true),
                  ),
                ),

                SizedBox(width: spacing.sm),

                Expanded(
                  child: _EntryAmount(
                    label: 'Credit',
                    value: entry.credit,
                    currency: currency,
                    color: getEntryColor(
                      accountCode: glAccount,
                      isDebit: false,
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: spacing.sm),

            Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.09)),

            SizedBox(height: spacing.xs),

            _AmountRow(
              label: 'Running Balance',
              value: entry.runningBalance,
              currency: currency,
              strong: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryAmount extends StatelessWidget {
  const _EntryAmount({
    required this.label,
    required this.value,
    required this.currency,
    required this.color,
  });

  final String label;
  final double value;
  final String currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),

        SizedBox(height: spacing.xs),

        Text(
          value == 0
              ? '-'
              : NumberFormatService.formatAmount(value, currency: currency),
          style: AppTextStyles.smallNumber(context).copyWith(
            color: value == 0 ? colorScheme.onSurfaceVariant : color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PeriodTotalsCard extends StatelessWidget {
  const _PeriodTotalsCard({required this.drilldown});

  final PeriodicBalanceDrilldown drilldown;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      margin: EdgeInsets.fromLTRB(
        spacing.padding,
        spacing.xs,
        spacing.padding,
        spacing.sm,
      ),
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        children: [
          _AmountRow(
            label: 'Opening Balance',
            value: drilldown.openingBalance,
            currency: drilldown.currencyCode,
          ),

          SizedBox(height: spacing.sm),

          _AmountRow(
            label: 'Total Debit',
            value: drilldown.totalDebit,
            currency: drilldown.currencyCode,
          ),

          SizedBox(height: spacing.sm),

          _AmountRow(
            label: 'Total Credit',
            value: drilldown.totalCredit,
            currency: drilldown.currencyCode,
          ),

          SizedBox(height: spacing.sm),

          _AmountRow(
            label: 'Calculated Closing',
            value: drilldown.calculatedClosingBalance,
            currency: drilldown.currencyCode,
          ),

          SizedBox(height: spacing.sm),

          _AmountRow(
            label: 'Snapshot Closing',
            value: drilldown.closingBalance,
            currency: drilldown.currencyCode,
            strong: true,
          ),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    required this.currency,
    this.strong = false,
  });

  final String label;
  final double value;
  final String currency;
  final bool strong;

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
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
          ),
        ),

        Flexible(
          child: Text(
            NumberFormatService.formatAmount(value, currency: currency),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.smallNumber(
              context,
            ).copyWith(fontWeight: strong ? FontWeight.w800 : FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _BalanceStatusCard extends StatelessWidget {
  const _BalanceStatusCard({required this.drilldown});

  final PeriodicBalanceDrilldown drilldown;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;

    final color = drilldown.balanced
        ? const Color(0xFF16A34A)
        : const Color(0xFFDC2626);

    return Container(
      margin: EdgeInsets.symmetric(horizontal: spacing.padding),
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(
            drilldown.balanced ? Icons.check_circle : Icons.error_outline,
            color: color,
          ),

          SizedBox(width: spacing.sm),

          Expanded(
            child: Text(
              drilldown.balanced ? 'Balanced' : 'Out of balance',
              style: AppTextStyles.small(
                context,
              ).copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ),

          if (!drilldown.balanced)
            Flexible(
              child: Text(
                NumberFormatService.formatAmount(
                  drilldown.difference,
                  currency: drilldown.currencyCode,
                ),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.smallNumber(
                  context,
                ).copyWith(color: color, fontWeight: FontWeight.w800),
              ),
            ),
        ],
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
