import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/widgets/app_icon_button.dart';
import 'package:ngoda/ui/widgets/scan_qr_screen.dart';

List<AppIconButton> getUserHomeScreenQuickLinks({
  required BuildContext context,
  required UserRole role,
  required double iconSize,
  required Color primary,
  bool isCreditAgent = false,
  bool nfcSupported = false,
}) {
  switch (role) {
    case UserRole.admin:
    case UserRole.finance:
    case UserRole.accounts:
    case UserRole.treasury:
    case UserRole.compliance:
      return const [];

    case UserRole.merchant:
      return [
        if (nfcSupported)
          _quickLink(
            label: 'NFC Payment',
            icon: Icons.contactless_outlined,
            iconSize: iconSize,
            color: primary,
            onPressed: () {
              context.push('/merchant-cash/receive-nfc-payment');
            },
          ),
        _quickLink(
          label: 'QR Payment',
          icon: Icons.qr_code_2,
          iconSize: iconSize,
          color: primary,
          onPressed: () {
            context.push('/merchant-cash/receive-qr-payment');
          },
        ),
        _quickLink(
          label: 'Voucher Pay',
          icon: Icons.receipt_long_outlined,
          iconSize: iconSize,
          color: primary,
          onPressed: () async {
            final result = await _scanQrCode(context);

            if (result == null) {
              return;
            }

            if (!context.mounted) {
              return;
            }

            context.push('/merchant-cash/voucher-payment', extra: result);
          },
        ),
        _quickLink(
          label: 'Cash In',
          icon: Icons.add_card_outlined,
          iconSize: iconSize,
          color: primary,
          onPressed: () {
            context.push('/merchant-cash/receive-cash-deposit');
          },
        ),
        _quickLink(
          label: 'Cash Out',
          icon: Icons.payments_outlined,
          iconSize: iconSize,
          color: primary,
          onPressed: () async {
            final result = await _scanQrCode(context);

            if (result == null) {
              return;
            }

            if (!context.mounted) {
              return;
            }

            context.push('/merchant-cash/process-withdrawal', extra: result);
          },
        ),
        if (isCreditAgent)
          _quickLink(
            label: 'Settlement',
            icon: Icons.account_balance_wallet_outlined,
            iconSize: iconSize,
            color: primary,
            onPressed: () async {
              final result = await _scanQrCode(context);

              if (result == null) {
                return;
              }

              if (!context.mounted) {
                return;
              }

              context.push('/merchant-cash/cash-settlement', extra: result);
            },
          ),

        // // Additional current credit-agent action.
        // if (isCreditAgent)
        //   _quickLink(
        //     label: 'Credit',
        //     icon: Icons.credit_score_outlined,
        //     iconSize: iconSize,
        //     color: primary,
        //     onPressed: () {
        //       context.push('/credit-agent');
        //     },
        //   ),
      ];

    case UserRole.vendor:
      return [
        if (nfcSupported)
          _quickLink(
            label: 'NFC Payment',
            icon: Icons.contactless_outlined,
            iconSize: iconSize,
            color: primary,
            onPressed: () {
              context.push('/vendor-cash/receive-nfc-payment');
            },
          ),
        _quickLink(
          label: 'QR Payment',
          icon: Icons.qr_code_2,
          iconSize: iconSize,
          color: primary,
          onPressed: () {
            context.push('/vendor-cash/receive-qr-payment');
          },
        ),
        _quickLink(
          label: 'Voucher Pay',
          icon: Icons.receipt_long_outlined,
          iconSize: iconSize,
          color: primary,
          onPressed: () async {
            final result = await _scanQrCode(context);

            if (result == null) {
              return;
            }

            if (!context.mounted) {
              return;
            }

            context.push('/vendor-cash/voucher-payment', extra: result);
          },
        ),
        _quickLink(
          label: 'Cash In',
          icon: Icons.add_card_outlined,
          iconSize: iconSize,
          color: primary,
          onPressed: () {
            context.push('/vendor-cash/receive-cash-deposit');
          },
        ),
        _quickLink(
          label: 'Cash Out',
          icon: Icons.payments_outlined,
          iconSize: iconSize,
          color: primary,
          onPressed: () async {
            final result = await _scanQrCode(context);

            if (result == null) {
              return;
            }

            if (!context.mounted) {
              return;
            }

            context.push('/vendor-cash/process-withdrawal', extra: result);
          },
        ),

        // Additional current credit-agent action.
        if (isCreditAgent)
          _quickLink(
            label: 'Credit',
            icon: Icons.credit_score_outlined,
            iconSize: iconSize,
            color: primary,
            onPressed: () {
              context.push('/credit-agent');
            },
          ),
      ];

    case UserRole.agent:
      return [
        _quickLink(
          label: 'Cash In',
          icon: Icons.add_card_outlined,
          iconSize: iconSize,
          color: primary,
          layout: AppIconButtonLayout.horizontal,
          onPressed: () {
            context.push('/agent-cash/receive-cash-deposit');
          },
        ),
        _quickLink(
          label: 'Cash Out',
          icon: Icons.payments_outlined,
          iconSize: iconSize,
          color: primary,
          layout: AppIconButtonLayout.horizontal,
          onPressed: () async {
            final result = await _scanQrCode(context);

            if (result == null) {
              return;
            }

            if (!context.mounted) {
              return;
            }

            context.go('/agent-cash/process-withdrawal', extra: result);
          },
        ),

        // Additional current credit-agent action.
        if (isCreditAgent)
          _quickLink(
            label: 'Credit',
            icon: Icons.credit_score_outlined,
            iconSize: iconSize,
            color: primary,
            layout: AppIconButtonLayout.horizontal,
            onPressed: () {
              context.push('/credit-agent');
            },
          ),
      ];

    case UserRole.customer:
      return [
        _quickLink(
          label: 'QR Payment',
          icon: Icons.qr_code_scanner,
          iconSize: iconSize,
          color: primary,
          onPressed: () async {
            final result = await _scanQrCode(context);

            if (result == null) {
              return;
            }

            if (!context.mounted) {
              return;
            }

            context.go('/customer-cash/make-qr-payment', extra: result);
          },
        ),
        _quickLink(
          label: 'Cash In',
          icon: Icons.add_card_outlined,
          iconSize: iconSize,
          color: primary,
          onPressed: () async {
            final result = await _scanQrCode(context);

            if (result == null) {
              return;
            }

            if (!context.mounted) {
              return;
            }

            context.go('/customer-cash/make-cash-deposit', extra: result);
          },
        ),
        _quickLink(
          label: 'Cash Send',
          icon: Icons.send_outlined,
          iconSize: iconSize,
          color: primary,
          onPressed: () {
            context.go('/customer-cash/send-cash');
          },
        ),
        _quickLink(
          label: 'Cash Out',
          icon: Icons.payments_outlined,
          iconSize: iconSize,
          color: primary,
          onPressed: () {
            context.go('/customer-cash/make-cash-withdrawal');
          },
        ),
        _quickLink(
          label: 'Create Voucher',
          icon: Icons.receipt_long_outlined,
          iconSize: iconSize,
          color: primary,
          onPressed: () {
            context.go('/customer-cash/create-payment-voucher');
          },
        ),
        _quickLink(
          label: 'Access Value',
          icon: Icons.account_balance_wallet_outlined,
          iconSize: iconSize,
          color: primary,
          onPressed: () {
            context.push('/loans/borrow');
          },
        ),
        _quickLink(
          label: 'Settle Balance',
          icon: Icons.currency_exchange_outlined,
          iconSize: iconSize,
          color: primary,
          onPressed: () {
            context.push('/loans/repay');
          },
        ),
        _quickLink(
          label: 'Buy Gold',
          icon: Icons.savings_outlined,
          iconSize: iconSize,
          color: primary,
          onPressed: () {
            context.push('/gold/buy');
          },
        ),
        _quickLink(
          label: 'Sell Gold',
          icon: Icons.sell_outlined,
          iconSize: iconSize,
          color: primary,
          onPressed: () {
            context.push('/gold/sell');
          },
        ),
        _quickLink(
          label: 'Transfer Gold',
          icon: Icons.swap_horiz,
          iconSize: iconSize,
          color: primary,
          onPressed: () {
            context.push('/gold/transfer');
          },
        ),

        // Additional current NFC action.
        if (nfcSupported)
          _quickLink(
            label: 'Tap',
            icon: Icons.contactless_outlined,
            iconSize: iconSize,
            color: primary,
            onPressed: () {
              context.push('/tap-to-pay');
            },
          ),
      ];
  }
}

AppIconButton _quickLink({
  required String label,
  required IconData icon,
  required double iconSize,
  required Color color,
  required VoidCallback onPressed,
  AppIconButtonLayout layout = AppIconButtonLayout.vertical,
}) {
  return AppIconButton(
    title: label,
    icon: icon,
    iconSize: iconSize,
    color: color,
    layout: layout,
    onTap: onPressed,
  );
}

Future<dynamic> _scanQrCode(BuildContext context) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const ScanQrScreen()));
}
