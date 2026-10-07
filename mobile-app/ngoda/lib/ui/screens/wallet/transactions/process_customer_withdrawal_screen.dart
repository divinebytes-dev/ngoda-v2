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
import 'package:ngoda/ui/functions/get_wallet_balances.dart';
import 'package:ngoda/ui/functions/refresh_user_dashboard.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/wallet_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class ProcessUserWithdrawalScreen extends ConsumerStatefulWidget {
  final TransactionData? transactionData;

  const ProcessUserWithdrawalScreen({super.key, this.transactionData});

  @override
  ConsumerState<ProcessUserWithdrawalScreen> createState() =>
      _ProcessUserWithdrawalScreenState();
}

class _ProcessUserWithdrawalScreenState
    extends ConsumerState<ProcessUserWithdrawalScreen> {
  final amountCtrl = TextEditingController();
  final feeCtrl = TextEditingController();
  final taxCtrl = TextEditingController();
  final userIdCtrl = TextEditingController();

  double? _amount;
  double? _fee;
  double? _tax;
  String? _currencyCode;

  @override
  void initState() {
    super.initState();

    final data = widget.transactionData;

    if (data == null) {
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ref.read(walletTransactionProvider.notifier).initReference();
    });
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
                  title: 'User Withdrawal',
                  subtitle: 'Process user withdrawal securely',
                  onClose: _closeScreen,
                ),

                Expanded(
                  child: Center(
                    child: Text(
                      'Withdrawal details are not available',
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
                  title: 'User Withdrawal',
                  subtitle: 'Process user withdrawal securely',
                  onClose: _closeScreen,
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
                                      isDisabled: state.isLoading,
                                      onPressed: _closeScreen,
                                    ),
                                  ),

                                  SizedBox(width: spacing.md),

                                  Expanded(
                                    child: AppButton(
                                      text: 'Withdraw',
                                      isProcessing: state.isLoading,
                                      onPressed: state.isLoading
                                          ? null
                                          : handleUserWithdrawal,
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

  Future<void> handleUserWithdrawal() async {
    final transaction = widget.transactionData;

    if (transaction == null || _amount == null) {
      return;
    }

    try {
      final user = getCurrentUser();

      final signedTransaction = await getSignedTransaction(
        v: transaction.v,
        reference: transaction.r,
        identifier: user.userId!,
        amount: _amount!,
        currency: transaction.c,
      );

      final notifier = ref.read(walletTransactionProvider.notifier);

      await notifier.processUserWithdrawal(
        transaction: transaction,
        approval: signedTransaction.senderApproval,
        isCreditAgent: isCreditAgent(ref),
      );

      refreshUserDashboard(ref);

      if (!mounted) {
        return;
      }

      await showReceipt();

      if (!mounted) {
        return;
      }

      _resetTransaction();
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());

      if (!mounted) {
        return;
      }

      /*
       * Preserve the existing behaviour:
       * processing errors close this screen.
       */
      _resetTransaction();

      if (context.canPop()) {
        context.pop();
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
      title: 'Withdrawal Successful',
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

  void _resetTransaction() {
    amountCtrl.clear();
    feeCtrl.clear();
    taxCtrl.clear();
    userIdCtrl.clear();

    ref.read(walletTransactionProvider.notifier).reset();
  }

  void _closeScreen() {
    if (!mounted) {
      return;
    }

    FocusScope.of(context).unfocus();

    _resetTransaction();

    if (context.canPop()) {
      context.pop();
    }
  }
}
