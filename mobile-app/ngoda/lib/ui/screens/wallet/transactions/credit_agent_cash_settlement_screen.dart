// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';
// import 'package:ngoda/data_models/payment/payment_row.dart';
// import 'package:ngoda/data_models/transaction/transaction_data.dart';
// import 'package:ngoda/services/currency_service.dart';
// import 'package:ngoda/services/dialog_service.dart';
// import 'package:ngoda/services/number_format_service.dart';
// import 'package:ngoda/ui/enums/enums.dart';
// import 'package:ngoda/ui/extensions/app_size.dart';
// import 'package:ngoda/ui/extensions/theme_extension.dart';
// import 'package:ngoda/ui/functions/get_wallet_balances.dart';
// import 'package:ngoda/ui/functions/refresh_user_dashboard.dart';
// import 'package:ngoda/ui/screens/wallet/transactions/provider/wallet_transaction_provider.dart';
// import 'package:ngoda/ui/shared/app_text_styles.dart';
// import 'package:ngoda/ui/widgets/app_button.dart';
// import 'package:ngoda/ui/widgets/app_error_state.dart';
// import 'package:ngoda/ui/widgets/app_value_row.dart';
// import 'package:ngoda/ui/widgets/input_field.dart';
// import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
// import 'package:ngoda/ui/widgets/view_header.dart';

// class CreditAgentCashSettlementScreen extends ConsumerStatefulWidget {
//   final TransactionData? qrData;

//   const CreditAgentCashSettlementScreen({super.key, this.qrData});

//   @override
//   ConsumerState<CreditAgentCashSettlementScreen> createState() =>
//       _CreditAgentCashSettlementScreenState();
// }

// class _CreditAgentCashSettlementScreenState
//     extends ConsumerState<CreditAgentCashSettlementScreen> {
//   final amountCtrl = TextEditingController();
//   final emailCtrl = TextEditingController();

//   bool _transactionInitialized = false;
//   String? _initializationError;

//   @override
//   void initState() {
//     super.initState();

//     final data = widget.qrData;

//     if (data == null) {
//       return;
//     }

//     final amount = data.a / 100;

//     amountCtrl.text = NumberFormatService.formatAmount(
//       amount,
//       currency: data.c,
//     );

//     emailCtrl.text = data.s;

//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       if (!mounted) {
//         return;
//       }

//       _initializeTransaction(data);
//     });
//   }

//   @override
//   void dispose() {
//     amountCtrl.dispose();
//     emailCtrl.dispose();

//     super.dispose();
//   }

//   void _initializeTransaction(TransactionData data) {
//     if (_transactionInitialized) {
//       return;
//     }

//     final currency = CurrencyService.get(data.c);

//     if (currency == null) {
//       setState(() {
//         _initializationError =
//             'Currency ${data.c.toUpperCase()} is not available';
//       });

//       return;
//     }

//     final balances = getAgentWalletBalance(ref);

//     if (balances == null) {
//       setState(() {
//         _initializationError = 'Failed to get agent wallet';
//       });

//       return;
//     }

//     final notifier = ref.read(walletTransactionProvider.notifier);

//     notifier
//       ..initReference()
//       ..updateCurrency(currency, balances)
//       ..updateAmountPay(data);

//     _transactionInitialized = true;

//     if (_initializationError != null) {
//       setState(() {
//         _initializationError = null;
//       });
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final radius = context.radius;
//     final colorScheme = context.colorScheme;

//     final state = ref.watch(walletTransactionProvider);

//     final data = widget.qrData;

//     if (data == null) {
//       return Scaffold(
//         body: SafeArea(
//           child: Padding(
//             padding: EdgeInsets.all(spacing.md),
//             child: Column(
//               children: [
//                 ViewHeader(
//                   title: 'Cash Settlement',
//                   subtitle: 'Cash balance settlement',
//                   onClose: _closeScreen,
//                 ),
//                 const Expanded(
//                   child: AppErrorState(message: 'Failed to read settlement QR'),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       );
//     }

//     if (_initializationError != null) {
//       return Scaffold(
//         body: SafeArea(
//           child: Padding(
//             padding: EdgeInsets.all(spacing.md),
//             child: Column(
//               children: [
//                 ViewHeader(
//                   title: 'Cash Settlement',
//                   subtitle: 'Cash balance settlement',
//                   onClose: _closeScreen,
//                 ),
//                 Expanded(
//                   child: Center(
//                     child: Text(
//                       _initializationError!,
//                       textAlign: TextAlign.center,
//                       style: AppTextStyles.small(
//                         context,
//                       ).copyWith(color: colorScheme.error),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       );
//     }

//     return Scaffold(
//       body: SafeArea(
//         child: GestureDetector(
//           behavior: HitTestBehavior.translucent,
//           onTap: () {
//             FocusScope.of(context).unfocus();
//           },
//           child: Padding(
//             padding: EdgeInsets.all(spacing.md),
//             child: Column(
//               children: [
//                 ViewHeader(
//                   title: 'Cash Settlement',
//                   subtitle: 'Cash balance settlement',
//                   onClose: _closeScreen,
//                 ),

//                 Expanded(
//                   child: SingleChildScrollView(
//                     keyboardDismissBehavior:
//                         ScrollViewKeyboardDismissBehavior.onDrag,
//                     child: Column(
//                       children: [
//                         SizedBox(height: spacing.md),

