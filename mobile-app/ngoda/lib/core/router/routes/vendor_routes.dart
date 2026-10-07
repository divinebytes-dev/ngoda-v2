import 'package:go_router/go_router.dart';

import 'package:ngoda/core/router/utils/custom_page_transition.dart';
import 'package:ngoda/data_models/transaction/transaction_data.dart';
import 'package:ngoda/ui/screens/vendor/cash/vendor_cash_screen.dart';
import 'package:ngoda/ui/screens/wallet/transactions/create_payment_voucher_screen.dart';
import 'package:ngoda/ui/screens/wallet/transactions/make_deposit_screen.dart';
import 'package:ngoda/ui/screens/wallet/transactions/make_nfc_payment_screen.dart';
import 'package:ngoda/ui/screens/wallet/transactions/make_qr_payment_screen.dart';
import 'package:ngoda/ui/screens/wallet/transactions/process_customer_withdrawal_screen.dart';
import 'package:ngoda/ui/screens/wallet/transactions/receive_customer_deposit_screen.dart';
import 'package:ngoda/ui/screens/wallet/transactions/receive_nfc_payment_screen.dart';
import 'package:ngoda/ui/screens/wallet/transactions/receive_qr_payment_screen.dart';
import 'package:ngoda/ui/screens/wallet/transactions/send_cash_screen.dart';
import 'package:ngoda/ui/screens/wallet/transactions/voucher_payment_screen.dart';
import 'package:ngoda/ui/screens/wallet/transactions/withdraw_cash_screen.dart';

final List<GoRoute> vendorRoutes = [
  GoRoute(
    path: '/vendor-cash',
    builder: (_, _) => const VendorCashScreen(),
    routes: [
      /*
       * Receive transactions.
       */
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

      /*
       * Outgoing transactions.
       */
      GoRoute(
        path: 'make-cash-deposit',
        pageBuilder: (_, state) {
          final qrData = state.extra as TransactionData?;

          return slidePage(MakeDepositScreen(qrData: qrData), state);
        },
      ),
      GoRoute(
        path: 'cash-send',
        pageBuilder: (_, state) {
          return slidePage(SendCashScreen(), state);
        },
      ),
      GoRoute(
        path: 'make-cash-withdrawal',
        pageBuilder: (_, state) {
          return slidePage(WithdrawCashScreen(), state);
        },
      ),
      GoRoute(
        path: 'make-qr-payment',
        pageBuilder: (_, state) {
          final qrData = state.extra as TransactionData?;

          return slidePage(MakeQrPaymentScreen(qrData: qrData), state);
        },
      ),
      GoRoute(
        path: 'create-payment-voucher',
        pageBuilder: (_, state) {
          return slidePage(CreatePaymentVoucherScreen(), state);
        },
      ),
      GoRoute(
        path: 'make-nfc-payment',
        pageBuilder: (_, state) {
          final paymentData = state.extra as TransactionData?;

          return slidePage(
            MakeNFCPaymentScreen(paymentData: paymentData),
            state,
          );
        },
      ),
    ],
  ),
];
