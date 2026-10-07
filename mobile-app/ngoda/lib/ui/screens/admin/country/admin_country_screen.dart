import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/widgets/action_tile.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';

class AdminCountryScreen extends ConsumerWidget {
  const AdminCountryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 2),
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'Operational Country'),

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
                            title: 'Operational Countries',
                            subtitle: 'List operational countries',
                            icon: Icons.list_rounded,
                            color: Colors.purple,
                            onTap: () {
                              context.push('/country/operational-countries');
                            },
                          ),

                          SizedBox(height: spacing.md),

                          ActionTile(
                            title: 'Add Operational Country',
                            subtitle: 'Add operational country',
                            icon: Icons.add_location_alt_outlined,
                            color: Colors.green,
                            onTap: () {
                              context.push('/country/add-operational-country');
                            },
                          ),

                          SizedBox(height: spacing.md),

                          ActionTile(
                            title: 'Edit Country Currencies',
                            subtitle: 'Update operational country currencies',
                            icon: Icons.mode_edit_outline_sharp,
                            color: Colors.orange,
                            onTap: () {
                              context.push('/country/add-country-currency');
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
