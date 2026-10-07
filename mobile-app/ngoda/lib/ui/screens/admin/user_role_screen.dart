import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/widgets/action_tile.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';

class UserRoleScreen extends ConsumerWidget {
  const UserRoleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 1),
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'User Roles'),

            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  spacing.lg,
                  0,
                  spacing.lg,
                  spacing.lg,
                ),
                child: Column(
                  children: [
                    SizedBox(height: spacing.xxl),

                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(spacing.md),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(radius.cardRadius),
                      ),
                      child: Column(
                        children: [
                          ActionTile(
                            title: 'Change Roles',
                            subtitle: 'Change user role',
                            icon: Icons.edit_outlined,
                            color: Colors.green,
                            onTap: () {
                              context.push('/user-role/change-role');
                            },
                          ),

                          SizedBox(height: spacing.md),

                          ActionTile(
                            title: 'Grant Roles',
                            subtitle: 'Grant blockchain role',
                            icon: Icons.admin_panel_settings_outlined,
                            color: Colors.green,
                            onTap: () {
                              context.push('/user-role/grant-role');
                            },
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: spacing.xxxxl),
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
