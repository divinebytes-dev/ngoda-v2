import 'package:go_router/go_router.dart';

import 'package:ngoda/core/router/utils/custom_page_transition.dart';
import 'package:ngoda/landing_screen.dart';
import 'package:ngoda/ui/screens/auth/login/login_screen.dart';
import 'package:ngoda/ui/screens/auth/password-reset/forgot_password_screen.dart';
import 'package:ngoda/ui/screens/auth/password-reset/new_password_screen.dart';
import 'package:ngoda/ui/screens/auth/password-reset/password_otp_screen.dart';
import 'package:ngoda/ui/screens/auth/registration/registration_screen.dart';
import 'package:ngoda/ui/screens/lock/lock_screen.dart';
import 'package:ngoda/ui/screens/pin-setup/setup_pin_screen.dart';

final List<GoRoute> authRoutes = [
  /*
   * Application entry.
   */
  GoRoute(path: '/', builder: (_, _) => const LandingScreen()),

  // /*
  //  * Authentication.
  //  */
  GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
  GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),

  // /*
  //  * Local application security.
  //  */
  GoRoute(path: '/setup-pin', builder: (_, _) => const SetupPinScreen()),

  GoRoute(path: '/lock', builder: (_, _) => const LockScreen()),

  // /*
  //  * Password recovery entry.
  //  */
  GoRoute(
    path: '/forgot-password',
    pageBuilder: (context, state) {
      return slidePage(const ForgotPasswordScreen(), state);
    },
  ),

  /*
   * Phone recovery verification.
   *
   * The phone number is supplied by
   * ForgotPasswordScreen.
   */
  GoRoute(
    path: '/reset-password-otp',
    pageBuilder: (context, state) {
      final phone = state.extra as String;

      return slidePage(ResetPasswordOtpScreen(phone: phone), state);
    },
  ),

  /*
   * Password recovery completion.
   *
   * Used after either:
   *
   * - email recovery establishes a recovery
   *   Supabase session; or
   *
   * - phone OTP verification establishes the
   *   required Supabase session.
   */
  GoRoute(
    path: '/new-password',
    pageBuilder: (context, state) {
      return slidePage(const NewPasswordScreen(), state);
    },
  ),
];
