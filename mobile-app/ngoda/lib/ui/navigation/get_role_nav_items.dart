import 'package:flutter/material.dart';

import 'package:ngoda/ui/navigation/nav_item.dart';

List<NavItem> getRoleNavItems(String? role, double iconSize, Color primary) {
  switch (role?.trim().toLowerCase()) {
    case 'finance':
      return [
        NavItem(
          route: '/user-dashboard',
          destination: NavigationDestination(
            icon: Icon(Icons.home_outlined, size: iconSize),
            selectedIcon: Icon(Icons.home, size: iconSize, color: primary),
            label: 'Home',
          ),
        ),
        NavItem(
          route: '/funding',
          action: () {},
          destination: NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined, size: iconSize),
            selectedIcon: Icon(
              Icons.account_balance_wallet,
              size: iconSize,
              color: primary,
            ),
            label: 'Funding',
          ),
        ),
        NavItem(
          route: '/financial-statements',
          destination: NavigationDestination(
            icon: Icon(Icons.account_balance_outlined, size: iconSize),
            selectedIcon: Icon(
              Icons.account_balance,
              size: iconSize,
              color: primary,
            ),
            label: 'Financials',
          ),
        ),
        NavItem(
          route: '/loans',
          action: () {},
          destination: NavigationDestination(
            icon: Icon(Icons.lock_outline, size: iconSize),
            selectedIcon: Icon(Icons.lock, size: iconSize, color: primary),
            label: 'SVA',
          ),
        ),
        NavItem(
          route: '/more',
          destination: NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded, size: iconSize),
            selectedIcon: Icon(
              Icons.more_horiz_rounded,
              size: iconSize,
              color: primary,
            ),
            label: 'More',
          ),
        ),
      ];

    case 'admin':
      return [
        NavItem(
          route: '/user-dashboard',
          destination: NavigationDestination(
            icon: Icon(Icons.home_outlined, size: iconSize),
            selectedIcon: Icon(Icons.home, size: iconSize, color: primary),
            label: 'Home',
          ),
        ),
        NavItem(
          route: '/userRole',
          destination: NavigationDestination(
            icon: Icon(Icons.person_3_outlined, size: iconSize),
            selectedIcon: Icon(Icons.person_3, size: iconSize, color: primary),
            label: 'Roles',
          ),
        ),
        NavItem(
          route: '/country',
          destination: NavigationDestination(
            icon: Icon(Icons.contact_page_outlined, size: iconSize),
            selectedIcon: Icon(
              Icons.contact_page,
              size: iconSize,
              color: primary,
            ),
            label: 'Country',
          ),
        ),
        NavItem(
          route: '/currency',
          destination: NavigationDestination(
            icon: Icon(Icons.monetization_on_outlined, size: iconSize),
            selectedIcon: Icon(
              Icons.monetization_on,
              size: iconSize,
              color: primary,
            ),
            label: 'Currency',
          ),
        ),
        NavItem(
          route: '/profile',
          destination: NavigationDestination(
            icon: Icon(Icons.person_outline, size: iconSize),
            selectedIcon: Icon(Icons.person, size: iconSize, color: primary),
            label: 'Profile',
          ),
        ),
      ];

    case 'agent':
      return _goldAndLoanNavigation(
        cashRoute: '/agent-cash',
        iconSize: iconSize,
        primary: primary,
      );

    case 'vendor':
      return _goldAndLoanNavigation(
        cashRoute: '/vendor-cash',
        iconSize: iconSize,
        primary: primary,
      );

    case 'merchant':
      return [
        NavItem(
          route: '/user-dashboard',
          destination: NavigationDestination(
            icon: Icon(Icons.home_outlined, size: iconSize),
            selectedIcon: Icon(Icons.home, size: iconSize, color: primary),
            label: 'Home',
          ),
        ),
        NavItem(
          route: '/merchant-cash',
          destination: NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined, size: iconSize),
            selectedIcon: Icon(
              Icons.account_balance_wallet,
              size: iconSize,
              color: primary,
            ),
            label: 'Cash',
          ),
        ),
        NavItem(
          route: '/merchant-wallet',
          destination: NavigationDestination(
            icon: Icon(Icons.wallet_outlined, size: iconSize),
            selectedIcon: Icon(Icons.wallet, size: iconSize, color: primary),
            label: 'Wallet',
          ),
        ),
        NavItem(
          route: '/merchant-commission',
          destination: NavigationDestination(
            icon: Icon(Icons.monetization_on_outlined, size: iconSize),
            selectedIcon: Icon(
              Icons.monetization_on,
              size: iconSize,
              color: primary,
            ),
            label: 'Finance',
          ),
        ),
        NavItem(
          route: '/more',
          destination: NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded, size: iconSize),
            selectedIcon: Icon(
              Icons.more_horiz_rounded,
              size: iconSize,
              color: primary,
            ),
            label: 'More',
          ),
        ),
      ];

    case 'treasury':
      return [
        NavItem(
          route: '/user-dashboard',
          destination: NavigationDestination(
            icon: Icon(Icons.home_outlined, size: iconSize),
            selectedIcon: Icon(Icons.home, size: iconSize, color: primary),
            label: 'Home',
          ),
        ),
        NavItem(
          route: '/treasury-funding',
          destination: NavigationDestination(
            icon: Icon(Icons.monetization_on_outlined, size: iconSize),
            selectedIcon: Icon(
              Icons.monetization_on,
              size: iconSize,
              color: primary,
            ),
            label: 'Funding',
          ),
        ),
        NavItem(
          route: '/treasury-wallet',
          destination: NavigationDestination(
            icon: Icon(Icons.wallet_outlined, size: iconSize),
            selectedIcon: Icon(Icons.wallet, size: iconSize, color: primary),
            label: 'Wallet',
          ),
        ),
        NavItem(
          route: '/tokens',
          destination: NavigationDestination(
            icon: Icon(Icons.token_outlined, size: iconSize),
            selectedIcon: Icon(Icons.token, size: iconSize, color: primary),
            label: 'Tokens',
          ),
        ),
        NavItem(
          route: '/more',
          destination: NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded, size: iconSize),
            selectedIcon: Icon(
              Icons.more_horiz_rounded,
              size: iconSize,
              color: primary,
            ),
            label: 'More',
          ),
        ),
      ];

    case 'compliance':
      return [
        NavItem(
          route: '/user-dashboard',
          destination: NavigationDestination(
            icon: Icon(Icons.home_outlined, size: iconSize),
            selectedIcon: Icon(Icons.home, size: iconSize, color: primary),
            label: 'Home',
          ),
        ),
        NavItem(
          route: '/kyc-review',
          destination: NavigationDestination(
            icon: Icon(Icons.verified_user_outlined, size: iconSize),
            selectedIcon: Icon(
              Icons.verified_user,
              size: iconSize,
              color: primary,
            ),
            label: 'KYC',
          ),
        ),
        NavItem(
          route: '/monitoring',
          destination: NavigationDestination(
            icon: Icon(Icons.check_box_outlined, size: iconSize),
            selectedIcon: Icon(Icons.check_box, size: iconSize, color: primary),
            label: 'Monitoring',
          ),
        ),
        NavItem(
          route: '/reports',
          destination: NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined, size: iconSize),
            selectedIcon: Icon(Icons.bar_chart, size: iconSize, color: primary),
            label: 'Reports',
          ),
        ),
        NavItem(
          route: '/more',
          destination: NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded, size: iconSize),
            selectedIcon: Icon(
              Icons.more_horiz_rounded,
              size: iconSize,
              color: primary,
            ),
            label: 'More',
          ),
        ),
      ];

    case 'accounts':
      return [
        NavItem(
          route: '/user-dashboard',
          destination: NavigationDestination(
            icon: Icon(Icons.home_outlined, size: iconSize),
            selectedIcon: Icon(Icons.home, size: iconSize, color: primary),
            label: 'Home',
          ),
        ),
        NavItem(
          route: '/funding',
          destination: NavigationDestination(
            icon: Icon(Icons.monetization_on_outlined, size: iconSize),
            selectedIcon: Icon(
              Icons.monetization_on,
              size: iconSize,
              color: primary,
            ),
            label: 'Funding',
          ),
        ),
        NavItem(
          route: '/financial-statements',
          destination: NavigationDestination(
            icon: Icon(Icons.account_balance_outlined, size: iconSize),
            selectedIcon: Icon(
              Icons.account_balance,
              size: iconSize,
              color: primary,
            ),
            label: 'Financials',
          ),
        ),
        NavItem(
          route: '/payments',
          destination: NavigationDestination(
            icon: Icon(Icons.money_outlined, size: iconSize),
            selectedIcon: Icon(Icons.money, size: iconSize, color: primary),
            label: 'Payments',
          ),
        ),
        NavItem(
          route: '/more',
          destination: NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded, size: iconSize),
            selectedIcon: Icon(
              Icons.more_horiz_rounded,
              size: iconSize,
              color: primary,
            ),
            label: 'More',
          ),
        ),
      ];

    case 'customer':
      return _goldAndLoanNavigation(
        cashRoute: '/cash',
        iconSize: iconSize,
        primary: primary,
      );

    default:
      return const [];
  }
}

