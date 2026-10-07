import 'package:go_router/go_router.dart';

import 'package:ngoda/core/router/utils/custom_page_transition.dart';
import 'package:ngoda/data_models/transaction/transaction_data.dart';
import 'package:ngoda/ui/screens/merchant/cash/merchant_cash_screen.dart';
import 'package:ngoda/ui/screens/wallet/reports/commission_summary_screen.dart';
import 'package:ngoda/ui/screens/wallet/transactions/process_customer_withdrawal_screen.dart';
import 'package:ngoda/ui/screens/wallet/transactions/receive_customer_deposit_screen.dart';
import 'package:ngoda/ui/screens/wallet/transactions/receive_nfc_payment_screen.dart';
import 'package:ngoda/ui/screens/wallet/transactions/receive_qr_payment_screen.dart';
import 'package:ngoda/ui/screens/wallet/transactions/voucher_payment_screen.dart';

final List<GoRoute> merchantRoutes = [
  GoRoute(
    path: '/merchant-cash',
    builder: (_, _) => const MerchantCashScreen(),
    routes: [
      GoRoute(
        path: 'receive-qr-payment',
        pageBuilder: (_, state) {
          return slidePage(ReceiveQrPaymentScreen(), state);
        },
      ),
      GoRoute(
        path: 'receive-nfc-payment',
        pageBuilder: (_, state) {
          return slidePage(ReceiveNFCPaymentScreen(), state);
        },
      ),
      GoRoute(
        path: 'receive-cash-deposit',
        pageBuilder: (_, state) {
          return slidePage(ReceiveCustomerDepositScreen(), state);
        },
      ),
      // GoRoute(
      //   path: 'cash-settlement',
      //   pageBuilder: (_, state) {
      //     final transactionData = state.extra as TransactionData?;

      //     return slidePage(
      //       CreditAgentCashSettlementScreen(qrData: transactionData),
      //       state,
      //     );
      //   },
      // ),
      GoRoute(
        path: 'voucher-payment',
        pageBuilder: (_, state) {
          final paymentData = state.extra as TransactionData?;

          return slidePage(VoucherPaymentScreen(qrData: paymentData), state);
        },
      ),
      GoRoute(
        path: 'process-withdrawal',
        pageBuilder: (_, state) {
          final transactionData = state.extra as TransactionData?;

          return slidePage(
            ProcessUserWithdrawalScreen(transactionData: transactionData),
            state,
          );
        },
      ),
    ],
  ),
  GoRoute(
    path: '/commission-summary',
    pageBuilder: (_, state) {
      return slidePage(CommissionSummaryScreen(), state);
    },
  ),
];
