import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/loan/loan_preview.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/wallet/loan/provider/loan_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class LoanPreviewScreen extends ConsumerStatefulWidget {
  const LoanPreviewScreen({super.key, required this.amount});

  final String amount;

  @override
  ConsumerState<LoanPreviewScreen> createState() => _LoanPreviewScreenState();
}

class _LoanPreviewScreenState extends ConsumerState<LoanPreviewScreen> {
  @override
  void initState() {
    super.initState();

    Future.microtask(_loadPreview);
  }

  Future<void> _loadPreview() async {
    final amount = NumberFormatService.anyToDouble(widget.amount.trim());

    final notifier = ref.read(loanTransactionProvider.notifier);

    /*
     * The route amount is the source of truth
     * for the preview being opened.
     *
     * This also protects the screen when it is
     * opened from a route/deep link rather than
     * relying on stale notifier state.
     */
    notifier.updateAmount(amount);

    if (amount <= 0) {
      return;
    }

    await notifier.previewLoan();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final state = ref.watch(loanTransactionProvider);

    final loadingMessage = state.step == BorrowStep.preview
        ? 'Calculating SVA Preview'
        : 'Unlocking SVA';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.lg),
              child: ViewHeader(
                title: 'Secured Value Access Preview',
                onClose: () => _cancel(context),
              ),
            ),
            SizedBox(height: spacing.sm),
            Expanded(child: _buildContent(context, state, loadingMessage)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    dynamic state,
    String loadingMessage,
  ) {
    final spacing = context.spacing;

    if (state.isLoading) {
      return AppLoader(message: loadingMessage, fullScreen: false);
    }

    if (state.error != null) {
      return Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: AppErrorState(title: 'Error', message: state.error!),
      );
    }

    final preview = state.preview;

    if (preview == null) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(spacing.lg),
      child: Column(
        children: [
          _PreviewCard(preview: preview),
          SizedBox(height: spacing.lg),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  text: 'Cancel',
                  isPrimary: false,
                  isDisabled: state.isLoading,
                  onPressed: () => _cancel(context),
                ),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: AppButton(
                  text: 'Access Value',
                  isProcessing: state.isLoading,
                  onPressed: !state.isValid || state.isLoading
                      ? null
                      : _handleBorrow,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _cancel(BuildContext context) {
    ref.read(loanTransactionProvider.notifier).reset();

    context.pop();
  }

  Future<void> _handleBorrow() async {
    final notifier = ref.read(loanTransactionProvider.notifier);

    try {
      await notifier.executeBorrow();

      if (!mounted) {
        return;
      }

      await _showReceipt();

      if (!mounted) {
        return;
      }

      notifier.reset();
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  Future<void> _showReceipt() async {
    final state = ref.read(loanTransactionProvider);

    final preview = state.preview;

    if (preview == null) {
      return;
    }

    await DialogService.paymentReceipt(
      context,
      title: 'Secured Value Access Successful',
      rows: [
        PaymentRow(
          'Amount',
          NumberFormatService.formatUsd(preview.requestedAmount),
          type: PaymentRowType.amount,
        ),
        PaymentRow(
          'Liquidity Initiation Fee',
          NumberFormatService.formatUsd(preview.initiationFee),
          type: PaymentRowType.amount,
        ),
        PaymentRow(
          'Net Access Value',
          NumberFormatService.formatUsd(preview.netDisbursed),
          type: PaymentRowType.amount,
          isBold: true,
        ),
      ],
      onDone: () {},
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});

  final LoanPreview preview;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(context.radius.cardRadius),
        border: Border.all(
          color: context.colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        children: [
          _PreviewRow(
            label: 'Requested',
            value: NumberFormatService.formatUsd(preview.requestedAmount),
          ),
          _PreviewRow(
            label: 'Net',
            value: NumberFormatService.formatUsd(preview.netDisbursed),
          ),
          _PreviewRow(
            label: 'Fee',
            value: NumberFormatService.formatUsd(preview.initiationFee),
          ),
          Divider(height: spacing.lg),
          _PreviewRow(
            label: 'Collateral (g)',
            value: NumberFormatService.formatNumber(
              preview.requiredCollateralGrams,
              decimals: 6,
            ),
          ),
          _PreviewRow(
            label: 'Access Ratio',
            value: '${preview.ltvPercent.toStringAsFixed(2)}%',
          ),
          Divider(height: spacing.lg),
          _PreviewRow(
            label: 'Current Price',
            value: NumberFormatService.formatUsd(preview.marketPricePerGram),
          ),
          _PreviewRow(
            label: 'Rebalancing Threshold',
            value: NumberFormatService.formatUsd(preview.risk.liquidationPrice),
          ),
          _PreviewRow(
            label: 'Health',
            value: preview.risk.healthFactor.toStringAsFixed(2),
          ),
          SizedBox(height: spacing.sm),
          Text(
            'Risk: ${preview.risk.riskLevel}',
            style: AppTextStyles.small(context).copyWith(
              color: _riskColor(context, preview.risk.riskLevel),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Color _riskColor(BuildContext context, String level) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (level.toUpperCase()) {
      case 'LOW':
        return Colors.green;

      case 'MEDIUM':
        return Colors.orange;

      case 'HIGH':
        return colorScheme.error;

      default:
        return colorScheme.onSurfaceVariant;
    }
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
          SizedBox(width: spacing.md),
          Text(
            value,
            textAlign: TextAlign.right,
            style: AppTextStyles.smallNumber(context),
          ),
        ],
      ),
    );
  }
}
