import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/hive_service_provider.dart';
import 'package:ngoda/services/hive_service.dart';
import 'package:ngoda/services/screen_scaling_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/widgets/action_tile.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/ui/widgets/scan_qr_screen.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';

class VendorCashScreen extends ConsumerWidget {
  const VendorCashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // final heightL = ScreenScalingService.scaleSize(context, 20);
    final radius = ScreenScalingService.scaleSize(context, 15);
    final nfcSupported =
        ref
            .read(hiveServiceProvider)
            .getItem<bool>(HiveBoxName.nfcSupport, "nfcSupported")
            .result ??
        false;
    print("nfc supported $nfcSupported");
    final spacing = context.spacing.sm;

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 1),

      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(radius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              /// 🔹 Header
              ScreenHeader(title: "Cash Wallet", subtitle: "Manage your cash"),

              /// 🔹 Fiat Card (reuse)
              // FiatCard(wallet: wallet),
              SizedBox(height: context.spacing.md),

              /// 🔹 Actions
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(0, 0, 0, spacing),
                  child: Column(
                    children: [
                      /// 🔹 QR PAYMENT
                      ActionTile(
                        title: "QR Payment",
                        subtitle: "Make payment securely",
                        icon: Icons.qr_code,
                        color: Colors.white,
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ScanQrScreen(),
                            ),
                          );

                          if (result == null) {
                            return;
                          }

                          if (!context.mounted) {
                            return;
                          }

                          context.go(
                            '/vendor-cash/make-qr-payment',
                            extra: result,
                          );
                        },
                      ),

                      SizedBox(height: spacing),

                      /// 🔹 DEPOSIT
                      ActionTile(
                        title: "Deposit Cash",

                        subtitle: "Make cash deposit securely",

                        icon: Icons.download,

                        color: Colors.green,

                        onTap: () async {
                          final result = await Navigator.push(
                            context,

                            MaterialPageRoute(
                              builder: (_) => const ScanQrScreen(),
                            ),
                          );

                          if (result == null) {
                            return;
                          }

                          if (!context.mounted) {
                            return;
                          }

                          context.go(
                            '/vendor-cash/make-cash-deposit',
                            extra: result,
                          );
                        },
                      ),

                      SizedBox(height: spacing),

                      /// 🔹 SEND CASH
                      ActionTile(
                        title: "Send Cash",

                        subtitle: "Transfer cash to other users",

                        icon: Icons.send,

                        color: Theme.of(context).colorScheme.primary,

                        onTap: () => context.go('/vendor-cash/cash-send'),
                      ),

                      SizedBox(height: spacing),

                      /// 🔹 WITHDRAW CASH
                      ActionTile(
                        title: "Withdraw Cash",

                        subtitle: "Withdraw cash securely",

                        icon: Icons.upload,

                        color: Colors.orange,

                        onTap: () =>
                            context.go('/vendor-cash/make-cash-withdrawal'),
                      ),
                      SizedBox(height: spacing),

                      if (nfcSupported)
                        /// 🔹 WITHDRAW CASH
                        ActionTile(
                          title: "NFC Payment",

                          subtitle: "Tap 2 Pay",

                          icon: Icons.upload,

                          color: Colors.red,

                          onTap: () =>
                              context.go('/vendor-cash/make-nfc-payment'),
                        ),
                      if (nfcSupported) SizedBox(height: spacing),
                      ActionTile(
                        title: "Payment Voucher",

                        subtitle: "Create payment voucher",

                        icon: Icons.receipt_outlined,

                        color: Colors.deepPurpleAccent,

                        onTap: () =>
                            context.go('/vendor-cash/create-payment-voucher'),
                      ),
                      SizedBox(height: spacing),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
