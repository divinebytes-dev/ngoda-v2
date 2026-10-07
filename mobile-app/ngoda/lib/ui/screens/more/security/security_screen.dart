import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/action_tile.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(spacing.margin),
          child: Column(
            children: [
              ViewHeader(
                title: 'Security',
                onClose: () {
                  context.pop();
                },
              ),

              SizedBox(height: spacing.lg),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Account Security',
                        style: AppTextStyles.medium(
                          context,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),

                      SizedBox(height: spacing.xs),

                      Text(
                        'Manage how you access and protect your account.',
                        style: AppTextStyles.small(
                          context,
                        ).copyWith(color: context.colorScheme.onSurfaceVariant),
                      ),

                      SizedBox(height: spacing.lg),

                      ActionTile(
                        icon: Icons.lock_outline,
                        title: 'Password',
                        subtitle: 'Change your account password',
                        onTap: () {
                          context.push('/security/reset-password');
                        },
                      ),

                      SizedBox(height: spacing.md),

                      ActionTile(
                        icon: Icons.pin_outlined,
                        title: 'Security PIN',
                        subtitle: 'Change your security PIN',
                        onTap: () {
                          context.push('/security/change-pin');
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
