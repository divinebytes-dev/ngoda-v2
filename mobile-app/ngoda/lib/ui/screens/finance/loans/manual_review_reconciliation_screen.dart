import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/finance/providers/finance_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class ReconcileManualReviewLiquidationJobScreen extends ConsumerStatefulWidget {
  final String jobId;

  const ReconcileManualReviewLiquidationJobScreen({
    super.key,
    required this.jobId,
  });

  @override
  ConsumerState<ReconcileManualReviewLiquidationJobScreen> createState() =>
      _ReconcileManualReviewLiquidationJobScreenState();
}

class _ReconcileManualReviewLiquidationJobScreenState
    extends ConsumerState<ReconcileManualReviewLiquidationJobScreen> {
  final _formKey = GlobalKey<FormState>();

  final _txHashController = TextEditingController();

  final _txHashFocusNode = FocusNode();

  bool _hasValidTxHash = false;

  @override
  void dispose() {
    _txHashController.dispose();
    _txHashFocusNode.dispose();

    super.dispose();
  }

  bool _isValidTransactionHash(String txHash) {
    return RegExp(r'^0x[a-fA-F0-9]{64}$').hasMatch(txHash.trim());
  }

  void _updateTxHashState(String value) {
    final isValid = _isValidTransactionHash(value);

    if (!mounted) {
      return;
    }

    if (isValid == _hasValidTxHash) {
      return;
    }

    setState(() {
      _hasValidTxHash = isValid;
    });
  }

  String? _validateTransactionHash(String? value) {
    final txHash = value?.trim() ?? '';

    if (txHash.isEmpty) {
      return 'Transaction hash is required';
    }

    if (!_isValidTransactionHash(txHash)) {
      return 'Enter a valid transaction hash';
    }

    return null;
  }

  Future<void> _pasteTransactionHash() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);

    final value = clipboardData?.text?.trim();

    if (value == null || value.isEmpty) {
      _txHashController.clear();
      _updateTxHashState('');

      return;
    }

    _txHashController.text = value;

    _txHashController.selection = TextSelection.collapsed(offset: value.length);

    _updateTxHashState(value);
  }

  Future<void> _reconcile() async {
    FocusScope.of(context).unfocus();

    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final txHash = _txHashController.text.trim();

    final notifier = ref.read(financeTransactionProvider.notifier);

    try {
      await notifier.reconcilManualReviewLiquidationJob(
        jobId: widget.jobId,
        txHash: txHash,
      );

      if (!mounted) {
        return;
      }

      await DialogService.success(
        context,
        message: 'Liquidation job reconciled successfully',
      );

      if (!mounted) {
        return;
      }

      context.pop();
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    } finally {
      notifier.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final transactionState = ref.watch(financeTransactionProvider);

    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final canReconcile = _hasValidTxHash && !transactionState.isLoading;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Reconcile Liquidation',
              onClose: () {
                context.pop();
              },
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  spacing.padding,
                  spacing.sm,
                  spacing.padding,
                  spacing.xl,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InformationCard(jobId: widget.jobId),
                      SizedBox(height: spacing.lg),
                      Text(
                        'Transaction Hash',
                        style: AppTextStyles.small(
                          context,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        'Paste the verified blockchain '
                        'transaction hash below.',
                        style: AppTextStyles.tiny(
                          context,
                        ).copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      SizedBox(height: spacing.sm),
                      TextFormField(
                        controller: _txHashController,
                        focusNode: _txHashFocusNode,
                        readOnly: true,
                        enabled: !transactionState.isLoading,
                        validator: _validateTransactionHash,
                        autocorrect: false,
                        enableSuggestions: false,
                        textCapitalization: TextCapitalization.none,
                        minLines: 2,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Transaction hash',
                          hintText: 'Paste transaction hash',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(radius.sm),
                          ),
                          suffixIcon: IconButton(
                            tooltip: 'Paste transaction hash',
                            onPressed: transactionState.isLoading
                                ? null
                                : _pasteTransactionHash,
                            icon: const Icon(Icons.content_paste_outlined),
                          ),
                        ),
                      ),
                      SizedBox(height: spacing.sm),
                      Text(
                        'The hash must belong to the '
                        'transaction verified for this '
                        'liquidation job.',
                        style: AppTextStyles.tiny(
                          context,
                        ).copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
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
            child: AppButton(
              text: 'Reconcile',
              isProcessing: transactionState.isLoading,
              isDisabled: !canReconcile,
              onPressed: canReconcile ? _reconcile : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _InformationCard extends StatelessWidget {
  final String jobId;

  const _InformationCard({required this.jobId});

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
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.sync_problem_outlined,
                size: iconSize.small,
                color: colorScheme.primary,
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Text(
                  'Manual Reconciliation',
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Text(
            'Enter the blockchain transaction '
            'hash that has been verified for '
            'this liquidation job.',
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: spacing.padding),
          Text(
            'Job ID',
            style: AppTextStyles.tiny(context).copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: spacing.xs),
          SelectableText(
            jobId,
            style: AppTextStyles.tinyNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
