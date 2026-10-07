import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/core/providers/hive_service_provider.dart';
import 'package:ngoda/services/hive_service.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';

String? authRedirect(BuildContext context, GoRouterState state) {
  final container = ProviderScope.containerOf(context);

  final auth = container.read(authProvider);

  final isAuthenticated = auth.isAuthenticated;

  final location = state.matchedLocation;

  /*
   * Public authentication routes.
   */
  final isPublicAuthRoute =
      location == '/login' ||
      location == '/register' ||
      location == '/forgot-password' ||
      location == '/reset-password-otp';

  /*
   * Password recovery completion.
   *
   * This route is intentionally separate
   * because the recovery flow establishes
   * a Supabase session before reaching it.
   */
  final isPasswordResetRoute = location == '/new-password';

  /*
   * PIN setup is an authenticated route,
   * but it must remain accessible before
   * the user has configured a PIN.
   */
  final isSetupPinRoute = location == '/setup-pin';

  /*
   * Lock screen is only meaningful for an
   * authenticated user who already has a PIN.
   */
  final isLockRoute = location == '/lock';

  /*
   * ------------------------------------------------------------
   * UNAUTHENTICATED
   * ------------------------------------------------------------
   */

  if (!isAuthenticated) {
    /*
     * Landing page remains available.
     */
    if (location == '/') {
      return null;
    }

    /*
     * Login, registration and recovery
     * entry routes remain available.
     */
    if (isPublicAuthRoute) {
      return null;
    }

    /*
     * /new-password requires an authenticated
     * recovery session.
     */
    if (isPasswordResetRoute) {
      return '/forgot-password';
    }

    /*
     * PIN setup and lock screen require an
     * authenticated application session.
     */
    if (isSetupPinRoute || isLockRoute) {
      return '/';
    }

    /*
     * All remaining routes are protected.
     */
    return '/';
  }

  /*
   * ------------------------------------------------------------
   * AUTHENTICATED
   * ------------------------------------------------------------
   */

  /*
   * Password recovery must take precedence
   * over the normal application PIN guard.
   *
   * A password-recovery Supabase session may
   * exist before the normal application login
   * flow has completed.
   */
  if (isPasswordResetRoute) {
    return null;
  }

  /*
   * Determine whether this authenticated user
   * has configured the local application PIN.
   */
  final hive = container.read(hiveServiceProvider);

  final storedPin = hive.getItem<String>(HiveBoxName.auth, 'pin').result;

  final hasPin = storedPin != null && storedPin.trim().isNotEmpty;

  /*
   * ------------------------------------------------------------
   * PIN NOT CONFIGURED
   * ------------------------------------------------------------
   *
   * An authenticated user must configure the
   * application PIN before entering any normal
   * protected application route.
   */
  if (!hasPin) {
    /*
     * Already on the PIN setup screen.
     */
    if (isSetupPinRoute) {
      return null;
    }

    /*
     * Force PIN setup before dashboard,
     * wallet, transactions, More, etc.
     */
    return '/setup-pin';
  }

  /*
   * ------------------------------------------------------------
   * PIN CONFIGURED
   * ------------------------------------------------------------
   */

  /*
   * PIN setup is no longer required.
   */
  if (isSetupPinRoute) {
    return '/user-dashboard';
  }

  /*
   * The lock screen remains accessible.
   *
   * Whether the application is currently
   * locked is controlled by the auth/idle
   * lifecycle rather than by PIN existence.
   */
  if (isLockRoute) {
    return null;
  }

  /*
   * An authenticated user should not return
   * to login or registration.
   */
  if (location == '/login' || location == '/register') {
    return '/user-dashboard';
  }

  /*
   * Authenticated landing-page access goes
   * directly into the application.
   */
  if (location == '/') {
    return '/user-dashboard';
  }

  /*
   * All other authenticated routes continue
   * normally.
   */
  return null;
}
