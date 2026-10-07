import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/data_models/treasury/token_adjustment.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/string_extension.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/accounts/notifier/accounts_transaction_notifier.dart';
import 'package:ngoda/ui/screens/accounts/providers/accounts_transaction_provider.dart';
import 'package:ngoda/ui/screens/accounts/providers/token_adjustment_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class ApproveTokenAdjustmentScreen extends ConsumerStatefulWidget {
  const ApproveTokenAdjustmentScreen({super.key});

  @override
  ConsumerState<ApproveTokenAdjustmentScreen> createState() =>
      _ApproveTokenAdjustmentScreenState();
}

class _ApproveTokenAdjustmentScreenState
    extends ConsumerState<ApproveTokenAdjustmentScreen> {
  static const String _status = 'pending';

  Future<void> _refresh() async {
    ref.invalidate(tokenAdjustmentProvider(_status));

    await ref.read(tokenAdjustmentProvider(_status).future);
  }

  @override
  Widget build(BuildContext context) {
    final asyncAdjustment = ref.watch(tokenAdjustmentProvider(_status));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Approve Tokens Adjustment',
              onClose: () => context.pop(),
            ),
            Expanded(
              child: asyncAdjustment.when(
                loading: () => const AppLoader(
                  message: 'Loading token adjustment request',
                  fullScreen: false,
                ),
                error: (error, _) {
                  return AppErrorState(message: error.toString());
                },
                data: (response) {
                  if (response.error != null) {
                    if (response.error!.contains('NO_DATA')) {
                      return _EmptyAdjustment(onRefresh: _refresh);
                    }

                    return AppErrorState(message: response.error);
                  }

                  final adjustment = response.result;

                  if (adjustment == null) {
                    return _EmptyAdjustment(onRefresh: _refresh);
                  }

                  return TokenAdjustmentBody(
                    adjustment: adjustment,
                    onRefresh: _refresh,
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

class _EmptyAdjustment extends StatelessWidget {
  const _EmptyAdjustment({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(spacing.lg),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.55,
            child: const AppEmptyState(
              message: 'No pending token adjustment request.',
            ),
          ),
        ],
      ),
    );
  }
}

class TokenAdjustmentBody extends ConsumerWidget {
  const TokenAdjustmentBody({
    required this.adjustment,
    required this.onRefresh,
    super.key,
  });

  final TokenAdjustment adjustment;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;

    final current = adjustment.currentCoveragePercent;

    final projected = adjustment.projectedCoveragePercent;

    final isSafe = adjustment.isSafeAfterApproval;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Stack(
        children: [
          SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              spacing.md,
              spacing.md,
              spacing.md,
              spacing.xxxxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CoverageInsight(
                  current: current,
                  projected: projected,
                  isSafe: isSafe,
                ),
                SizedBox(height: spacing.md),
                _DetailsCard(adjustment),
                SizedBox(height: spacing.md),
                _StateCard(
                  title: 'Current State',
                  gold: adjustment.availableGold,
                  tokens: adjustment.totalTokens,
                  coverage: current,
                  isSafe: true,
                  isCurrent: true,
                ),
                SizedBox(height: spacing.md),
                _StateCard(
                  title: 'After Approval',
                  gold: adjustment.projectedGold,
                  tokens: adjustment.projectedTokens,
                  coverage: projected,
                  isSafe: isSafe,
                  isCurrent: false,
                ),
                if (!isSafe) ...[
                  SizedBox(height: spacing.md),
                  const _WarningCard(),
                ],
              ],
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _StickyActions(
              adjustment: adjustment,
              onCompleted: onRefresh,
            ),
          ),
        ],
      ),
    );
  }
}

class _StickyActions extends ConsumerWidget {
  const _StickyActions({required this.adjustment, required this.onCompleted});

  final TokenAdjustment adjustment;
  final Future<void> Function() onCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final state = ref.watch(accountsTransactionProvider);

    final notifier = ref.read(accountsTransactionProvider.notifier);

    Future<void> process(String status) async {
      final completed = await _handleApprove(
        context,
        notifier,
        adjustment,
        status,
      );

      if (completed) {
        await onCompleted();
      }
    }

