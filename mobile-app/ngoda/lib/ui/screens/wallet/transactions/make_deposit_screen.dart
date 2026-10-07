import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/payment/customer_transaction_setup.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/data_models/transaction/transaction_data.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/services/transaction_loyalty_celebration_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/refresh_user_dashboard.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/customer_transaction_setup_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/wallet_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class MakeDepositScreen extends ConsumerStatefulWidget {
  final TransactionData? qrData;

  const MakeDepositScreen({super.key, this.qrData});

  @override
  ConsumerState<MakeDepositScreen> createState() => _MakeDepositScreenState();
}

class _MakeDepositScreenState extends ConsumerState<MakeDepositScreen> {
  final amountCtrl = TextEditingController();
  final emailCtrl = TextEditingController();

  String? _currencyCode;
  bool _transactionInitialized = false;

  @override
  void initState() {
    super.initState();

    final data = widget.qrData;

    if (data == null) {
      return;
    }

    final amount = data.a / 100;

    _currencyCode = data.c;

    amountCtrl.text = NumberFormatService.formatAmount(
      amount,
      currency: data.c,
    );

    emailCtrl.text = data.s;

    ref.listenManual<AsyncValue<CustomerTransactionSetup>>(
      customerTransactionSetupProvider,
      (previous, next) {
        next.whenData((setup) {
          _initializeTransaction(data, setup);
        });
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    amountCtrl.dispose();
    emailCtrl.dispose();

    super.dispose();
  }

  void _initializeTransaction(
    TransactionData data,
    CustomerTransactionSetup setup,
  ) {
    if (_transactionInitialized) {
      return;
    }

    final currencyCode = _currencyCode;

    if (currencyCode == null) {
      return;
    }

    final currency = setup.currencyRegistry.getByCode(currencyCode);

    if (currency == null) {
      return;
    }

    _transactionInitialized = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ref.read(walletTransactionProvider.notifier)
        ..updateCurrency(currency, setup.balances)
        ..updateAmountToDeposit(data)
        ..initReference();
    });
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final state = ref.watch(walletTransactionProvider);

    final setupAsync = ref.watch(customerTransactionSetupProvider);

    if (setupAsync.isLoading) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: CircularProgressIndicator(color: colorScheme.primary),
          ),
        ),
      );
    }

    if (setupAsync.hasError) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(spacing.md),
            child: Center(
              child: Text(
                setupAsync.error.toString(),
                textAlign: TextAlign.center,
                style: AppTextStyles.small(
                  context,
                ).copyWith(color: colorScheme.error),
              ),
            ),
          ),
        ),
      );
    }

    if (widget.qrData == null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(spacing.md),
            child: Column(
              children: [
                ViewHeader(
                  title: 'Deposit',
                  subtitle: 'Deposit money securely',
                  onClose: _closeScreen,
                ),

                Expanded(
                  child: Center(
                    child: Text(
                      'Deposit details are not available',
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
                  title: 'Deposit',
                  subtitle: 'Deposit money securely',
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
                                controller: emailCtrl,
                                readOnly: true,
                                placeholder: 'Agent',
                              ),

                              SizedBox(height: spacing.md),

                              InputField(
                                controller: amountCtrl,
                                readOnly: true,
                                placeholder: 'Amount',
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

                              if (state.currency != null &&
                                  state.amount > 0) ...[
                                SizedBox(height: spacing.lg),

                                _buildCalculation(),
                              ],

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
                                      text: 'Deposit',
                                      isProcessing: state.isLoading,
                                      onPressed:
                                          !state.isValid || state.isLoading
                                          ? null
                                          : handleDeposit,
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
    final state = ref.watch(walletTransactionProvider);

    final currency = state.currency!.code;

    return PaymentCalculationCard(
      children: [
        AppValueRow(
          label: 'Amount',
          value: NumberFormatService.formatAmount(
            state.amount,
            currency: currency,
          ),
          addBottomSpacing: false,
        ),

        SizedBox(height: context.spacing.sm),

        AppValueRow(
          label: 'Fee',
          value: NumberFormatService.formatAmount(
            state.feeAmount,
            currency: currency,
          ),
          addBottomSpacing: false,
        ),

        Padding(
          padding: EdgeInsets.symmetric(vertical: context.spacing.sm),
          child: const Divider(),
        ),

        AppValueRow(
          label: 'Total',
          value: NumberFormatService.formatAmount(
            state.totalDebit,
            currency: currency,
          ),
          valueStyle: AppTextStyles.smallNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
          addBottomSpacing: false,
        ),
      ],
    );
  }

  Future<void> handleDeposit() async {
    final data = widget.qrData;

    if (data == null) {
      return;
    }

    try {
      final notifier = ref.read(walletTransactionProvider.notifier);

      if (data.g == 0) {
        await notifier.cashDeposit(data);
      } else {
        await notifier.creditAgentCashDeposit(data);
      }

      final loyaltyResult = ref.read(walletTransactionProvider).loyaltyResult;

      refreshUserDashboard(ref);

      if (!mounted) {
        return;
      }

      await showReceipt();

      if (!mounted) {
        return;
      }

      await TransactionLoyaltyCelebrationService.show(context, loyaltyResult);

      if (!mounted) {
        return;
      }

      _resetForm();

      if (context.canPop()) {
        context.pop();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  Future<void> showReceipt() async {
    final state = ref.read(walletTransactionProvider);

    final currency = state.currency?.code ?? 'usd';

    final screenRoute = ModalRoute.of(context);

    await DialogService.paymentReceipt(
      context,
      title: 'Deposit Successful',
      rows: [
        PaymentRow(
          'Amount',
          NumberFormatService.formatAmount(state.amount, currency: currency),
        ),

        PaymentRow(
          'Fee',
          NumberFormatService.formatAmount(state.feeAmount, currency: currency),
        ),

        PaymentRow(
          'Total Cash Deposited',
          NumberFormatService.formatAmount(
            state.totalDebit,
            currency: currency,
          ),
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

  void _resetForm() {
    amountCtrl.clear();
    emailCtrl.clear();

    ref.read(walletTransactionProvider.notifier).reset();
  }

  void _closeScreen() {
    if (!mounted) {
      return;
    }

    FocusScope.of(context).unfocus();

    _resetForm();

    if (context.canPop()) {
      context.pop();
    }
  }
}
