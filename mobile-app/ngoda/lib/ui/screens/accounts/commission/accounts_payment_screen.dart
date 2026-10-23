import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/widgets/action_tile.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/currency_tabs.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';

class AccountsPaymentScreen extends ConsumerWidget {
  const AccountsPaymentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        bottomNavigationBar: const BottomNav(currentIndex: 3),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(radius.borderRadius),
            child: Builder(
              builder: (context) {
                return Column(
                  children: [
                    const ScreenHeader(
                      title: 'Payments',
                      subtitle: 'Agent commission and government tax',
                    ),
                    SizedBox(height: spacing.sm),
                    CurrencyTabs(
                      controller: DefaultTabController.of(context),
                      currencies: const ['Agent Commission', 'Government Tax'],
                    ),
                    SizedBox(height: spacing.md),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _PaymentActions(
                            storageKey: 'agent-commission-actions',
                            children: [
                              ActionTile(
                                title: 'Current Period Commission',
                                subtitle:
                                    'Current period totals and pending commission',
                                icon: Icons.payments,
                                color: colorScheme.primary,
                                onTap: () {
                                  context.go(
                                    '/payments/current-period-commission',
                                  );
                                },
                              ),
                              ActionTile(
                                title: 'Pending Commission',
                                subtitle: 'View outstanding commission batches',
                                icon: Icons.payments_outlined,
                                color: colorScheme.primary,
                                onTap: () {
                                  context.go('/payments/commission-summary');
                                },
                              ),
                              ActionTile(
                                title: 'Settle Commission',
                                subtitle: 'Pay approved commission batches',
                                icon: Icons.payments,
                                color: colorScheme.primary,
                                onTap: () {
                                  context.go(
                                    '/payments/settle-commission-batch',
                                  );
                                },
                              ),
                              ActionTile(
                                title: 'Settled Commission',
                                subtitle: 'View settled commission batches',
                                icon: Icons.history,
                                color: colorScheme.primary,
                                onTap: () {
                                  context.go(
                                    '/payments/settled-commission-batches',
                                  );
                                },
                              ),
                            ],
                          ),
                          _PaymentActions(
                            storageKey: 'government-tax-actions',
                            children: [
                              ActionTile(
                                title: 'Current Period Tax',
                                subtitle:
                                    'View tax accumulated in the current period',
                                icon: Icons.account_balance,
                                color: colorScheme.primary,
                                onTap: () {
                                  context.go('/payments/current-period-tax');
                                },
                              ),
                              ActionTile(
                                title: 'Pending Tax',
                                subtitle:
                                    'View outstanding government tax batches',
                                icon: Icons.payments_outlined,
                                color: colorScheme.primary,
                                onTap: () {
                                  context.go('/payments/tax-summary');
                                },
                              ),
                              ActionTile(
                                title: 'Settle Tax',
                                subtitle: 'Pay approved government tax batches',
                                icon: Icons.payments,
                                color: colorScheme.primary,
                                onTap: () {
                                  context.go('/payments/settle-tax-payment');
                                },
                              ),
                              ActionTile(
                                title: 'Settled Tax',
                                subtitle: 'View settled government tax batches',
                                icon: Icons.history,
                                color: colorScheme.primary,
                                onTap: () {
                                  context.go('/payments/settled-tax-payments');
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentActions extends StatelessWidget {
  const _PaymentActions({required this.storageKey, required this.children});

  final String storageKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: spacing.md),
      child: ListView.separated(
        key: PageStorageKey<String>(storageKey),
        padding: EdgeInsets.only(bottom: spacing.lg),
        itemCount: children.length,
        separatorBuilder: (_, _) => SizedBox(height: spacing.sm),
        itemBuilder: (context, index) => children[index],
      ),
    );
  }
}

// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';
// import 'package:ngoda/ui/extensions/app_size.dart';
// import 'package:ngoda/ui/extensions/theme_extension.dart';
// import 'package:ngoda/ui/widgets/action_tile.dart';
// import 'package:ngoda/ui/widgets/bottom_nav.dart';
// import 'package:ngoda/ui/widgets/screen_header.dart';

// class AccountsPaymentScreen extends ConsumerWidget {
//   const AccountsPaymentScreen({super.key});

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final spacing = context.spacing;
//     final radius = context.radius;
//     final colorScheme = context.colorScheme;

//     return Scaffold(
//       bottomNavigationBar: const BottomNav(currentIndex: 3),
//       body: SafeArea(
//         child: Padding(
//           padding: EdgeInsets.all(radius.borderRadius),
//           child: Column(
//             children: [
//               const ScreenHeader(
//                 title: 'Payment Screen',
//                 subtitle: 'Agents commission and Government tax payment',
//               ),
//               SizedBox(height: spacing.sm),
//               Expanded(
//                 child: SingleChildScrollView(
//                   padding: EdgeInsets.only(bottom: spacing.lg),
//                   child: Column(
//                     children: [
//                       ActionTile(
//                         title: 'Current Period Agents Commission',
//                         subtitle:
//                             'Current period pending agents commission payment',
//                         icon: Icons.payments,
//                         color: colorScheme.primary,
//                         onTap: () {
//                           context.go('/payments/current-period-commission');
//                         },
//                       ),
//                       SizedBox(height: spacing.sm),
//                       ActionTile(
//                         title: 'Pending Agents Commission',
//                         subtitle: 'Fetch pending agents commission',
//                         icon: Icons.payments_outlined,
//                         color: colorScheme.primary,
//                         onTap: () {
//                           context.go('/payments/commission-summary');
//                         },
//                       ),
//                       SizedBox(height: spacing.sm),

//                       ActionTile(
//                         title: 'Settle Agents Commission',
//                         subtitle: 'Settle agent commission payment batch',
//                         icon: Icons.payments,
//                         color: colorScheme.primary,
//                         onTap: () {
//                           context.go('/payments/settle-commission-batch');
//                         },
//                       ),
//                       SizedBox(height: spacing.sm),
//                       ActionTile(
//                         title: 'Settled Agents Commission',
//                         subtitle: 'Settled agent commission payment batches',
//                         icon: Icons.payments,
//                         color: colorScheme.primary,
//                         onTap: () {
//                           context.go('/payments/settled-commission-batches');
//                         },
//                       ),
//                       SizedBox(height: spacing.sm),
//                       const Divider(),
//                       SizedBox(height: spacing.sm),
//                       ActionTile(
//                         title: 'Current Period Government Tax',
//                         subtitle: 'Current period pending government tax',
//                         icon: Icons.payments,
//                         color: colorScheme.primary,
//                         onTap: () {
//                           context.go('/payments/current-period-tax');
//                         },
//                       ),
//                       SizedBox(height: spacing.sm),
//                       ActionTile(
//                         title: 'Pending Government Tax',
//                         subtitle: 'Fetch pending government tax payment',
//                         icon: Icons.payments_outlined,
//                         color: colorScheme.primary,
//                         onTap: () {
//                           context.go('/payments/tax-summary');
//                         },
//                       ),
//                       SizedBox(height: spacing.sm),

//                       ActionTile(
//                         title: 'Settle Government Tax',
//                         subtitle: 'Settle government tax batch',
//                         icon: Icons.payments_outlined,
//                         color: colorScheme.primary,
//                         onTap: () {
//                           context.go('/payments/settle-tax-payment');
//                         },
//                       ),
//                       SizedBox(height: spacing.sm),
//                       ActionTile(
//                         title: 'Settled Government Tax',
//                         subtitle: 'Settled government tax batches',
//                         icon: Icons.payments,
//                         color: colorScheme.primary,
//                         onTap: () {
//                           context.go('/payments/settled-tax-payments');
//                         },
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