    return Container(
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: AppButton(
                text: 'Reject',
                isPrimary: false,
                isDisabled: state.isLoading,
                onPressed: state.isLoading ? null : () => process('reject'),
              ),
            ),
            SizedBox(width: spacing.sm),
            Expanded(
              child: AppButton(
                text: 'Approve',
                isDisabled: state.isLoading,
                isProcessing: state.isLoading,
                onPressed: state.isLoading ? null : () => process('approve'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> _handleApprove(
  BuildContext context,
  AccountsTransactionNotifier notifier,
  TokenAdjustment adjustment,
  String status,
) async {
  try {
    final confirmed = await _confirm(
      context,
      adjustment.adjustmentType,
      adjustment.quantity,
      adjustment.uom,
    );

    if (confirmed != true) {
      return false;
    }

    await notifier.appoveTokenAdjustment(id: adjustment.id, status: status);

    if (!context.mounted) {
      return false;
    }

    await DialogService.success(
      context,
      message:
          'Token Adjustment '
          '${status.capitalize()}ed Successfully',
    );

    return true;
  } catch (error) {
    if (!context.mounted) {
      return false;
    }

    await DialogService.error(context, message: error.toString());

    return false;
  }
}

class _CoverageInsight extends StatelessWidget {
  const _CoverageInsight({
    required this.current,
    required this.projected,
    required this.isSafe,
  });

  final double current;
  final double projected;
  final bool isSafe;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
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
            'Coverage Impact',
            style: AppTextStyles.medium(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: spacing.sm),
          Row(
            children: [
              Expanded(
                child: _CoverageMetric(
                  label: 'Before',
                  value: current,
                  color: colorScheme.primary,
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.sm),
                child: Icon(
                  Icons.arrow_forward,
                  size: iconSize.small,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: _CoverageMetric(
                  label: 'After',
                  value: projected,
                  color: isSafe ? colorScheme.primary : colorScheme.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoverageMetric extends StatelessWidget {
  const _CoverageMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Column(
      children: [
        Text(label, style: AppTextStyles.small(context)),
        SizedBox(height: spacing.xs),
        Text(
          '${value.toStringAsFixed(1)}%',
          style: AppTextStyles.mediumNumber(context).copyWith(color: color),
        ),
      ],
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.title,
    required this.gold,
    required this.tokens,
    required this.coverage,
    required this.isSafe,
    required this.isCurrent,
  });

  final String title;
  final double gold;
  final double tokens;
  final double coverage;
  final bool isSafe;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final statusColor = isCurrent || isSafe
        ? colorScheme.primary
        : colorScheme.error;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(color: statusColor.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: spacing.sm),
          AppValueRow(
            label: 'Gold Reserve',
            value: NumberFormatService.formatNumber(gold),
          ),
          AppValueRow(
            label: 'Token Supply',
            value: NumberFormatService.formatNumber(tokens),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${coverage.toStringAsFixed(2)}%',
              style: AppTextStyles.mediumNumber(
                context,
              ).copyWith(color: statusColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard();

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: iconSize.small,
            color: colorScheme.error,
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Text(
              'This adjustment will result in '
              'under-collateralization '
              '(coverage < 100%).',
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard(this.adjustment);

  final TokenAdjustment adjustment;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          AppValueRow(label: 'Type', value: adjustment.adjustmentType),
          AppValueRow(
            label: 'Quantity',
            value:
                '${NumberFormatService.formatNumber(adjustment.quantity)} '
                '${adjustment.uom}',
            addBottomSpacing: adjustment.description != null,
          ),
          if (adjustment.description != null)
            AppValueRow(
              label: 'Description',
              value: adjustment.description!,
              addBottomSpacing: false,
            ),
        ],
      ),
    );
  }
}

Future<bool?> _confirm(
  BuildContext context,
  String type,
  double quantity,
  String uom,
) {
  return DialogService.paymentConfirmation(
    context,
    title: 'Confirm Token Adjustment',
    rows: [
      PaymentRow(
        type.capitalize(),
        '${NumberFormatService.formatNumber(quantity)} '
        '$uom',
      ),
    ],
  );
}
