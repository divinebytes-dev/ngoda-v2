import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import 'package:ngoda/core/providers/analytics_service_provider.dart';
import 'package:ngoda/core/providers/hive_service_provider.dart';
import 'package:ngoda/core/providers/idle_service_provider.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/hive_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_logo.dart';
import 'package:ngoda/ui/widgets/input_field.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController identifierCtrl = TextEditingController();

  final TextEditingController passwordCtrl = TextEditingController();

  final Logger log = Logger('Login');

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreLastIdentifier();
    });
  }

  void _restoreLastIdentifier() {
    final hive = ref.read(hiveServiceProvider);

    final identifier = hive
        .getItem<String>(HiveBoxName.lastLoginIdentifier, 'lastLoginIdentifier')
        .result;

    if (identifier == null || identifier.trim().isEmpty) {
      return;
    }

    final value = identifier.trim();

    identifierCtrl.text = value;

    ref.read(authProvider.notifier).updateLoginIdentifier(value);
  }

  @override
  void dispose() {
    identifierCtrl.dispose();
    passwordCtrl.dispose();

    super.dispose();
  }

  /*
   * ------------------------------------------------------------
   * LOGIN
   * ------------------------------------------------------------
   */

  Future<void> handleLogin() async {
    FocusScope.of(context).unfocus();

    try {
      /*
       * The notifier already owns the current
       * identifier and password because the
       * fields update UserAuthState as the user
       * types.
       *
       * We therefore do not pass the controller
       * values again here.
       */
      await ref.read(authProvider.notifier).login();

      if (!mounted) {
        return;
      }

      /*
       * PIN remains device-local.
       *
       * After authentication we check whether
       * this device already has a PIN.
       */
      final hive = ref.read(hiveServiceProvider);

      final pin = hive.getItem<String>(HiveBoxName.auth, 'pin').result;

      /*
       * Start inactivity monitoring only after
       * successful authentication.
       */
      ref.read(idleServiceProvider).start();

      final user = getCurrentUser();

      ref
          .read(analyticsServiceProvider)
          .logUserLogin('mobile', user.userId ?? '');

      if (!mounted) {
        return;
      }

      /*
       * A newly authenticated device without
       * a PIN must complete PIN setup before
       * entering the application.
       *
       * authRedirect also protects this globally,
       * but handling it here gives login an
       * explicit immediate destination.
       */
      if (pin == null || pin.trim().isEmpty) {
        context.go('/setup-pin');

        return;
      }

      context.go('/user-dashboard');
    } catch (error, stackTrace) {
      log.warning('Login failed.', error, stackTrace);

      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: 'Login failed:\n$error');
    }
  }

  /*
   * ------------------------------------------------------------
   * NAVIGATION
   * ------------------------------------------------------------
   */

  void handleForgotPassword() {
    FocusScope.of(context).unfocus();

    context.push('/forgot-password');
  }

  /*
   * ------------------------------------------------------------
   * VIEW
   * ------------------------------------------------------------
   */

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final radius = context.radius;

    final iconSize = context.iconSize;

    final colorScheme = context.colorScheme;

    final state = ref.watch(authProvider);

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusScope.of(context).unfocus();
          },
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
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
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
                            'Login',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.large(
                              context,
                            ).copyWith(fontWeight: FontWeight.w700),
                          ),

                          SizedBox(height: spacing.lg),

                          /*
                           * LOGIN IDENTIFIER
                           *
                           * One field accepts either
                           * email or phone.
                           *
                           * AuthNotifier determines
                           * which type it is.
                           */
                          InputField(
                            controller: identifierCtrl,
                            placeholder: 'Email / phone',
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            onChanged: ref
                                .read(authProvider.notifier)
                                .updateLoginIdentifier,
                          ),

                          /*
                           * Standard spacing between
                           * consecutive input fields.
                           */
                          SizedBox(height: spacing.sm),

                          InputField(
                            controller: passwordCtrl,
                            placeholder: 'Password',
                            keyboardType: TextInputType.text,
                            obscureText: true,
                            showPasswordToggle: true,
                            textInputAction: TextInputAction.done,
                            onChanged: ref
                                .read(authProvider.notifier)
                                .updateLoginPassword,
                          ),

                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: state.isLoading
                                  ? null
                                  : handleForgotPassword,
                              child: Text(
                                'Forgot password?',
                                style: AppTextStyles.tiny(context).copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),

                          /*
                           * Validation and request
                           * errors are owned by
                           * UserAuthState.
                           */
                          if (state.error != null) ...[
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(spacing.sm),
                              decoration: BoxDecoration(
                                color: colorScheme.error.withValues(
                                  alpha: 0.05,
                                ),
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

                            SizedBox(height: spacing.sm),
                          ],

                          SizedBox(height: spacing.md),

                          AppButton(
                            text: 'Login',
                            isProcessing: state.isLoading,
                            isDisabled: !state.isValid || state.isLoading,
                            onPressed: state.isValid && !state.isLoading
                                ? handleLogin
                                : null,
                          ),

                          SizedBox(height: spacing.sm),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Don't have an account? ",
                                style: AppTextStyles.tiny(
                                  context,
                                ).copyWith(color: colorScheme.onSurfaceVariant),
                              ),

                              GestureDetector(
                                onTap: state.isLoading
                                    ? null
                                    : () {
                                        context.go('/register');
                                      },
                                child: Text(
                                  'Register',
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
      ),
    );
  }
}
