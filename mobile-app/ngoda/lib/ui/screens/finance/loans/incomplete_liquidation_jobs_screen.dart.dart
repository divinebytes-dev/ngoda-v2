import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/loan/liquidation/incomplete_liquidation_jobs.dart';
import 'package:ngoda/data_models/params/loan_liquidation_params.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/finance/providers/incomplete_liquidation_jobs_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_pagination.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class IncompleteLiquidationJobsScreen extends ConsumerStatefulWidget {
  final LoanLiquidationParams params;

  const IncompleteLiquidationJobsScreen({super.key, required this.params});

  @override
  ConsumerState<IncompleteLiquidationJobsScreen> createState() =>
      _IncompleteLiquidationJobsScreenState();
}

class _IncompleteLiquidationJobsScreenState
    extends ConsumerState<IncompleteLiquidationJobsScreen> {
  late int currentPage;
  late int pageSize;

  @override
  void initState() {
    super.initState();

    currentPage = widget.params.page;
    pageSize = widget.params.pageSize;
  }

  LoanLiquidationParams get currentParams {
    return widget.params.copyWith(page: currentPage, pageSize: pageSize);
  }

  Future<void> _refresh() async {
    ref.invalidate(incompleteLiquidationJobsProvider(currentParams));

    await ref.read(incompleteLiquidationJobsProvider(currentParams).future);
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

  void _changePageSize(int newPageSize) {
    setState(() {
      pageSize = newPageSize;
      currentPage = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(
      incompleteLiquidationJobsProvider(currentParams),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Incomplete Transactions',
              onClose: () {
                ref.invalidate(
                  incompleteLiquidationJobsProvider(currentParams),
                );

                context.pop();
              },
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: recordsAsync.when(
                  loading: () => const AppLoader(
                    message: 'Loading incomplete transactions',
                    fullScreen: false,
                  ),
                  error: (error, _) => _RefreshableState(
                    child: AppErrorState(message: error.toString()),
                  ),
                  data: (response) {
                    if (response.error != null) {
                      return _RefreshableState(
                        child: AppErrorState(
                          message: response.error.toString(),
                        ),
                      );
                    }

                    final records = response.result;

                    if (records == null) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _IncompleteTransactionsContent(
                      records: records,
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

class _IncompleteTransactionsContent extends StatelessWidget {
  final IncompleteBlockchainTransactions records;
  final int pageSize;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int> onPageSizeChanged;

  const _IncompleteTransactionsContent({
    required this.records,
    required this.pageSize,
    required this.onPrevious,
    required this.onNext,
    required this.onPageSizeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Column(
      children: [
        Expanded(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              spacing.padding,
              0,
              spacing.padding,
              spacing.padding,
            ),
            children: [
              _SummaryCard(records: records),
              SizedBox(height: spacing.lg),
              _SectionHeader(
                title: 'Incomplete Records',
                trailing: records.pagination.totalEntries.toString(),
              ),
              SizedBox(height: spacing.sm),
              if (records.transactions.isEmpty)
                const AppEmptyState()
              else
                ...records.transactions.map(
                  (record) => Padding(
                    padding: EdgeInsets.only(bottom: spacing.sm),
                    child: _IncompleteTransactionCard(record: record),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              spacing.padding,
              spacing.sm,
              spacing.padding,
              spacing.sm,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: AppPagination(
              page: records.pagination.page,
              totalPages: records.pagination.totalPages,
              totalEntries: records.pagination.totalEntries,
              hasPrevious: records.pagination.hasPrevious,
              hasNext: records.pagination.hasNext,
              onPrevious: onPrevious,
              onNext: onNext,
              entryLabel: 'records',
              pageSize: pageSize,
              onPageSizeChanged: onPageSizeChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IncompleteBlockchainTransactions records;

  const _SummaryCard({required this.records});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    /*
     * These values are calculated from the records
     * currently loaded on this page.
     *
     * The overall record count comes from pagination.
     */
    final blockchainTransactionCount = records.transactions
        .where((record) => record.sourceType == 'blockchain_transaction')
        .length;

    final liquidationJobs = records.transactions
        .where((record) => record.sourceType == 'liquidation_job')
        .toList();

    final liquidationJobCount = liquidationJobs.length;

    final pageLiquidationDebt = liquidationJobs.fold<double>(
      0,
      (total, record) => total + record.totalDebt,
    );

    final pageLiquidationCollateral = liquidationJobs.fold<double>(
      0,
      (total, record) => total + record.collateralRequired,
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.padding),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius.sm),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Incomplete Transaction Summary',
            style: AppTextStyles.medium(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: spacing.padding),

          _SummaryRow(
            label: 'Total Records',
            value: records.totalRecordCount.toString(),
          ),

          SizedBox(height: spacing.sm),

          _SummaryRow(
            label: 'Blockchain Transactions',
            value: blockchainTransactionCount.toString(),
          ),

          SizedBox(height: spacing.sm),

          _SummaryRow(
            label: 'Liquidation Jobs',
            value: liquidationJobCount.toString(),
          ),

          if (liquidationJobCount > 0) ...[
            SizedBox(height: spacing.padding),

            Divider(height: 1, color: colorScheme.outlineVariant),

            SizedBox(height: spacing.padding),

            _SummaryRow(
              label: 'Liquidation Debt',
              value: NumberFormatService.formatAmount(
                pageLiquidationDebt,
                currency: 'usd',
              ),
            ),

            SizedBox(height: spacing.sm),

            _SummaryRow(
              label: 'Collateral Required',
              value:
                  '${NumberFormatService.formatNumber(pageLiquidationCollateral, decimals: 6)} g',
              strong: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _IncompleteTransactionCard extends StatelessWidget {
  final IncompleteTransactionRow record;

  const _IncompleteTransactionCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final errorMessage = record.errorMessage?.trim();

    final isLiquidationJob = record.sourceType == 'liquidation_job';

    final status = record.effectiveStatus ?? 'unknown';

    final title = isLiquidationJob
        ? record.borrowerName
        : _formatTransactionType(record.transactionType);

    final subtitle = isLiquidationJob
        ? 'Liquidation Job'
        : record.description ?? 'Blockchain Transaction';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.padding),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius.sm),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              SizedBox(width: spacing.sm),
              _StatusBadge(status: status),
            ],
          ),

          SizedBox(height: spacing.padding),

          Divider(height: 1, color: colorScheme.outlineVariant),

          SizedBox(height: spacing.padding),

          _DetailRow(label: 'Reference', value: record.effectiveReference),

          SizedBox(height: spacing.sm),

          _DetailRow(
            label: 'Fiscal Period',
            value: '${record.period}/${record.fiscalYear}',
          ),

          SizedBox(height: spacing.sm),

          _DetailRow(
            label: 'Created At',
            value: _formatDateTime(context, record.createdAt),
          ),

          SizedBox(height: spacing.padding),

          if (isLiquidationJob)
            _LiquidationDetails(record: record)
          else
            _BlockchainTransactionDetails(record: record),

          if (errorMessage != null && errorMessage.isNotEmpty) ...[
            SizedBox(height: spacing.padding),
            _ErrorMessage(message: errorMessage),
          ],
        ],
      ),
    );
  }

  String _formatTransactionType(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Blockchain Transaction';
    }

    return value
        .trim()
        .split('_')
        .where((word) => word.isNotEmpty)
        .map(
          (word) =>
              '${word[0].toUpperCase()}'
              '${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _formatDateTime(BuildContext context, DateTime? value) {
    if (value == null) {
      return 'Not available';
    }

    final local = value.toLocal();

    final date = MaterialLocalizations.of(context).formatMediumDate(local);

    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(local));

    return '$date, $time';
  }
}

class _LiquidationDetails extends StatelessWidget {
  final IncompleteTransactionRow record;

  const _LiquidationDetails({required this.record});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Column(
      children: [
        _AmountRow(
          label: 'Principal',
          value: record.totalPrincipal,
          currency: 'usd',
        ),
        SizedBox(height: spacing.sm),
        _AmountRow(
          label: 'Interest',
          value: record.totalInterest,
          currency: 'usd',
        ),
        if (record.penaltyAmount != 0) ...[
          SizedBox(height: spacing.sm),
          _AmountRow(
            label: 'Penalty',
            value: record.penaltyAmount,
            currency: 'usd',
          ),
        ],
        SizedBox(height: spacing.sm),
        _AmountRow(
          label: 'Total Debt',
          value: record.totalDebt,
          currency: 'usd',
          strong: true,
        ),
        SizedBox(height: spacing.padding),
        Divider(height: 1, color: colorScheme.outlineVariant),
        SizedBox(height: spacing.padding),
        _AmountRow(
          label: 'Repayment Required',
          value: record.repaymentRequired,
          currency: 'usd',
        ),
        SizedBox(height: spacing.sm),
        _ValueRow(
          label: 'Collateral Required',
          value:
              '${NumberFormatService.formatNumber(record.collateralRequired, decimals: 6)} g',
        ),
        SizedBox(height: spacing.sm),
        _AmountRow(
          label: 'Gold Price',
          value: record.goldPrice,
          currency: 'usd',
        ),
        if (record.retryCount > 0) ...[
          SizedBox(height: spacing.sm),
          _DetailRow(label: 'Retry Count', value: record.retryCount.toString()),
        ],
        if (record.blockchainQueueId != null) ...[
          SizedBox(height: spacing.sm),
          _DetailRow(label: 'Queue ID', value: record.blockchainQueueId!),
        ],
        if (record.transactionHash != null) ...[
          SizedBox(height: spacing.sm),
          _DetailRow(
            label: 'Transaction Hash',
            value: _shortHash(record.transactionHash!),
          ),
        ],
      ],
    );
  }

  String _shortHash(String value) {
    if (value.length <= 18) {
      return value;
    }

    return '${value.substring(0, 10)}'
        '...'
        '${value.substring(value.length - 8)}';
  }
}

class _BlockchainTransactionDetails extends StatelessWidget {
  final IncompleteTransactionRow record;

  const _BlockchainTransactionDetails({required this.record});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final currency = record.currencyCode ?? '';

    return Column(
      children: [
        _AmountRow(
          label: 'Gross Amount',
          value: record.grossAmount,
          currency: currency,
        ),
        SizedBox(height: spacing.sm),
        _AmountRow(
          label: 'Net Amount',
          value: record.netAmount,
          currency: currency,
        ),
        if (record.feeAmount != 0) ...[
          SizedBox(height: spacing.sm),
          _AmountRow(label: 'Fee', value: record.feeAmount, currency: currency),
        ],
        if (record.quantity > 0) ...[
          SizedBox(height: spacing.sm),
          _ValueRow(
            label: 'Quantity',
            value: NumberFormatService.formatNumber(
              record.quantity,
              decimals: 6,
            ),
          ),
        ],
        if (record.chain != null) ...[
          SizedBox(height: spacing.sm),
          _DetailRow(label: 'Chain', value: record.chain!.toUpperCase()),
        ],
        if (record.transactionHash != null) ...[
          SizedBox(height: spacing.sm),
          _DetailRow(
            label: 'Transaction Hash',
            value: _shortHash(record.transactionHash!),
          ),
        ],
      ],
    );
  }

  String _shortHash(String value) {
    if (value.length <= 18) {
      return value;
    }

    return '${value.substring(0, 10)}'
        '...'
        '${value.substring(value.length - 8)}';
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;

    final color = _statusColor(status);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(radius.sm),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Text(
        _formatStatus(status),
        style: AppTextStyles.tiny(
          context,
        ).copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Color _statusColor(String value) {
    switch (value.trim().toLowerCase()) {
      case 'failed':
      case 'error':
        return Colors.red;

      case 'pending':
      case 'queued':
      case 'processing':
      case 'blockchain_processing':
        return Colors.amber;

      case 'retrying':
        return Colors.orange;

      case 'completed':
      case 'confirmed':
      case 'success':
        return Colors.green;

      default:
        return Colors.grey;
    }
  }

  String _formatStatus(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      return 'Unknown';
    }

    return normalized
        .split('_')
        .map(
          (word) => word.isEmpty
              ? ''
              : '${word[0].toUpperCase()}'
                    '${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}

class _ErrorMessage extends StatelessWidget {
  final String message;

  const _ErrorMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius.sm),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: iconSize.small,
            color: colorScheme.error,
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: colorScheme.error, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
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
    return _ValueRow(
      label: label,
      value: NumberFormatService.formatAmount(value, currency: currency),
      strong: strong,
    );
  }
}

class _ValueRow extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _ValueRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.tiny(context).copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(width: spacing.sm),
        Text(
          value,
          textAlign: TextAlign.end,
          style: strong
              ? AppTextStyles.mediumNumber(
                  context,
                ).copyWith(fontWeight: FontWeight.w700)
              : AppTextStyles.smallNumber(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.tiny(context).copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(width: spacing.sm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            style: AppTextStyles.tiny(
              context,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return _ValueRow(label: label, value: value, strong: strong);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String trailing;

  const _SectionHeader({required this.title, required this.trailing});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
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
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(radius.cardRadius),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.09),
            ),
          ),
          child: Text(
            trailing,
            style: AppTextStyles.tinyNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
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
