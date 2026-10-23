import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/finance/financial_statement_drilldown.dart';
import 'package:ngoda/data_models/params/financial_statement_params.dart';
import 'package:ngoda/data_models/wallet/periodic_balance_entry.dart';
import 'package:ngoda/services/date_format_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_entry_color.dart';
import 'package:ngoda/ui/functions/transaction_formatter.dart';
import 'package:ngoda/ui/screens/finance/providers/financial_statement_entries_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_pagination.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class FinancialStatementEntriesScreen extends ConsumerStatefulWidget {
  const FinancialStatementEntriesScreen({
    super.key,
    required this.params,
    required this.title,
  });

  final FinancialStatementParams params;
  final String title;

  @override
  ConsumerState<FinancialStatementEntriesScreen> createState() =>
      _FinancialStatementEntriesScreenState();
}

class _FinancialStatementEntriesScreenState
    extends ConsumerState<FinancialStatementEntriesScreen> {
  late int currentPage;
  late int pageSize;

  @override
  void initState() {
    super.initState();

    currentPage = widget.params.page;
    pageSize = widget.params.pageSize;
  }

  FinancialStatementParams get currentParams {
    return widget.params.copyWith(page: currentPage, pageSize: pageSize);
  }

  Future<void> _refresh() async {
    ref.invalidate(financialStatementEntriesProvider(currentParams));

    await ref.read(financialStatementEntriesProvider(currentParams).future);
  }

  void _previousPage() {
    if (currentPage <= 1) {
      return;
    }

    setState(() {
      currentPage--;
    });
  }

  void _nextPage() {
    setState(() {
      currentPage++;
    });
  }

  void _changePageSize(int value) {
    setState(() {
      pageSize = value;
      currentPage = 1;
    });
  }

  void _closeScreen() {
    ref.invalidate(financialStatementEntriesProvider(currentParams));

    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(
      financialStatementEntriesProvider(currentParams),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(title: widget.title, onClose: _closeScreen),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: asyncData.when(
                  loading: () => const AppLoader(
                    message: 'Loading GL entries',
                    fullScreen: true,
                  ),
                  error: (error, _) {
                    return _RefreshableState(
                      child: AppErrorState(message: error.toString()),
                    );
                  },
                  data: (response) {
                    if (response.error != null) {
                      return _RefreshableState(
                        child: AppErrorState(message: response.error!),
                      );
                    }

                    final drilldown = response.result;

                    if (drilldown == null) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _DrilldownContent(
                      drilldown: drilldown,
                      pageSize: pageSize,
                      onPrevious: _previousPage,
                      onNext: _nextPage,
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

class _DrilldownContent extends StatelessWidget {
  const _DrilldownContent({
    required this.drilldown,
    required this.pageSize,
    required this.onPrevious,
    required this.onNext,
    required this.onPageSizeChanged,
  });

  final FinancialStatementDrilldown drilldown;
  final int pageSize;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int> onPageSizeChanged;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _ReportHeader(drilldown: drilldown)),
        SliverToBoxAdapter(
          child: _SectionHeader(
            totalEntries: drilldown.pagination.totalEntries,
          ),
        ),
        if (!drilldown.hasEntries)
          const SliverToBoxAdapter(
            child: SizedBox(height: 250, child: AppEmptyState()),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(spacing.sm, 0, spacing.sm, spacing.sm),
            sliver: SliverList.builder(
              itemCount: drilldown.entries.length,
              itemBuilder: (context, index) {
                return _EntryCard(
                  entry: drilldown.entries[index],
                  glAccount: drilldown.glAccountCode,
                  currency: drilldown.currencyCode,
                );
              },
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: spacing.sm),
          sliver: SliverToBoxAdapter(
            child: AppPagination(
              page: drilldown.pagination.page,
              totalPages: drilldown.pagination.totalPages,
              totalEntries: drilldown.pagination.totalEntries,
              hasPrevious: drilldown.pagination.hasPrevious,
              hasNext: drilldown.pagination.hasNext,
              onPrevious: onPrevious,
              onNext: onNext,
              entryLabel: 'entries',
              pageSize: pageSize,
              onPageSizeChanged: onPageSizeChanged,
            ),
          ),
        ),
        SliverToBoxAdapter(child: _TotalsCard(drilldown: drilldown)),
        SliverToBoxAdapter(child: _BalanceStatusCard(drilldown: drilldown)),
        SliverToBoxAdapter(child: SizedBox(height: spacing.lg)),
      ],
    );
  }
}

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({required this.drilldown});

  final FinancialStatementDrilldown drilldown;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      margin: EdgeInsets.fromLTRB(spacing.sm, 0, spacing.sm, spacing.lg),
      padding: EdgeInsets.all(spacing.padding),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
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
              Text(
                drilldown.glAccountCode,
                style: AppTextStyles.tiny(
                  context,
                ).copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                drilldown.currencyCode.toUpperCase(),
                style: AppTextStyles.small(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          SizedBox(height: spacing.lg),
          _row(
            context,
            label: 'Start Date',
            value: DateFormatService.formatDisplayDate(drilldown.startDate),
          ),
          SizedBox(height: spacing.sm),
          _row(
            context,
            label: 'End Date',
            value: DateFormatService.formatDisplayDate(drilldown.endDate),
          ),
          SizedBox(height: spacing.sm),
          _amountRow(
            context,
            label: 'Opening Balance',
            value: drilldown.openingBalance,
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required String label,
    required String value,
  }) {
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

  Widget _amountRow(
    BuildContext context, {
    required String label,
    required double value,
  }) {
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
          NumberFormatService.formatAmount(
            value,
            currency: drilldown.currencyCode,
          ),
          style: AppTextStyles.smallNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.totalEntries});

  final int totalEntries;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.sm, 0, spacing.sm, spacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'GL Entries',
              style: AppTextStyles.small(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.sm,
              vertical: spacing.xs,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(radius.borderRadius),
            ),
            child: Text(
              totalEntries.toString(),
              style: AppTextStyles.tinyNumber(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
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
              context.push(
                '/recent-transactions/'
                '${entry.documentNumber}',
              );
            },
      child: Container(
        margin: EdgeInsets.only(bottom: spacing.sm),
        padding: EdgeInsets.all(spacing.sm),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
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
                    formatTxType(entry.transactionType),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.small(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
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
                    size: iconSize.medium,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
            if (entry.documentNumber.isNotEmpty) ...[
              SizedBox(height: spacing.xs),
              Text(
                entry.documentNumber,
                style: AppTextStyles.tiny(
                  context,
                ).copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
            SizedBox(height: spacing.sm),
            Row(
              children: [
                Expanded(
                  child: _amountColumn(
                    context,
                    label: 'Debit',
                    value: entry.debit,
                    color: getEntryColor(accountCode: glAccount, isDebit: true),
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: _amountColumn(
                    context,
                    label: 'Credit',
                    value: entry.credit,
                    color: getEntryColor(
                      accountCode: glAccount,
                      isDebit: false,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.sm),
            Divider(color: colorScheme.outlineVariant),
            SizedBox(height: spacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Running Balance',
                  style: AppTextStyles.tiny(context).copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  NumberFormatService.formatAmount(
                    entry.runningBalance,
                    currency: currency,
                  ),
                  style: AppTextStyles.smallNumber(
                    context,
                  ).copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountColumn(
    BuildContext context, {
    required String label,
    required double value,
    required Color color,
  }) {
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

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.drilldown});

  final FinancialStatementDrilldown drilldown;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      margin: EdgeInsets.fromLTRB(
        spacing.sm,
        spacing.xs,
        spacing.sm,
        spacing.sm,
      ),
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        children: [
          _row(context, 'Opening Balance', drilldown.openingBalance),
          SizedBox(height: spacing.sm),
          _row(context, 'Total Debit', drilldown.totalDebit),
          SizedBox(height: spacing.sm),
          _row(context, 'Total Credit', drilldown.totalCredit),
          SizedBox(height: spacing.sm),
          _row(
            context,
            'Calculated Closing',
            drilldown.calculatedClosingBalance,
          ),
          SizedBox(height: spacing.sm),
          _row(
            context,
            'Closing Balance',
            drilldown.closingBalance,
            strong: true,
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    double value, {
    bool strong = false,
  }) {
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
        Text(
          NumberFormatService.formatAmount(
            value,
            currency: drilldown.currencyCode,
          ),
          style: AppTextStyles.smallNumber(
            context,
          ).copyWith(fontWeight: strong ? FontWeight.w800 : FontWeight.w600),
        ),
      ],
    );
  }
}

class _BalanceStatusCard extends StatelessWidget {
  const _BalanceStatusCard({required this.drilldown});

  final FinancialStatementDrilldown drilldown;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;

    final color = drilldown.balanced
        ? const Color(0xFF16A34A)
        : const Color(0xFFDC2626);

    return Container(
      margin: EdgeInsets.symmetric(horizontal: spacing.sm),
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
            size: iconSize.medium,
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
            Text(
              NumberFormatService.formatAmount(
                drilldown.difference,
                currency: drilldown.currencyCode,
              ),
              style: AppTextStyles.smallNumber(
                context,
              ).copyWith(color: color, fontWeight: FontWeight.w800),
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
