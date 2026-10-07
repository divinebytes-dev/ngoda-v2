import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/loan/liquidation/manual_review_liquidation.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/finance/providers/manual_review_liquidation_job_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class ManualReviewLiquidationJobScreen extends ConsumerWidget {
  final String jobId;

  const ManualReviewLiquidationJobScreen({super.key, required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(manualReviewLiquidationJobProvider(jobId));

    Future<void> refresh() async {
      ref.invalidate(manualReviewLiquidationJobProvider(jobId));

      await ref.read(manualReviewLiquidationJobProvider(jobId).future);
    }

    return Scaffold(
      bottomNavigationBar: SafeArea(
        top: false,
        child: _ReconcileCard(jobId: jobId),
      ),
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Manual Review Job',
              onClose: () => context.pop(),
            ),
            Expanded(
              child: asyncData.when(
                loading: () => const AppLoader(message: 'Loading job details'),
                error: (error, _) => AppErrorState(
                  title: 'Manual Review Job',
                  message: error.toString(),
                ),
                data: (response) {
                  if (response.error != null) {
                    return AppErrorState(
                      title: 'Manual Review Job',
                      message: response.error.toString(),
                    );
                  }

                  final detail = response.result;

                  if (detail == null) {
                    return const AppEmptyState();
                  }

                  return _Body(detail: detail, onRefresh: refresh);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final ManualReviewLiquidationDetail detail;
  final Future<void> Function() onRefresh;

  const _Body({required this.detail, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          spacing.padding,
          0,
          spacing.padding,
          spacing.xl,
        ),
        children: [
          _ReviewHeader(detail: detail),

          _space(context),

          _RecommendedActionCard(action: detail.recommendedAction),

          _space(context),

          _SectionCard(
            title: 'Customer',
            icon: Icons.person_outline,
            children: [
              _DetailRow(label: 'Name', value: detail.customer.displayName),
              _DetailRow(
                label: 'Email',
                value: detail.customer.email ?? 'Not available',
              ),
              _DetailRow(
                label: 'Phone',
                value: detail.customer.phone ?? 'Not available',
              ),
              _DetailRow(
                label: 'User ID',
                value: detail.customer.userId,
                compact: true,
              ),
            ],
          ),

          _space(context),

          _SectionCard(
            title: 'Document',
            icon: Icons.description_outlined,
            children: [
              _DetailRow(
                label: 'Document Number',
                value: detail.document.documentNumber ?? 'Not posted',
              ),
              _DetailRow(
                label: 'Fiscal Year',
                value: detail.document.fiscalYear.toString(),
              ),
              _DetailRow(
                label: 'Period',
                value: detail.document.period.toString(),
              ),
              _DetailRow(
                label: 'Country',
                value: detail.document.countryCode.toUpperCase(),
              ),
            ],
          ),

          _space(context),

          _SectionCard(
            title: 'Liquidation Values',
            icon: Icons.account_balance_wallet_outlined,
            children: [
              _AmountDetailRow(
                label: 'Principal',
                value: detail.liquidationValues.principal,
                currency: 'usd',
              ),
              _AmountDetailRow(
                label: 'Interest',
                value: detail.liquidationValues.interest,
                currency: 'usd',
              ),
              _AmountDetailRow(
                label: 'Total Debt',
                value: detail.liquidationValues.totalDebt,
                currency: 'usd',
                strong: true,
              ),
              _AmountDetailRow(
                label: 'Repayment Required',
                value: detail.liquidationValues.repaymentRequired,
                currency: 'usd',
              ),
              _AmountDetailRow(
                label: 'Penalty',
                value: detail.liquidationValues.penaltyAmount,
                currency: 'usd',
              ),
              _AmountDetailRow(
                label: 'Total Proceeds',
                value: detail.liquidationValues.totalProceeds,
                currency: 'usd',
                strong: true,
              ),
              _DetailRow(
                label: 'Collateral Required',
                value: detail.liquidationValues.collateralRequired
                    .toStringAsFixed(6),
              ),
              _AmountDetailRow(
                label: 'Gold Price',
                value: detail.liquidationValues.goldPrice,
                currency: 'usd',
              ),
            ],
          ),

          _space(context),

          _SectionCard(
            title: 'Expected Transfer',
            icon: Icons.swap_horiz_outlined,
            children: [
              _DetailRow(
                label: 'Chain',
                value: _formatStatus(detail.expectedTransfer.chain),
              ),
              _DetailRow(
                label: 'Transaction Type',
                value: _formatStatus(detail.expectedTransfer.transactionType),
              ),
              _AmountDetailRow(
                label: 'Amount',
                value: detail.expectedTransfer.amount,
                currency: detail.expectedTransfer.currencyCode,
                decimals: 6,
                strong: true,
              ),
              _DetailRow(
                label: 'From',
                value: detail.expectedTransfer.fromAddress ?? 'Not available',
                compact: true,
              ),
              _DetailRow(
                label: 'To',
                value: detail.expectedTransfer.toAddress ?? 'Not available',
                compact: true,
              ),
              if (detail.expectedTransfer.rawAmount != null)
                _DetailRow(
                  label: 'Raw Amount',
                  value: detail.expectedTransfer.rawAmount!,
                  compact: true,
                ),
              if (detail.expectedTransfer.permitOwner != null)
                _DetailRow(
                  label: 'Permit Owner',
                  value: detail.expectedTransfer.permitOwner!,
                  compact: true,
                ),
              if (detail.expectedTransfer.permitNonce != null)
                _DetailRow(
                  label: 'Permit Nonce',
                  value: detail.expectedTransfer.permitNonce!,
                ),
              if (detail.expectedTransfer.permitDeadline != null)
                _DetailRow(
                  label: 'Permit Deadline',
                  value: _formatDateTime(
                    detail.expectedTransfer.permitDeadline,
                  ),
                ),
              if (detail.expectedTransfer.permitExpired != null)
                _DetailRow(
                  label: 'Permit Expired',
                  value: detail.expectedTransfer.permitExpired! ? 'Yes' : 'No',
                ),
            ],
          ),

          _space(context),

          _SectionCard(
            title: 'Blockchain Evidence',
            icon: Icons.link,
            children: [
              _DetailRow(
                label: 'Queue Hash',
                value:
                    detail.blockchainEvidence.queueTransactionHash ??
                    'Not available',
                compact: true,
              ),
              _DetailRow(
                label: 'Recorded Hash',
                value:
                    detail.blockchainEvidence.recordedTransactionHash ??
                    'Not available',
                compact: true,
              ),
              _DetailRow(
                label: 'Blockchain Transaction ID',
                value:
                    detail.blockchainEvidence.blockchainTransactionId ??
                    'Not available',
                compact: true,
              ),
              _DetailRow(
                label: 'Transaction Status',
                value: _formatStatus(
                  detail.blockchainEvidence.transactionStatus ?? 'unknown',
                ),
              ),
              _DetailRow(
                label: 'Chain Status',
                value: _formatStatus(
                  detail.blockchainEvidence.chainStatus ?? 'unknown',
                ),
              ),
              _DetailRow(
                label: 'Submitted',
                value: _formatDateTime(detail.blockchainEvidence.submittedAt),
              ),
              _DetailRow(
                label: 'Confirmed',
                value: _formatDateTime(detail.blockchainEvidence.confirmedAt),
              ),
              _DetailRow(
                label: 'Recorded',
                value: _formatDateTime(detail.blockchainEvidence.recordedAt),
              ),
              if (detail.blockchainEvidence.explorerUrl != null)
                _DetailRow(
                  label: 'Explorer',
                  value: detail.blockchainEvidence.explorerUrl!,
                  compact: true,
                ),
            ],
          ),

          _space(context),

          _SectionCard(
            title: 'Processing Status',
            icon: Icons.sync_problem_outlined,
            children: [
              _DetailRow(
                label: 'Job Status',
                value: _formatStatus(detail.status.jobStatus),
              ),
              _DetailRow(
                label: 'Queue Status',
                value: _formatStatus(detail.status.queueStatus),
              ),
              _DetailRow(
                label: 'Attempts',
                value: detail.status.attemptCount.toString(),
              ),
              _DetailRow(
                label: 'Retries',
                value: detail.status.retryCount.toString(),
              ),
              if (detail.status.jobError != null)
                _ErrorMessage(
                  title: 'Job Error',
                  message: detail.status.jobError!,
                ),
              if (detail.status.queueError != null)
                _ErrorMessage(
                  title: 'Queue Error',
                  message: detail.status.queueError!,
                ),
            ],
          ),

          _space(context),

          _SectionCard(
            title: 'Timeline',
            icon: Icons.history_outlined,
            children: [
              _DetailRow(
                label: 'Created',
                value: _formatDateTime(detail.timeline.createdAt),
              ),
              _DetailRow(
                label: 'Processing Started',
                value: _formatDateTime(detail.timeline.processingStartedAt),
              ),
              _DetailRow(
                label: 'Last Attempt',
                value: _formatDateTime(detail.timeline.lastAttemptAt),
              ),
              _DetailRow(
                label: 'Signed',
                value: _formatDateTime(detail.timeline.signedAt),
              ),
              _DetailRow(
                label: 'Claimed',
                value: _formatDateTime(detail.timeline.claimedAt),
              ),
            ],
          ),

          if (detail.verificationRequirements.isNotEmpty) ...[
            _space(context),
            _VerificationRequirements(
              requirements: detail.verificationRequirements,
            ),
          ],
        ],
      ),
    );
  }

  Widget _space(BuildContext context) {
    return SizedBox(height: context.spacing.sm);
  }
}

class _ReviewHeader extends StatelessWidget {
  final ManualReviewLiquidationDetail detail;

  const _ReviewHeader({required this.detail});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.padding),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  detail.customer.displayName,
                  style: AppTextStyles.medium(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _StatusBadge(status: detail.status.queueStatus),
            ],
          ),
          SizedBox(height: spacing.sm),
          _DetailRow(
            label: 'Job ID',
            value: detail.liquidationJobId,
            compact: true,
          ),
          _DetailRow(label: 'Queue ID', value: detail.queueId, compact: true),
          _DetailRow(
            label: 'Manual Review',
            value: detail.manualReviewRequired ? 'Required' : 'Not Required',
          ),
        ],
      ),
    );
  }
}

