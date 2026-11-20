import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/data_models/transaction/transaction_data.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/functions/get_signed_transaction.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/wallet_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class ProcessCommissionWithdrawalScreen extends ConsumerStatefulWidget {
  final TransactionData? transactionData;

  const ProcessCommissionWithdrawalScreen({super.key, this.transactionData});

  @override
  ConsumerState<ProcessCommissionWithdrawalScreen> createState() =>
      _ProcessCommissionWithdrawalScreenState();
}

class _ProcessCommissionWithdrawalScreenState
    extends ConsumerState<ProcessCommissionWithdrawalScreen> {
  final amountCtrl = TextEditingController();
  final feeCtrl = TextEditingController();
  final taxCtrl = TextEditingController();
  final userIdCtrl = TextEditingController();

  bool _isSubmitting = false;
  double? _amount;
  double? _fee;
  double? _tax;
  String? _currencyCode;

  @override
  void initState() {
    super.initState();

    final data = widget.transactionData;

    if (data == null ||
        data.v != "v10" ||
        data.a <= 0 ||
        data.f < 0 ||
        data.g < 0 ||
        data.c.trim().isEmpty ||
        data.c.trim().toLowerCase() == 'gold' ||
        data.r.trim().isEmpty ||
        data.s.trim().isEmpty) {
      return;
    }

    _amount = data.a / 100;
    _fee = data.f / 100;
    _tax = data.g / 100;
    _currencyCode = data.c;

    amountCtrl.text = NumberFormatService.formatAmount(
      _amount!,
      currency: data.c,
    );

    feeCtrl.text = NumberFormatService.formatAmount(_fee!, currency: data.c);

    taxCtrl.text = NumberFormatService.formatAmount(_tax!, currency: data.c);

    userIdCtrl.text = data.s;
  }

  @override
  void dispose() {
    amountCtrl.dispose();
    feeCtrl.dispose();
    taxCtrl.dispose();
    userIdCtrl.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final state = ref.watch(walletTransactionProvider);
    final submitting = _isSubmitting || state.isLoading;

    if (widget.transactionData == null ||
        _amount == null ||
        _fee == null ||
        _tax == null ||
        _currencyCode == null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(spacing.md),
            child: Column(
              children: [
                ViewHeader(
                  title: 'Commission Withdrawal',
                  subtitle: 'Review the scanned withdrawal',
                  onClose: () {
                    if (!submitting) {
                      _closeScreen();
                    }
                  },
                ),

                Expanded(
                  child: Center(
                    child: Text(
                      'Scan a valid commission withdrawal QR.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(color: colorScheme.error),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusScope.of(context).unfocus();
          },
          child: Padding(
            padding: EdgeInsets.all(spacing.md),
            child: Column(
              children: [
                ViewHeader(
                  title: 'Commission Withdrawal',
                  subtitle: 'Review the scanned withdrawal',
                  onClose: () {
                    if (!submitting) {
                      _closeScreen();
                    }
                  },
                ),

                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      children: [
                        SizedBox(height: spacing.md),

                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(spacing.md),
                          decoration: BoxDecoration(
                            color: context.theme.cardColor,
                            borderRadius: BorderRadius.circular(radius.md),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.shadow.withValues(
                                  alpha: 0.05,
                                ),
                                blurRadius: spacing.lg,
                                offset: Offset(0, spacing.sm),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InputField(
                                controller: userIdCtrl,
                                readOnly: true,
                                placeholder: 'User',
                              ),

                              SizedBox(height: spacing.md),

                              InputField(
                                controller: amountCtrl,
                                readOnly: true,
                                placeholder: 'Amount',
                              ),

                              SizedBox(height: spacing.md),

                              InputField(
                                controller: feeCtrl,
                                readOnly: true,
                                placeholder: 'Fee',
                              ),

                              SizedBox(height: spacing.md),

                              InputField(
                                controller: taxCtrl,
                                readOnly: true,
                                placeholder: 'Tax',
                              ),

                              if (state.error != null &&
                                  state.error!.trim().isNotEmpty) ...[
                                SizedBox(height: spacing.sm),

                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    state.error!,
                                    style: AppTextStyles.tiny(
                                      context,
                                    ).copyWith(color: colorScheme.error),
                                  ),
                                ),
                              ],

                              SizedBox(height: spacing.lg),

                              _buildCalculation(),

                              SizedBox(height: spacing.lg),

                              Row(
                                children: [
                                  Expanded(
                                    child: AppButton(
                                      text: 'Cancel',
                                      isPrimary: false,
                                      isDisabled: submitting,
                                      onPressed: submitting
                                          ? null
                                          : _closeScreen,
                                    ),
                                  ),

                                  SizedBox(width: spacing.md),

                                  Expanded(
                                    child: AppButton(
                                      text: 'Process Withdrawal',
                                      isProcessing: submitting,
                                      onPressed: submitting
                                          ? null
                                          : _processWithdrawal,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: spacing.md),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalculation() {
    final amount = _amount!;
    final fee = _fee!;
    final tax = _tax!;
    final currency = _currencyCode!;

    final total = amount + fee + tax;

    return PaymentCalculationCard(
      children: [
        AppValueRow(
          label: 'Amount',
          value: NumberFormatService.formatAmount(amount, currency: currency),
          addBottomSpacing: false,
        ),

        SizedBox(height: context.spacing.sm),

        AppValueRow(
          label: 'Fee',
          value: NumberFormatService.formatAmount(fee, currency: currency),
          addBottomSpacing: false,
        ),

        SizedBox(height: context.spacing.sm),

        AppValueRow(
          label: 'Tax',
          value: NumberFormatService.formatAmount(tax, currency: currency),
          addBottomSpacing: false,
        ),

        Padding(
          padding: EdgeInsets.symmetric(vertical: context.spacing.sm),
          child: const Divider(),
        ),

        AppValueRow(
          label: 'Total',
          value: NumberFormatService.formatAmount(total, currency: currency),
          valueStyle: AppTextStyles.smallNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
          addBottomSpacing: false,
        ),
      ],
    );
  }

  Future<void> _processWithdrawal() async {
    final transaction = widget.transactionData;

    if (_isSubmitting || transaction == null || _amount == null) {
      return;
    }

    final user = getCurrentUser();
    final userId = user.userId;
    if (user.role != 'office' || userId == null) {
      await DialogService.error(
        context,
        message: 'You are not authorized to process commission withdrawals.',
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final signedTransaction = await getSignedTransaction(
        v: transaction.v,
        reference: transaction.r,
        identifier: userId,
        amount: _amount!,
        currency: transaction.c,
      );

      if (!mounted) {
        return;
      }

      await ref
          .read(walletTransactionProvider.notifier)
          .processCommissionWithdrawal(
            transaction: transaction,
            approval: signedTransaction.senderApproval,
          );

      if (!mounted) {
        return;
      }

      await showReceipt();
      if (mounted) {
        _closeScreen();
      }
    } catch (error) {
      if (mounted) {
        await DialogService.error(context, message: error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> showReceipt() async {
    final amount = _amount!;
    final fee = _fee!;
    final tax = _tax!;
    final currency = _currencyCode!;

    final total = amount + fee + tax;

    final screenRoute = ModalRoute.of(context);

    await DialogService.paymentReceipt(
      context,
      title: 'Commission Withdrawal Successful',
      rows: [
        PaymentRow(
          'Amount',
          NumberFormatService.formatAmount(amount, currency: currency),
          type: PaymentRowType.amount,
        ),

        PaymentRow(
          'Fee',
          NumberFormatService.formatAmount(fee, currency: currency),
          type: PaymentRowType.amount,
        ),

        PaymentRow(
          'Tax',
          NumberFormatService.formatAmount(tax, currency: currency),
          type: PaymentRowType.amount,
        ),

        PaymentRow(
          'Total',
          NumberFormatService.formatAmount(total, currency: currency),
          type: PaymentRowType.amount,
          isBold: true,
        ),
      ],
      onDone: () {},
    );

    await WidgetsBinding.instance.endOfFrame;

    while (mounted && screenRoute != null && !screenRoute.isCurrent) {
      await WidgetsBinding.instance.endOfFrame;
    }

    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  void _closeScreen() {
    if (!mounted) {
      return;
    }

    FocusScope.of(context).unfocus();

    if (context.canPop()) {
      context.pop();
    }
  }
}
