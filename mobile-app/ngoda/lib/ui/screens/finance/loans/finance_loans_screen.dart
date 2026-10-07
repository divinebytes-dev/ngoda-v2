import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/params/loan_liquidation_params.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/widgets/action_tile.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';

class FinanceLoansScreen extends StatelessWidget {
  const FinanceLoansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 3),
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'SVA Operations'),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(spacing.padding),
                child: Column(
                  children: [
                    ActionTile(
                      title: 'Last Accrual Date',
                      subtitle: 'View last interest calculation',
                      icon: Icons.event,
                      color: Colors.green,
                      onTap: () {
                        context.push('/finance-loans/last-accrual-date');
                      },
                    ),

                    SizedBox(height: spacing.sm),

                    ActionTile(
                      title: 'Liquidation Jobs',
                      subtitle: 'View loan liquidations',
                      icon: Icons.warning_amber_rounded,
                      color: Colors.red,
                      onTap: () {
                        context.push(
                          '/finance-loans/liquidated-loans',
                          extra: LoanLiquidationParams(page: 1, pageSize: 50),
                        );
                      },
                    ),

                    SizedBox(height: spacing.sm),

                    ActionTile(
                      title: 'Blockchain Jobs',
                      subtitle: 'View pending blockchain processing',
                      icon: Icons.sync,
                      color: Colors.orange,
                      onTap: () {
                        context.push(
                          '/finance-loans/incomplete-liquidation-jobs',
                          extra: LoanLiquidationParams(page: 1, pageSize: 50),
                        );
                      },
                    ),

                    SizedBox(height: spacing.sm),

                    ActionTile(
                      title: 'Manual Review Liquidation Jobs',
                      subtitle: 'Manual review pending liquidation jobs',
                      icon: Icons.sync,
                      color: Colors.orange,
                      onTap: () {
                        context.push(
                          '/finance-loans/manual-review-liquidation-jobs',
                          extra: LoanLiquidationParams(page: 1, pageSize: 50),
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
    );
  }
}
