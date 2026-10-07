import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/action_tile.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';

class FinancialStatementsScreen extends StatelessWidget {
  const FinancialStatementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 2),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(spacing.lg),
              child: Column(
                children: [
                  SizedBox(height: spacing.lg),
                  Center(
                    child: Text(
                      'Financial Statements',
                      style: AppTextStyles.medium(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(height: spacing.lg),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  spacing.padding,
                  0,
                  spacing.padding,
                  spacing.lg,
                ),
                child: Column(
                  children: [
                    SizedBox(height: spacing.lg),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(spacing.md),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(
                          radius.borderRadius,
                        ),
                      ),
                      child: Column(
                        children: [
                          ActionTile(
                            title: 'Trial Balance',
                            subtitle: 'Trial Balance statement',
                            icon: Icons.receipt_long,
                            color: Colors.green,
                            onTap: () {
                              context.push(
                                '/financial-statements/trial-balance',
                              );
                            },
                          ),
                          SizedBox(height: spacing.md),
                          ActionTile(
                            title: 'Profit and Loss',
                            subtitle: 'Profit and loss statement',
                            icon: Icons.summarize,
                            color: Colors.indigo,
                            onTap: () {
                              context.push('/financial-statements/profit-loss');
                            },
                          ),
                          SizedBox(height: spacing.md),
                          ActionTile(
                            title: 'Balance Sheet',
                            subtitle: 'Balance sheet statement',
                            icon: Icons.book,
                            color: Colors.blue,
                            onTap: () {
                              context.push(
                                '/financial-statements/balance-sheet',
                              );
                            },
                          ),
                        ],
                      ),
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
