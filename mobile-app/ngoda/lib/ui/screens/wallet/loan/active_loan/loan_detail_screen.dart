import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/data_models/loan/loan_detail.dart';
import 'package:ngoda/data_models/loan/loan_entry.dart';
import 'package:ngoda/data_models/params/loan_details_params.dart';
import 'package:ngoda/services/date_format_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/transaction_formatter.dart';
import 'package:ngoda/ui/screens/wallet/loan/provider/loan_detail_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_pagination.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class LoanDetailScreen extends ConsumerStatefulWidget {
  const LoanDetailScreen({super.key, required this.loanId});

  final String loanId;

  @override
  ConsumerState<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends ConsumerState<LoanDetailScreen> {
  static const List<int> _pageSizeOptions = [10, 25, 50, 100];

  late LoanDetailsParams _params;

  @override
  void initState() {
    super.initState();

    _params = LoanDetailsParams(loanId: widget.loanId);
  }

  @override
  void didUpdateWidget(covariant LoanDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.loanId != widget.loanId) {
      _params = LoanDetailsParams(loanId: widget.loanId);
    }
  }

  void _previousPage() {
    if (_params.page <= 1) {
      return;
    }

    setState(() {
      _params = _params.copyWith(page: _params.page - 1);
    });
  }

  void _nextPage(int totalPages) {
    if (_params.page >= totalPages) {
      return;
    }

    setState(() {
      _params = _params.copyWith(page: _params.page + 1);
    });
  }

  void _changePageSize(int pageSize) {
    if (_params.pageSize == pageSize) {
      return;
    }

    setState(() {
      _params = _params.copyWith(page: 1, pageSize: pageSize);
    });
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final asyncData = ref.watch(loanDetailsProvider(_params));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.lg),
              child: ViewHeader(
                title: 'Secured Value Access Details',
                onClose: context.pop,
              ),
            ),

            Expanded(
              child: asyncData.when(
                loading: () => const Center(
                  child: AppLoader(
                    message: 'Loading value access transactions',
                    fullScreen: false,
                  ),
                ),

                error: (error, _) =>
                    AppErrorState(title: 'Error', message: error.toString()),

                data: (result) {
                  if (result.error != null) {
                    return AppErrorState(
                      title: 'Error',
                      message: result.error!,
                    );
                  }

                  final details = result.result;

                  if (details == null) {
                    return const AppEmptyState();
                  }

                  final pagination = details.pagination;

                  return Column(
                    children: [
                      Expanded(child: _LoanDetailsView(details: details)),

                      if (pagination.totalEntries > 0)
                        AppPagination(
                          page: pagination.page,
                          totalPages: pagination.totalPages,
                          totalEntries: pagination.totalEntries,
                          hasPrevious: pagination.hasPrevious,
                          hasNext: pagination.hasNext,
                          pageSize: pagination.pageSize,
                          pageSizeOptions: _pageSizeOptions,
                          onPrevious: _previousPage,
                          onNext: () => _nextPage(pagination.totalPages),
                          onPageSizeChanged: _changePageSize,
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoanDetailsView extends StatelessWidget {
  const _LoanDetailsView({required this.details});

  final LoanDetails details;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        spacing.lg,
        spacing.sm,
        spacing.lg,
        spacing.lg,
      ),
      children: [
        _BalanceSummaryCard(details: details),

        SizedBox(height: spacing.lg),

        _BreakdownCard(details: details),

        SizedBox(height: spacing.lg),

        Text(
          'Transactions',
          style: AppTextStyles.small(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),

        SizedBox(height: spacing.md),

        if (details.entries.isEmpty)
          const AppEmptyState()
        else
          ...details.entries.map(
            (entry) => Padding(
              padding: EdgeInsets.only(bottom: spacing.md),
              child: _LoanEntryCard(entry: entry),
            ),
          ),
      ],
    );
  }
}

class _BalanceSummaryCard extends StatelessWidget {
  const _BalanceSummaryCard({required this.details});

  final LoanDetails details;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.error;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(context.radius.lg),
        border: Border.all(color: accent.withValues(alpha: 0.09)),
      ),
      child: Column(
        children: [
          Text(
            'Outstanding Access Balance',
            style: AppTextStyles.small(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),

          SizedBox(height: spacing.sm),

          Text(
            NumberFormatService.formatAmount(
              details.balances.outstandingBalance,
              decimals: 2,
            ),
            style: AppTextStyles.veryLargeNumber(context),
          ),

          SizedBox(height: spacing.lg),

          AppValueRow(
            label: 'Access Balance',
            value: NumberFormatService.formatAmount(
              details.balances.principalBalance,
              decimals: 2,
            ),
          ),

          AppValueRow(
            label: 'Liquidity Fee',
            value: NumberFormatService.formatAmount(
              details.balances.interestBalance,
              decimals: 2,
            ),
            addBottomSpacing: false,
          ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.details});

  final LoanDetails details;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: context.theme.cardColor,
        borderRadius: BorderRadius.circular(context.radius.lg),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Breakdown',
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),

          SizedBox(height: spacing.lg),

          _DebitCreditSection(
            title: 'Access Balance',
            debit: details.totals.debitPrincipal,
            credit: details.totals.creditPrincipal,
          ),

          Divider(height: spacing.lg),

          _DebitCreditSection(
            title: 'Liquidity Fee',
            debit: details.totals.debitInterest,
            credit: details.totals.creditInterest,
          ),
        ],
      ),
    );
  }
}

