import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ngoda/core/providers/idle_service_provider.dart';
import 'package:ngoda/core/router/app_router.dart';
import 'package:ngoda/ui/screens/lock/lock_screen.dart';
import 'package:ngoda/ui/shared/app_theme.dart';
import 'package:ngoda/ui/shared/theme_provider.dart';
import 'package:ngoda/ui/widgets/network_connection_listener.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';

class NgodaApp extends ConsumerWidget {
  const NgodaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    final isLocked = ref.watch(authProvider.select((state) => state.isLocked));

    final router = ref.watch(routerProvider);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        ref.read(idleServiceProvider).userActivity();
      },
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,

        /*
         * AppTheme requires BuildContext because
         * the theme uses the responsive design
         * system:
         *
         * AppSpacing
         * AppRadius
         * AppIconSize
         * AppTextStyles
         */
        theme: AppTheme.light(context),
        darkTheme: AppTheme.dark(context),
        themeMode: themeMode,
        routerConfig: router,
        builder: (context, child) {
          return NetworkConnectionListener(
            child: Stack(
              children: [
                child ?? const SizedBox.shrink(),

                /*
                 * LockScreen sits above the
                 * current route without replacing
                 * the application's navigation
                 * state.
                 */
                if (isLocked) const LockScreen(),
              ],
            ),
          );
        },
      ),
    );
  }
}
