import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/navigation/get_role_nav_items.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class BottomNav extends ConsumerWidget {
  final int currentIndex;

  const BottomNav({super.key, required this.currentIndex});

  void _handleTap(BuildContext context, String role, int index) {
    final route = _routeFor(role, index);

    if (route == null) {
      return;
    }

    context.go(route);
  }

  String? _routeFor(String role, int index) {
    final routes = switch (role) {
      'customer' => const [
        '/user-dashboard',
        '/customer-cash',
        '/gold',
        '/loans',
        '/more',
      ],

      'admin' => const [
        '/user-dashboard',
        '/user-role',
        '/country',
        '/currency',
        '/more',
      ],

      'agent' => const [
        '/user-dashboard',
        '/agent-cash',
        '/gold',
        '/loans',
        '/more',
      ],

      'merchant' => const [
        '/user-dashboard',
        '/merchant-cash',
        '/merchant-wallet',
        '/commission-summary',
        '/more',
      ],

      'vendor' => const [
        '/user-dashboard',
        '/vendor-cash',
        '/gold',
        '/loans',
        '/more',
      ],

      'finance' => const [
        '/user-dashboard',
        '/funding',
        '/financial-statements',
        '/finance-loans',
        '/more',
      ],

      'treasury' => const [
        '/user-dashboard',
        '/treasury-funding',
        '/treasury-wallet',
        '/tokens',
        '/more',
      ],

      'accounts' => const [
        '/user-dashboard',
        '/accounts-funding',
        '/financial-statements',
        '/payments',
        '/more',
      ],

      'compliance' => const [
        '/user-dashboard',
        '/kyc-review',
        '/monitoring',
        '/reports',
        '/more',
      ],

      _ => const <String>[],
    };

    if (index < 0 || index >= routes.length) {
      return null;
    }

    return routes[index];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = Logger('BottomNav');

    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final decoded = getCurrentUser();

    final role = decoded.role?.trim().toLowerCase() ?? 'undefined';

    final items = getRoleNavItems(role, iconSize.large, colorScheme.primary);

    log.fine('Bottom navigation role: $role');

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedIndex = currentIndex >= 0 && currentIndex < items.length
        ? currentIndex
        : 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.margin,
        0,
        spacing.margin,
        spacing.margin,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius.edgeInsert),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.08),
              blurRadius: spacing.lg,
              offset: Offset(0, spacing.sm),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius.edgeInsert),
          child: NavigationBar(
            height: spacing.buttonHeight + spacing.lg,
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) {
              _handleTap(context, role, index);
            },
            backgroundColor: context.theme.cardColor,
            indicatorColor: colorScheme.primary.withValues(alpha: 0.12),
            indicatorShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius.borderRadius),
            ),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((
              states,
            ) {
              final isSelected = states.contains(WidgetState.selected);

              return AppTextStyles.tiny(context).copyWith(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              );
            }),
            destinations: items.map((item) => item.destination).toList(),
          ),
        ),
      ),
    );
  }
}
