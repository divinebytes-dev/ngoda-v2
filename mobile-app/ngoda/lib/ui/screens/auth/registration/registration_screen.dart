import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:ngoda/data_models/country/supported_country.dart';

import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/screens/auth/providers/supported_countries_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_dropdown_field.dart';
import 'package:ngoda/ui/widgets/app_logo.dart';
import 'package:ngoda/ui/widgets/app_state_view.dart';
import 'package:ngoda/ui/widgets/input_field.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final TextEditingController emailCtrl = TextEditingController();

  final TextEditingController phoneCtrl = TextEditingController();

  final TextEditingController passwordCtrl = TextEditingController();

  final Logger log = Logger('Register');

  @override
  void dispose() {
    emailCtrl.dispose();
    phoneCtrl.dispose();
    passwordCtrl.dispose();

    super.dispose();
  }

  Future<void> handleRegister() async {
    try {
      await ref.read(authProvider.notifier).register();

      if (!mounted) {
        return;
      }

      log.fine('Registration completed successfully.');

      await DialogService.success(
        context,
        message:
            'Registration Successful.\n'
            'Activation link sent to your inbox',
      );

      if (!mounted) {
        return;
      }

      context.go('/login');

      Future.microtask(() {
        ref.read(authProvider.notifier).logout('Done Registration');
      });
    } catch (error, stackTrace) {
      log.warning('Registration failed.', error, stackTrace);

      if (!mounted) {
        return;
      }

      await DialogService.error(
        context,
        message: 'Registration failed:\n$error',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final state = ref.watch(authProvider);

    final countries = ref.watch(supportedCountriesProvider);

    final countryResponse = countries.value;

    if (countryResponse?.error != null) {
      return Scaffold(
        body: SafeArea(
          child: AppStateView(
            title: 'Countries unavailable',
            message:
                'We could not load the supported countries. Please try again.',
            icon: Icons.public_off_outlined,
            iconColor: colorScheme.error,
            action: AppButton(
              text: 'Go Back',
              isPrimary: false,
              onPressed: () {
                context.pop();
              },
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.xxl,
          ),
          child: Column(
            children: [
              SizedBox(height: spacing.xxxxl),

              const AppLogo(),

              SizedBox(height: spacing.sm),

              Text(
                'Gold is still the measure of wealth',
                textAlign: TextAlign.center,
                style: AppTextStyles.small(
                  context,
                ).copyWith(color: colorScheme.onSurfaceVariant),
              ),

              SizedBox(height: spacing.xxl),

              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    padding: EdgeInsets.all(spacing.md),
                    decoration: BoxDecoration(
                      color: context.theme.cardColor,
                      borderRadius: BorderRadius.circular(radius.cardRadius),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Create Account',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.large(
                            context,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),

                        SizedBox(height: spacing.lg),

                        InputField(
                          controller: emailCtrl,
                          placeholder: 'Email',
                          keyboardType: TextInputType.emailAddress,
                          onChanged: (value) {
                            ref.read(authProvider.notifier).updateEmail(value);
                          },
                        ),

                        SizedBox(height: spacing.sm),

                        InputField(
                          controller: phoneCtrl,
                          placeholder: 'Phone number',
                          keyboardType: TextInputType.phone,
                          onChanged: (value) {
                            ref
                                .read(authProvider.notifier)
                                .updatePhoneNumber(value);
                          },
                        ),

                        SizedBox(height: spacing.sm),

                        InputField(
                          controller: passwordCtrl,
                          placeholder: 'Password',
                          keyboardType: TextInputType.text,
                          obscureText: true,
                          showPasswordToggle: true,
                          onChanged: (value) {
                            ref
                                .read(authProvider.notifier)
                                .updatePassword(value);
                          },
                        ),

                        SizedBox(height: spacing.sm),

                        if (countryResponse?.result != null)
                          AppDropdownField<SupportedCountry>(
                            selected: state.country,
                            values: countryResponse!.result!,
                            hint: 'Select country',
                            labelBuilder: (country) {
                              return country.name;
                            },
                            onSelect: state.isLoading
                                ? null
                                : (country) {
                                    ref
                                        .read(authProvider.notifier)
                                        .updateCountry(country);
                                  },
                          ),

                        if (state.error != null) ...[
                          SizedBox(height: spacing.sm),

                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(spacing.sm),
                            decoration: BoxDecoration(
                              color: colorScheme.error.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(
                                radius.borderRadius,
                              ),
                              border: Border.all(
                                color: colorScheme.error.withValues(
                                  alpha: 0.20,
                                ),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  size: iconSize.small,
                                  color: colorScheme.error,
                                ),

                                SizedBox(width: spacing.sm),

                                Expanded(
                                  child: Text(
                                    state.error!,
                                    style: AppTextStyles.small(
                                      context,
                                    ).copyWith(color: colorScheme.error),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        SizedBox(height: spacing.lg),

                        AppButton(
                          text: 'Register',
                          isProcessing: state.isLoading,
                          onPressed: state.isValid && state.country != null
                              ? () async {
                                  await handleRegister();
                                }
                              : null,
                        ),

                        SizedBox(height: spacing.sm),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Have an account? ',
                              style: AppTextStyles.tiny(
                                context,
                              ).copyWith(color: colorScheme.onSurfaceVariant),
                            ),

                            GestureDetector(
                              onTap: state.isLoading
                                  ? null
                                  : () {
                                      context.go('/login');
                                    },
                              child: Text(
                                'Login',
                                style: AppTextStyles.tiny(context).copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
