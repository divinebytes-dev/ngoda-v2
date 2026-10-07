import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/widgets/action_tile.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';

class AccountsPaymentScreen extends ConsumerWidget {
  const AccountsPaymentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 3),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(radius.borderRadius),
          child: Column(
            children: [
              const ScreenHeader(
                title: 'Payment Screen',
                subtitle: 'Agents commission and Government tax payment',
              ),
              SizedBox(height: spacing.sm),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: spacing.lg),
                  child: Column(
                    children: [
                      ActionTile(
                        title: 'Pending Agents Commission',
                        subtitle: 'Fetch pending agents commission',
                        icon: Icons.payments_outlined,
                        color: colorScheme.primary,
                        onTap: () {
                          context.go('/payments/commission-summary');
                        },
                      ),
                      SizedBox(height: spacing.sm),
                      ActionTile(
                        title: 'Create Agents Commission Batch',
                        subtitle: 'Create agent commission payment batch',
                        icon: Icons.payments,
                        color: colorScheme.primary,
                        onTap: () {
                          context.go('/payments/create-commission-batch');
                        },
                      ),
                      SizedBox(height: spacing.sm),
                      ActionTile(
                        title: 'Settle Agents Commission',
                        subtitle: 'Settle agent commission payment batch',
                        icon: Icons.payments,
                        color: colorScheme.primary,
                        onTap: () {
                          context.go('/payments/settle-commission-batch');
                        },
                      ),
                      SizedBox(height: spacing.sm),
                      ActionTile(
                        title: 'Settled Agents Commission',
                        subtitle: 'Settled agent commission payment batches',
                        icon: Icons.payments,
                        color: colorScheme.primary,
                        onTap: () {
                          context.go('/payments/settled-commission-batches');
                        },
                      ),
                      SizedBox(height: spacing.sm),
                      const Divider(),
                      SizedBox(height: spacing.sm),
                      ActionTile(
                        title: 'Pending Government Tax',
                        subtitle: 'Fetch pending government tax payment',
                        icon: Icons.payments_outlined,
                        color: colorScheme.primary,
                        onTap: () {
                          context.go('/payments/tax-summary');
                        },
                      ),
                      SizedBox(height: spacing.sm),
                      ActionTile(
                        title: 'Create Government Tax',
                        subtitle: 'Create government tax settlement batch',
                        icon: Icons.payments,
                        color: colorScheme.primary,
                        onTap: () {
                          context.go('/payments/create-tax-payment');
                        },
                      ),
                      SizedBox(height: spacing.sm),
                      ActionTile(
                        title: 'Settle Government Tax',
                        subtitle: 'Settle government tax batch',
                        icon: Icons.payments_outlined,
                        color: colorScheme.primary,
                        onTap: () {
                          context.go('/payments/settle-tax-payment');
                        },
                      ),
                      SizedBox(height: spacing.sm),
                      ActionTile(
                        title: 'Settled Government Tax',
                        subtitle: 'Settled government tax batches',
                        icon: Icons.payments,
                        color: colorScheme.primary,
                        onTap: () {
                          context.go('/payments/settled-tax-payments');
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
