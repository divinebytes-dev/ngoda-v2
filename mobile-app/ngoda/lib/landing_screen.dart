import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/shared/theme_provider.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_logo.dart';

class LandingScreen extends ConsumerWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;

    final themeMode = ref.watch(themeModeProvider);

    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(spacing.xl),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: isDark ? 'Use light theme' : 'Use dark theme',
                  icon: Icon(
                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    size: context.iconSize.large,
                  ),
                  onPressed: () {
                    ref.read(themeModeProvider.notifier).toggle();
                  },
                ),
              ),

              const Spacer(),

              const AppLogo(),

              SizedBox(height: spacing.md),

              Text(
                'Real Asset. Real Freedom',
                textAlign: TextAlign.center,
                style: AppTextStyles.brandTagline(context),
              ),

              SizedBox(height: spacing.sm),

              Text(
                'Own tokenised gold backed by physical reserves. '
                'Fully audited. Globally accessible.',
                textAlign: TextAlign.center,
                style: AppTextStyles.small(context).copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),

              const Spacer(),

              AppButton(
                text: 'Login',
                onPressed: () {
                  context.go('/login');
                },
              ),

              SizedBox(height: spacing.md),

              AppButton(
                text: 'Create Account',
                isPrimary: false,
                onPressed: () {
                  context.go('/register');
                },
              ),

              SizedBox(height: spacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
