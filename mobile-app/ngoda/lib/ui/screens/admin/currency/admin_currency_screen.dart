import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/widgets/action_tile.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';

class AdminCurrencyScreen extends ConsumerWidget {
  const AdminCurrencyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 3),
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'Supported Currency'),

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
                            title: 'Supported Currency List',
                            subtitle: 'List supported currencies',
                            icon: Icons.list_rounded,
                            color: Colors.purple,
                            onTap: () {
                              context.push('/currency/currency-list');
                            },
                          ),

                          SizedBox(height: spacing.md),

                          ActionTile(
                            title: 'Add Supported Currency',
                            subtitle: 'Add supported currency',
                            icon: Icons.add_card_outlined,
                            color: Colors.green,
                            onTap: () {
                              context.push('/currency/add-supported-currency');
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