//                         Container(
//                           width: double.infinity,
//                           padding: EdgeInsets.all(spacing.md),
//                           decoration: BoxDecoration(
//                             color: context.theme.cardColor,
//                             borderRadius: BorderRadius.circular(radius.md),
//                             boxShadow: [
//                               BoxShadow(
//                                 color: colorScheme.shadow.withValues(
//                                   alpha: 0.05,
//                                 ),
//                                 blurRadius: spacing.lg,
//                                 offset: Offset(0, spacing.sm),
//                               ),
//                             ],
//                           ),
//                           child: Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               InputField(
//                                 controller: emailCtrl,
//                                 readOnly: true,
//                                 placeholder: 'Ngoda Accounts',
//                               ),

//                               SizedBox(height: spacing.md),

//                               InputField(
//                                 controller: amountCtrl,
//                                 readOnly: true,
//                                 placeholder: 'Amount',
//                               ),

//                               if (state.error != null &&
//                                   state.error!.trim().isNotEmpty) ...[
//                                 SizedBox(height: spacing.sm),
//                                 Align(
//                                   alignment: Alignment.centerLeft,
//                                   child: Text(
//                                     state.error!,
//                                     style: AppTextStyles.tiny(
//                                       context,
//                                     ).copyWith(color: colorScheme.error),
//                                   ),
//                                 ),
//                               ],

//                               if (state.currency != null &&
//                                   state.amount > 0) ...[
//                                 SizedBox(height: spacing.lg),
//                                 _buildCalculation(),
//                               ],

//                               SizedBox(height: spacing.lg),

//                               Row(
//                                 children: [
//                                   Expanded(
//                                     child: AppButton(
//                                       text: 'Cancel',
//                                       isPrimary: false,
//                                       isDisabled: state.isLoading,
//                                       onPressed: _closeScreen,
//                                     ),
//                                   ),

//                                   SizedBox(width: spacing.md),

//                                   Expanded(
//                                     child: AppButton(
//                                       text: 'Settle Balance',
//                                       isProcessing: state.isLoading,
//                                       onPressed:
//                                           !state.isValid ||
//                                               state.isLoading ||
//                                               !_transactionInitialized
//                                           ? null
//                                           : handleCashSettlement,
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ],
//                           ),
//                         ),

//                         SizedBox(height: spacing.md),
//                       ],
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildCalculation() {
//     final state = ref.watch(walletTransactionProvider);

//     final currency = state.currency!.code;

//     return PaymentCalculationCard(
//       children: [
//         AppValueRow(
//           label: 'Amount',
//           value: NumberFormatService.formatAmount(
//             state.amount,
//             currency: currency,
//           ),
//           addBottomSpacing: false,
//         ),

//         Padding(
//           padding: EdgeInsets.symmetric(vertical: context.spacing.sm),
//           child: const Divider(),
//         ),

//         AppValueRow(
//           label: 'Total',
//           value: NumberFormatService.formatAmount(
//             state.totalDebit,
//             currency: currency,
//           ),
//           valueStyle: AppTextStyles.smallNumber(
//             context,
//           ).copyWith(fontWeight: FontWeight.w700),
//           addBottomSpacing: false,
//         ),
//       ],
//     );
//   }

//   Future<void> handleCashSettlement() async {
//     final data = widget.qrData;

//     if (data == null || !_transactionInitialized) {
//       return;
//     }

//     try {
//       final notifier = ref.read(walletTransactionProvider.notifier);

//       await notifier.creditAgentCashSettlement(data);

//       if (!mounted) {
//         return;
//       }

//       refreshUserDashboard(ref);

//       /*
//        * Keep the transaction state intact until
//        * the receipt has been built and displayed.
//        *
//        * The amount controllers can be cleared
//        * after the transaction because the receipt
//        * reads from walletTransactionProvider.
//        */
//       amountCtrl.clear();
//       emailCtrl.clear();

//       await showReceipt();

//       if (!mounted) {
//         return;
//       }

//       _resetTransaction();
//     } catch (error) {
//       if (!mounted) {
//         return;
//       }

//       await DialogService.error(context, message: error.toString());
//     }
//   }

//   Future<void> showReceipt() async {
//     final state = ref.read(walletTransactionProvider);

//     final currency = state.currency!.code;

//     final screenRoute = ModalRoute.of(context);

//     await DialogService.paymentReceipt(
//       context,
//       title: 'Credit Agent Cash Settlement',
//       rows: [
//         PaymentRow(
//           'Amount',
//           NumberFormatService.formatAmount(state.amount, currency: currency),
//           type: PaymentRowType.amount,
//         ),
//         PaymentRow(
//           'Total',
//           NumberFormatService.formatAmount(
//             state.totalDebit,
//             currency: currency,
//           ),
//           type: PaymentRowType.amount,
//           isBold: true,
//         ),
//       ],
//       onDone: () {},
//     );

//     await WidgetsBinding.instance.endOfFrame;

//     while (mounted && screenRoute != null && !screenRoute.isCurrent) {
//       await WidgetsBinding.instance.endOfFrame;
//     }

//     await Future<void>.delayed(const Duration(milliseconds: 200));
//   }

//   void _resetTransaction() {
//     amountCtrl.clear();
//     emailCtrl.clear();

//     final notifier = ref.read(walletTransactionProvider.notifier);

//     notifier.reset();
//     notifier.initReference();
//   }

//   void _closeScreen() {
//     if (!mounted) {
//       return;
//     }

//     FocusScope.of(context).unfocus();

//     _resetTransaction();

//     if (context.canPop()) {
//       context.pop();
//     }
//   }
// }
