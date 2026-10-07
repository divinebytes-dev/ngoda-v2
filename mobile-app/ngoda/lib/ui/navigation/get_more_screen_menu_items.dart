import 'package:flutter/material.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/navigation/profile_screen_menu_item.dart';

final Map<UserRole, List<ProfileScreenMenuItem>> moreActivityMenu = {
  UserRole.finance: [
    ProfileScreenMenuItem(
      icon: Icons.account_balance_outlined,
      label: 'GL Balances',
      route: '/gl-balances',
    ),
    ProfileScreenMenuItem(
      icon: Icons.receipt_long_outlined,
      label: 'Recent Transactions',
      route: '/recent-transactions',
    ),
    ProfileScreenMenuItem(
      icon: Icons.approval_outlined,
      label: 'Approve Tax Settlement',
      route: '/approve-tax-settlement',
    ),
    ProfileScreenMenuItem(
      icon: Icons.approval_outlined,
      label: 'Approve Commission Settlement',
      route: '/approve-commission-settlement',
    ),
    ProfileScreenMenuItem(
      icon: Icons.date_range_outlined,
      label: 'Fiscal Periods',
      route: '/more-screen/fiscal-periods',
    ),
  ],

  UserRole.treasury: [
    ProfileScreenMenuItem(
      icon: Icons.receipt_long_outlined,
      label: 'Transactions',
      route: '/transactions',
    ),
    ProfileScreenMenuItem(
      icon: Icons.account_balance_wallet_outlined,
      label: 'Token Balances',
      route: '/tokens/balances',
    ),
    ProfileScreenMenuItem(
      icon: Icons.link_outlined,
      label: 'Incomplete Blockchain',
      route: '/tokens/incomplete-blockchain-transactions',
    ),
    ProfileScreenMenuItem(
      icon: Icons.how_to_reg_outlined,
      label: 'Approve Credit Agent',
      route: '/approve-credit-agent',
    ),
  ],

  UserRole.agent: [
    ProfileScreenMenuItem(
      icon: Icons.bar_chart_outlined,
      label: 'Financial Behaviour',
      route: '/financial-intelligence',
    ),
    ProfileScreenMenuItem(
      icon: Icons.workspace_premium_outlined,
      label: 'Financial Badges',
      route: '/financial-intelligence/badges',
    ),
    ProfileScreenMenuItem(
      icon: Icons.account_balance_wallet_outlined,
      label: 'Wallet',
      route: '/agent-wallet',
    ),
    ProfileScreenMenuItem(
      icon: Icons.payments_outlined,
      label: 'Commission',
      route: '/commission-summary',
    ),
    ProfileScreenMenuItem(
      icon: Icons.receipt_long_outlined,
      label: 'Transactions',
      route: '/transactions',
    ),
    ProfileScreenMenuItem(
      icon: Icons.person_add_alt,
      label: 'Referral Link',
      route: '/share-referral-link',
    ),
    ProfileScreenMenuItem(
      icon: Icons.stars_outlined,
      label: 'Ngoda Rewards',
      route: '/rewards',
    ),
  ],

  UserRole.merchant: [
    ProfileScreenMenuItem(
      icon: Icons.receipt_long_outlined,
      label: 'Transactions',
      route: '/transactions',
    ),
    ProfileScreenMenuItem(
      icon: Icons.person_add_alt,
      label: 'Referral Link',
      route: '/share-referral-link',
    ),
  ],

  UserRole.vendor: [
    ProfileScreenMenuItem(
      icon: Icons.bar_chart_outlined,
      label: 'Financial Behaviour',
      route: '/financial-intelligence',
    ),
    ProfileScreenMenuItem(
      icon: Icons.workspace_premium_outlined,
      label: 'Financial Badges',
      route: '/financial-intelligence/badges',
    ),
    ProfileScreenMenuItem(
      icon: Icons.account_balance_wallet_outlined,
      label: 'Wallet',
      route: '/vendor-wallet',
    ),
    ProfileScreenMenuItem(
      icon: Icons.payments_outlined,
      label: 'Commission',
      route: '/commission-summary',
    ),
    ProfileScreenMenuItem(
      icon: Icons.receipt_long_outlined,
      label: 'Transactions',
      route: '/transactions',
    ),
    ProfileScreenMenuItem(
      icon: Icons.person_add_alt,
      label: 'Referral Link',
      route: '/share-referral-link',
    ),
    ProfileScreenMenuItem(
      icon: Icons.stars_outlined,
      label: 'Ngoda Rewards',
      route: '/rewards',
    ),
  ],

  UserRole.admin: [
    ProfileScreenMenuItem(
      icon: Icons.receipt_long_outlined,
      label: 'Transactions',
      route: '/transactions',
    ),
  ],

  UserRole.accounts: [
    ProfileScreenMenuItem(
      icon: Icons.receipt_long_outlined,
      label: 'Recent Transactions',
      route: '/recent-transactions',
    ),
    ProfileScreenMenuItem(
      icon: Icons.approval_outlined,
      label: 'Approve Token Adjustment',
      route: '/tokens/approve-adjustment',
    ),
  ],

  UserRole.customer: [
    ProfileScreenMenuItem(
      icon: Icons.bar_chart_outlined,
      label: 'Financial Behaviour',
      route: '/financial-intelligence',
    ),
    ProfileScreenMenuItem(
      icon: Icons.workspace_premium_outlined,
      label: 'Financial Badges',
      route: '/financial-intelligence/badges',
    ),
    ProfileScreenMenuItem(
      icon: Icons.account_balance_wallet_outlined,
      label: 'Wallet',
      route: '/customer-wallet',
    ),
    ProfileScreenMenuItem(
      icon: Icons.receipt_long_outlined,
      label: 'Transactions',
      route: '/transactions',
    ),
    ProfileScreenMenuItem(
      icon: Icons.person_add_alt,
      label: 'Referral Link',
      route: '/share-referral-link',
    ),
    ProfileScreenMenuItem(
      icon: Icons.stars_outlined,
      label: 'Ngoda Rewards',
      route: '/rewards',
    ),
  ],
};