List<NavItem> _goldAndLoanNavigation({
  required String cashRoute,
  required double iconSize,
  required Color primary,
}) {
  return [
    NavItem(
      route: '/user-dashboard',
      destination: NavigationDestination(
        icon: Icon(Icons.home_outlined, size: iconSize),
        selectedIcon: Icon(Icons.home, size: iconSize, color: primary),
        label: 'Home',
      ),
    ),
    NavItem(
      route: cashRoute,
      destination: NavigationDestination(
        icon: Icon(Icons.account_balance_wallet_outlined, size: iconSize),
        selectedIcon: Icon(
          Icons.account_balance_wallet,
          size: iconSize,
          color: primary,
        ),
        label: 'Cash',
      ),
    ),
    NavItem(
      route: 'gold',
      action: () {},
      destination: NavigationDestination(
        icon: Icon(Icons.workspace_premium_outlined, size: iconSize),
        selectedIcon: Icon(
          Icons.workspace_premium,
          size: iconSize,
          color: Colors.amber,
        ),
        label: 'Gold',
      ),
    ),
    NavItem(
      route: 'loans',
      action: () {},
      destination: NavigationDestination(
        icon: Icon(Icons.account_balance_outlined, size: iconSize),
        selectedIcon: Icon(
          Icons.account_balance,
          size: iconSize,
          color: primary,
        ),
        label: 'SVA',
      ),
    ),
    NavItem(
      route: '/more',
      destination: NavigationDestination(
        icon: Icon(Icons.more_horiz_rounded, size: iconSize),
        selectedIcon: Icon(
          Icons.more_horiz_rounded,
          size: iconSize,
          color: primary,
        ),
        label: 'More',
      ),
    ),
  ];
}
