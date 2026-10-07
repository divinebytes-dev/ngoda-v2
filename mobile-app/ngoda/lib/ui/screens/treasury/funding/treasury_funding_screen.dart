import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/action_tile.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';

class TreasuryFundingScreen extends ConsumerWidget {
  const TreasuryFundingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 1),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            spacing.md,
            spacing.md,
            spacing.md,
            spacing.lg,
          ),
          children: [
            Center(
              child: Text(
                'Funding',
                style: AppTextStyles.large(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
            ),

            SizedBox(height: spacing.xs),

            Center(
              child: Text(
                'Manage treasury funding.',
                style: AppTextStyles.small(
                  context,
                ).copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),

            SizedBox(height: spacing.lg),

            // const _SectionLabel(
            //   title: 'Funding options',
            //   description: 'Choose the type of funding you want to process.',
            // ),

            // SizedBox(height: spacing.sm),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(spacing.sm),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(spacing.md),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                children: [
                  ActionTile(
                    title: 'Fund Agent',
                    subtitle: 'Transfer funds to an agent.',
                    icon: Icons.account_balance_wallet_outlined,
                    color: colorScheme.primary,
                    onTap: () {
                      context.push('/treasury-funding/agent-funding');
                    },
                  ),

                  SizedBox(height: spacing.sm),

                  ActionTile(
                    title: 'Fund Credit Agent',
                    subtitle: 'Transfer funds to a credit agent.',
                    icon: Icons.credit_score_outlined,
                    color: colorScheme.primary,
                    onTap: () {
                      context.push('/treasury-funding/credit-agent-funding');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// class _SectionLabel extends StatelessWidget {
//   const _SectionLabel({required this.title, required this.description});

//   final String title;
//   final String description;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final colorScheme = context.colorScheme;

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           title,
//           style: AppTextStyles.small(
//             context,
//           ).copyWith(fontWeight: FontWeight.w700),
//         ),
//         SizedBox(height: spacing.xs),
//         Text(
//           description,
//           style: AppTextStyles.tiny(
//             context,
//           ).copyWith(color: colorScheme.onSurfaceVariant),
//         ),
//       ],
//     );
//   }
// }