class _RecommendedActionCard extends StatelessWidget {
  final LiquidationRecommendedAction action;

  const _RecommendedActionCard({required this.action});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final color = _actionColor(action.action);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.padding),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(radius.sm),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recommended Action',
            style: AppTextStyles.tiny(context).copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: spacing.xs),
          Text(
            _actionTitle(action.action),
            style: AppTextStyles.medium(
              context,
            ).copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          if (action.message.trim().isNotEmpty) ...[
            SizedBox(height: spacing.sm),
            Text(action.message, style: AppTextStyles.small(context)),
          ],
          if (action.successResult != null)
            _OutcomeRow(label: 'If successful', value: action.successResult!),
          if (action.notFoundResult != null)
            _OutcomeRow(label: 'If not found', value: action.notFoundResult!),
          if (action.uncertainResult != null)
            _OutcomeRow(label: 'If uncertain', value: action.uncertainResult!),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

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
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: iconSize.small, color: colorScheme.primary),
              SizedBox(width: spacing.sm),
              Text(
                title,
                style: AppTextStyles.small(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool compact;

  const _DetailRow({
    required this.label,
    required this.value,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: AppTextStyles.tiny(context).copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: compact ? 2 : null,
              overflow: compact ? TextOverflow.ellipsis : null,
              style: compact
                  ? AppTextStyles.tinyNumber(
                      context,
                    ).copyWith(fontWeight: FontWeight.w600)
                  : AppTextStyles.tiny(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountDetailRow extends StatelessWidget {
  final String label;
  final double value;
  final String currency;
  final bool strong;
  final int decimals;

  const _AmountDetailRow({
    required this.label,
    required this.value,
    required this.currency,
    this.strong = false,
    this.decimals = 2,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Row(
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
              decimals: decimals,
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
      ),
    );
  }
}

class _VerificationRequirements extends StatelessWidget {
  final List<String> requirements;

  const _VerificationRequirements({required this.requirements});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return _SectionCard(
      title: 'Verification Requirements',
      icon: Icons.fact_check_outlined,
      children: requirements.map((requirement) {
        return Padding(
          padding: EdgeInsets.only(bottom: spacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: iconSize.small,
                color: colorScheme.primary,
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Text(requirement, style: AppTextStyles.tiny(context)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  final String title;
  final String message;

  const _ErrorMessage({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: spacing.sm),
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: colorScheme.error, fontWeight: FontWeight.w700),
          ),
          Text(
            message,
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: colorScheme.error),
          ),
        ],
      ),
    );
  }
}

class _OutcomeRow extends StatelessWidget {
  final String label;
  final String value;

  const _OutcomeRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: context.spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: AppTextStyles.tiny(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          Expanded(child: Text(value, style: AppTextStyles.tiny(context))),
        ],
      ),
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

Color _statusColor(String value) {
  switch (value.trim().toLowerCase()) {
    case 'pending':
      return Colors.amber;

    case 'processing':
      return Colors.blue;

    case 'failed':
      return Colors.red;

    case 'confirmed':
    case 'completed':
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

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return 'Not available';
  }

  final local = value.toLocal();

  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');

  return '$day/$month/${local.year} '
      '$hour:$minute';
}

class _ReconcileCard extends ConsumerWidget {
  final String jobId;

  const _ReconcileCard({required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.padding,
        vertical: spacing.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () async {
            await context.push(
              '/finance-loans/'
              'manual-review-liquidation-jobs/'
              'job/reconcile',
              extra: jobId,
            );

            ref.invalidate(manualReviewLiquidationJobProvider(jobId));
          },
          icon: const Icon(Icons.sync_outlined),
          label: const Text('Reconcile Transaction'),
        ),
      ),
    );
  }
}
