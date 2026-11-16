import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/extensions/user_role_extension.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/navigation/get_more_screen_menu_items.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/engagement_settings_section.dart';
import 'package:ngoda/ui/widgets/more_tile.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  static final Logger _log = Logger('MoreScreen');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;

    final decoded = getCurrentUser();

    if (!decoded.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.go('/login');
        }
      });

      return const SizedBox.shrink();
    }

    final role = decoded.role?.trim();

    if (role == null || role.isEmpty) {
      return const SizedBox.shrink();
    }

    final rolex = UserRoleX.fromString(role);
    final items = moreActivityMenu[rolex] ?? [];

    _log.fine('More navigation role: $role, role enum: $rolex');

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 4),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(spacing.margin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'More',
                style: AppTextStyles.large(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),

              SizedBox(height: spacing.md),

              _SectionCard(
                title: 'Account',
                children: [
                  MoreTile(
                    icon: Icons.person_outline,
                    label: 'Profile',
                    onTap: () {
                      context.push('/profile');
                    },
                  ),
                  MoreTile(
                    icon: Icons.security_outlined,
                    label: 'Security',
                    onTap: () {
                      context.push('/security');
                    },
                  ),
                ],
              ),

              if (items.isNotEmpty) ...[
                SizedBox(height: spacing.md),
                _SectionCard(
                  title: 'Activity',
                  children: items.map((item) {
                    return MoreTile(
                      icon: item.icon,
                      label: item.label,
                      onTap: () {
                        context.push(item.route);
                      },
                    );
                  }).toList(),
                ),
              ],

              SizedBox(height: spacing.md),

              const _SectionCard(
                title: 'App',
                children: [EngagementSettingsSection()],
              ),

              SizedBox(height: spacing.md),

              _SectionCard(
                title: 'System',
                children: [
                  MoreTile(
                    icon: Icons.logout,
                    label: 'Logout',
                    isDestructive: true,
                    showChevron: false,
                    onTap: () async {
                      final confirmed = await DialogService.confirm(
                        context,
                        title: 'Sign out',
                        message: 'Are you sure you want to logout?',
                        confirmText: 'Logout',
                        type: DialogType.destructive,
                      );

                      if (!confirmed) {
                        return;
                      }

                      await ref
                          .read(authProvider.notifier)
                          .logout('User Logout');
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: context.theme.cardColor,
        borderRadius: BorderRadius.circular(radius.edgeInsert),
        // boxShadow: [
        //   BoxShadow(
        //     color: colorScheme.shadow.withValues(alpha: 0.05),
        //     blurRadius: spacing.lg,
        //     offset: Offset(0, spacing.sm),
        //   ),
        // ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.small(context).copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: spacing.sm),
          ...children,
        ],
      ),
    );
  }
}
