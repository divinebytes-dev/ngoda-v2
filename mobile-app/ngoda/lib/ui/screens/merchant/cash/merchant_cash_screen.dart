import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/core/providers/hive_service_provider.dart';
import 'package:ngoda/services/hive_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/widgets/action_tile.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/scan_qr_screen.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';

class MerchantCashScreen extends ConsumerWidget {
  const MerchantCashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;

    final nfcSupported =
        ref
            .read(hiveServiceProvider)
            .getItem<bool>(HiveBoxName.nfcSupport, 'nfcSupported')
            .result ??
        false;

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 1),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(spacing.padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const ScreenHeader(
                title: 'Cash Wallet',
                subtitle: 'Manage your cash',
              ),

              SizedBox(height: spacing.md),

              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: spacing.sm),
                  child: Column(
                    children: [
                      if (nfcSupported) ...[
                        ActionTile(
                          title: 'NFC Payment',
                          subtitle: 'Receive payment securely',
                          icon: Icons.nfc,
                          color: Colors.green,
                          onTap: () => context.push(
                            '/merchant-cash/receive-nfc-payment',
                          ),
                        ),
                        SizedBox(height: spacing.sm),
                      ],

                      ActionTile(
                        title: 'QR Payment',
                        subtitle: 'Receive QR payments securely',
                        icon: Icons.qr_code,
                        color: Colors.green,
                        onTap: () =>
                            context.push('/merchant-cash/receive-qr-payment'),
                      ),

                      SizedBox(height: spacing.sm),

                      ActionTile(
                        title: 'Voucher Payment',
                        subtitle: 'Receive payment securely',
                        icon: Icons.receipt,
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

                          context.push(
                            '/merchant-cash/voucher-payment',
                            extra: result,
                          );
                        },
                      ),

                      SizedBox(height: spacing.sm),

                      ActionTile(
                        title: 'Cash Deposit',
                        subtitle: 'Make customer cash deposit securely',
                        icon: Icons.upload,
                        color: Colors.orange,
                        onTap: () =>
                            context.push('/merchant-cash/receive-cash-deposit'),
                      ),

                      SizedBox(height: spacing.sm),

                      ActionTile(
                        title: 'Cash Withdrawal',
                        subtitle: 'Make user withdraw cash safely',
                        icon: Icons.money,
                        color: Colors.amber,
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

                          context.push(
                            '/merchant-cash/process-withdrawal',
                            extra: result,
                          );
                        },
                      ),
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
