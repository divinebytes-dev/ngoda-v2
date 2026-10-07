import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/loan/liquidation/manual_review_liquidation.dart';
import 'package:ngoda/data_models/params/loan_liquidation_params.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/finance/providers/manual_review_liquidation_jobs_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_pagination.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class ManualReviewLiquidationJobsScreen extends ConsumerStatefulWidget {
  final LoanLiquidationParams params;

  const ManualReviewLiquidationJobsScreen({super.key, required this.params});

  @override
  ConsumerState<ManualReviewLiquidationJobsScreen> createState() =>
      _ManualReviewLiquidationJobsScreenState();
}

class _ManualReviewLiquidationJobsScreenState
    extends ConsumerState<ManualReviewLiquidationJobsScreen> {
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
    ref.invalidate(manualReviewLiquidationJobsProvider(currentParams));

    await ref.read(manualReviewLiquidationJobsProvider(currentParams).future);
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

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(
      manualReviewLiquidationJobsProvider(currentParams),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Manual Review Liquidations',
              onClose: () {
                context.pop();
              },
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: asyncData.when(
                  loading: () => const AppLoader(
                    message: 'Loading liquidation jobs',
                    fullScreen: false,
                  ),
                  error: (error, _) {
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

                    final data = response.result;

                    if (data == null) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _Content(
                      data: data,
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

class _Content extends StatelessWidget {
  final ManualReviewLiquidations data;
  final int pageSize;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int> onPageSizeChanged;

  const _Content({
    required this.data,
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
              spacing.lg,
            ),
            children: [
              _SummaryCard(data: data),
              SizedBox(height: spacing.lg),
              _SectionHeader(
                title: 'Jobs Requiring Review',
                trailing: data.pagination.totalEntries.toString(),
              ),
              SizedBox(height: spacing.sm),
              if (data.rows.isEmpty)
                const AppEmptyState()
              else
                ...data.rows.map(
                  (job) => Padding(
                    padding: EdgeInsets.only(bottom: spacing.sm),
                    child: _JobCard(job: job),
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
              page: data.pagination.page,
              totalPages: data.pagination.totalPages,
              totalEntries: data.pagination.totalEntries,
              hasPrevious: data.pagination.hasPrevious,
              hasNext: data.pagination.hasNext,
              onPrevious: onPrevious,
              onNext: onNext,
              entryLabel: 'jobs',
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
  final ManualReviewLiquidations data;

  const _SummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.padding),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius.sm),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Manual Review',
                  style: AppTextStyles.medium(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(
                Icons.manage_search_outlined,
                size: iconSize.small,
                color: colorScheme.primary,
              ),
            ],
          ),
          SizedBox(height: spacing.lg),
          _SummaryRow(
            label: 'Total Jobs',
            value: data.pagination.totalEntries.toString(),
          ),
          SizedBox(height: spacing.sm),
          _SummaryRow(
            label: 'Verify On Chain',
            value: data
                .countForAction(ManualReviewAction.verifyOnChain)
                .toString(),
          ),
        ],
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final ManualReviewLiquidationRow job;

  const _JobCard({required this.job});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final error = job.errorMessage?.trim();

    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(radius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius.cardRadius),
        onTap: () {
          context.push(
            '/finance-loans/manual-review-liquidation-jobs/job',
            extra: job.liquidationJobId,
          );
        },
        child: Padding(
          padding: EdgeInsets.all(spacing.padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.borrowerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.medium(
                            context,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (job.email != null || job.phone != null) ...[
                          SizedBox(height: spacing.xs),
                          Text(
                            job.email ?? job.phone ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.tiny(
                              context,
                            ).copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  _StatusBadge(status: job.queueStatus),
                ],
              ),
              SizedBox(height: spacing.padding),
              _AmountRow(
                label: 'Amount',
                value: job.amount,
                currency: job.currencyCode,
                strong: true,
              ),
              SizedBox(height: spacing.sm),
              _InfoRow(
                label: 'Document',
                value: job.documentNumber ?? 'Not posted',
              ),
              SizedBox(height: spacing.sm),
              _InfoRow(
                label: 'Period',
                value: '${job.period}/${job.fiscalYear}',
              ),
              SizedBox(height: spacing.sm),
              _InfoRow(
                label: 'Job Status',
                value: _formatStatus(job.jobStatus),
              ),
              SizedBox(height: spacing.sm),
              _InfoRow(
                label: 'Attempts',
                value: '${job.attemptCount} / Retries ${job.retryCount}',
              ),
              SizedBox(height: spacing.padding),
              _ActionBox(
                action: job.recommendedAction,
                message: job.actionMessage,
              ),
              if (job.transactionHash != null) ...[
                SizedBox(height: spacing.sm),
                _HashRow(hash: job.transactionHash!),
              ],
              if (error != null && error.isNotEmpty) ...[
                SizedBox(height: spacing.sm),
                _ErrorMessage(message: error),
              ],
              SizedBox(height: spacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Review job',
                    style: AppTextStyles.tiny(context).copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: spacing.xs),
                  Icon(
                    Icons.chevron_right,
                    size: iconSize.small,
                    color: colorScheme.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBox extends StatelessWidget {
  final ManualReviewAction action;
  final String message;

  const _ActionBox({required this.action, required this.message});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final color = _actionColor(action);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius.sm),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _actionTitle(action),
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          if (message.trim().isNotEmpty) ...[
            SizedBox(height: spacing.xs),
            Text(
              message,
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _HashRow extends StatelessWidget {
  final String hash;

  const _HashRow({required this.hash});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Row(
      children: [
        Icon(
          Icons.link,
          size: iconSize.small,
          color: colorScheme.onSurfaceVariant,
        ),
        SizedBox(width: spacing.xs),
        Expanded(
          child: Text(
            hash,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.tinyNumber(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  final String message;

  const _ErrorMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius.sm),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.15)),
      ),
      child: Text(
        message,
        style: AppTextStyles.tiny(
          context,
        ).copyWith(color: colorScheme.error, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
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
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTextStyles.tiny(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
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
        Text(
          NumberFormatService.formatAmount(
            value,
            currency: currency,
            decimals: 6,
          ),
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

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
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
        Text(
          value,
          style: AppTextStyles.mediumNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
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
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String trailing;

  const _SectionHeader({required this.title, required this.trailing});

  @override
  Widget build(BuildContext context) {
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
        Text(
          trailing,
          style: AppTextStyles.tinyNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

Color _statusColor(String value) {
  switch (value.trim().toLowerCase()) {
    case 'pending':
      return Colors.amber;

    case 'processing':
      return Colors.blue;

    case 'failed':
      return Colors.red;

    case 'completed':
    case 'confirmed':
    case 'posted':
      return Colors.green;

    default:
      return Colors.grey;
  }
}

Color _actionColor(ManualReviewAction action) {
  switch (action) {
    case ManualReviewAction.verifyOnChain:
      return Colors.orange;

    case ManualReviewAction.verifyStoredTransaction:
      return Colors.blue;

    case ManualReviewAction.resumeAccounting:
      return Colors.green;

    case ManualReviewAction.unknown:
      return Colors.grey;
  }
}

String _actionTitle(ManualReviewAction action) {
  switch (action) {
    case ManualReviewAction.verifyOnChain:
      return 'Verify On Chain';

    case ManualReviewAction.verifyStoredTransaction:
      return 'Verify Stored Transaction';

    case ManualReviewAction.resumeAccounting:
      return 'Resume Accounting';

    case ManualReviewAction.unknown:
      return 'Manual Review';
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
