import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/core/providers/hive_service_provider.dart';
import 'package:ngoda/services/hive_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_colors.dart';
import 'package:ngoda/ui/widgets/action_tile.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/scan_qr_screen.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';

class CustomerCashScreen extends ConsumerWidget {
  const CustomerCashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

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
          padding: EdgeInsets.all(spacing.md),
          child: Column(
            children: [
              const ScreenHeader(
                title: 'Cash Wallet',
                subtitle: 'Manage your cash balances',
              ),

              SizedBox(height: spacing.md),

              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: spacing.md),
                  child: Column(
                    children: [
                      ActionTile(
                        title: 'QR Payment',
                        subtitle: 'Make payment securely',
                        icon: Icons.qr_code,
                        color: colorScheme.primary,
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ScanQrScreen(),
                            ),
                          );

                          if (result == null || !context.mounted) {
                            return;
                          }

                          context.push(
                            '/customer-cash/make-qr-payment',
                            extra: result,
                          );
                        },
                      ),

                      SizedBox(height: spacing.sm),

                      ActionTile(
                        title: 'Deposit Cash',
                        subtitle: 'Make cash deposit securely',
                        icon: Icons.download,
                        color: AppColors.success,
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ScanQrScreen(),
                            ),
                          );

                          if (result == null || !context.mounted) {
                            return;
                          }

                          context.push(
                            '/customer-cash/make-cash-deposit',
                            extra: result,
                          );
                        },
                      ),

                      SizedBox(height: spacing.sm),

                      ActionTile(
                        title: 'Send Cash',
                        subtitle: 'Transfer cash to other users',
                        icon: Icons.send,
                        color: colorScheme.primary,
                        onTap: () {
                          context.push('/customer-cash/send-cash');
                        },
                      ),

                      SizedBox(height: spacing.sm),

                      ActionTile(
                        title: 'Withdraw Cash',
                        subtitle: 'Withdraw cash securely',
                        icon: Icons.upload,
                        color: AppColors.warning,
                        onTap: () {
                          context.push('/customer-cash/make-cash-withdrawal');
                        },
                      ),

                      if (nfcSupported) ...[
                        SizedBox(height: spacing.sm),

                        ActionTile(
                          title: 'NFC Payment',
                          subtitle: 'Tap 2 Pay',
                          icon: Icons.contactless,
                          color: colorScheme.primary,
                          onTap: () {
                            context.push('/customer-cash/make-nfc-payment');
                          },
                        ),
                      ],

                      SizedBox(height: spacing.sm),

                      ActionTile(
                        title: 'Payment Voucher',
                        subtitle: 'Create payment voucher',
                        icon: Icons.receipt_outlined,
                        color: colorScheme.secondary,
                        onTap: () {
                          context.push('/customer-cash/create-payment-voucher');
                        },
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
    );
  }
}