class _DebitCreditSection extends StatelessWidget {
  const _DebitCreditSection({
    required this.title,
    required this.debit,
    required this.credit,
  });

  final String title;
  final double debit;
  final double credit;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.small(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),

        SizedBox(height: spacing.sm),

        Row(
          children: [
            Expanded(
              child: _AmountColumn(
                label: 'Debit',
                amount: debit,
                color: colorScheme.error,
              ),
            ),

            SizedBox(width: spacing.md),

            Expanded(
              child: _AmountColumn(
                label: 'Credit',
                amount: credit,
                color: Colors.green,
                alignEnd: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AmountColumn extends StatelessWidget {
  const _AmountColumn({
    required this.label,
    required this.amount,
    required this.color,
    this.alignEnd = false,
  });

  final String label;
  final double amount;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),

        SizedBox(height: spacing.xs),

        Text(
          amount == 0
              ? '-'
              : NumberFormatService.formatAmount(amount, decimals: 2),
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: AppTextStyles.smallNumber(context).copyWith(
            color: amount == 0 ? colorScheme.onSurfaceVariant : color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LoanEntryCard extends StatelessWidget {
  const _LoanEntryCard({required this.entry});

  final LoanEntry entry;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;

    final hasPrincipal =
        entry.debitPrincipal != 0 || entry.creditPrincipal != 0;

    final hasInterest = entry.debitInterest != 0 || entry.creditInterest != 0;

    if (!hasPrincipal && !hasInterest) {
      return const SizedBox.shrink();
    }

    final hasDebit = entry.debitPrincipal > 0 || entry.debitInterest > 0;

    final hasCredit = entry.creditPrincipal > 0 || entry.creditInterest > 0;

    final indicatorColor = hasDebit
        ? colorScheme.error
        : hasCredit
        ? Colors.green
        : colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: context.theme.cardColor,
        borderRadius: BorderRadius.circular(context.radius.cardRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: context.iconSize.small,
            height: context.iconSize.small,
            margin: EdgeInsets.only(top: spacing.xs),
            decoration: BoxDecoration(
              color: indicatorColor,
              shape: BoxShape.circle,
            ),
          ),

          SizedBox(width: spacing.md),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        formatTxType(entry.entryType),
                        style: AppTextStyles.small(
                          context,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),

                    SizedBox(width: spacing.sm),

                    Text(
                      DateFormatService.formatDateTime(entry.createdAt),
                      textAlign: TextAlign.right,
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),

                if (hasPrincipal) ...[
                  SizedBox(height: spacing.md),

                  _EntryAmount(
                    label: 'Access Balance',
                    debit: entry.debitPrincipal,
                    credit: entry.creditPrincipal,
                  ),
                ],

                if (hasInterest) ...[
                  SizedBox(height: spacing.md),

                  _EntryAmount(
                    label: 'Liquidity Fee',
                    debit: entry.debitInterest,
                    credit: entry.creditInterest,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryAmount extends StatelessWidget {
  const _EntryAmount({
    required this.label,
    required this.debit,
    required this.credit,
  });

  final String label;
  final double debit;
  final double credit;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;

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

        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (debit > 0)
              Text(
                NumberFormatService.formatAmount(debit, decimals: 2),
                style: AppTextStyles.smallNumber(context).copyWith(
                  color: colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),

            if (debit > 0 && credit > 0) SizedBox(width: spacing.md),

            if (credit > 0)
              Text(
                NumberFormatService.formatAmount(credit, decimals: 2),
                style: AppTextStyles.smallNumber(
                  context,
                ).copyWith(color: Colors.green, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ],
    );
  }
}
