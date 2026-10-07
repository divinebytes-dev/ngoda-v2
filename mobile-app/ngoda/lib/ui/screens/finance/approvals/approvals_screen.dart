import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/widgets/action_tile.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';

class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'Approvals'),
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
                            title: 'Approve Settlement',
                            subtitle: 'Approve commission settlement',
                            icon: Icons.receipt_long,
                            color: Colors.green,
                            onTap: () {
                              context.push('/approvals/approve-settlement');
                            },
                          ),
                          SizedBox(height: spacing.md),
                          ActionTile(
                            title: 'Approve Tax Settlement',
                            subtitle: 'Approve government tax settlement',
                            icon: Icons.receipt_long,
                            color: Colors.green,
                            onTap: () {
                              context.push('/approvals/approve-tax-settlement');
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
