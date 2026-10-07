// import 'dart:async';

// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:ngoda/data_models/gamefication/gamification.dart';
// import 'package:ngoda/ui/screens/gamification/provider/gamification_notifier_provider.dart';
// import 'package:ngoda/ui/screens/gamification/state/gamification_state.dart';
// import 'package:ngoda/ui/widgets/gamification_celebration_overlay.dart';

// class GamificationBootstrap extends ConsumerStatefulWidget {
//   final bool isAuthenticated;
//   final Widget child;

//   const GamificationBootstrap({
//     super.key,
//     required this.isAuthenticated,
//     required this.child,
//   });

//   @override
//   ConsumerState<GamificationBootstrap> createState() {
//     return _GamificationBootstrapState();
//   }
// }

// class _GamificationBootstrapState extends ConsumerState<GamificationBootstrap>
//     with WidgetsBindingObserver {
//   OverlayEntry? _activeEntry;

//   String? _activeNotificationId;

//   @override
//   void initState() {
//     super.initState();

//     WidgetsBinding.instance.addObserver(this);

//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       if (!mounted) {
//         return;
//       }

//       _synchronizeAuthentication();
//     });
//   }

//   @override
//   void didUpdateWidget(covariant GamificationBootstrap oldWidget) {
//     super.didUpdateWidget(oldWidget);

//     if (oldWidget.isAuthenticated != widget.isAuthenticated) {
//       _synchronizeAuthentication();
//     }
//   }

//   void _synchronizeAuthentication() {
//     final notifier = ref.read(gamificationNotifierProvider.notifier);

//     if (widget.isAuthenticated) {
//       unawaited(notifier.start());

//       return;
//     }

//     _removeActiveOverlay();

//     notifier.stop();
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     if (state != AppLifecycleState.resumed || !widget.isAuthenticated) {
//       return;
//     }

//     unawaited(ref.read(gamificationNotifierProvider.notifier).refresh());
//   }

//   void _showNotification(GamificationNotification notification) {
//     if (!mounted ||
//         !widget.isAuthenticated ||
//         _activeEntry != null ||
//         _activeNotificationId == notification.id) {
//       return;
//     }

//     final overlay = Overlay.maybeOf(context, rootOverlay: true);

//     if (overlay == null) {
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         if (!mounted) {
//           return;
//         }

//         _showNotification(notification);
//       });

//       return;
//     }

//     late final OverlayEntry entry;

//     entry = OverlayEntry(
//       builder: (context) {
//         return GamificationCelebrationOverlay(
//           notification: notification,
//           onPresented: () {
//             if (!mounted) {
//               return;
//             }

//             unawaited(
//               ref
//                   .read(gamificationNotifierProvider.notifier)
//                   .acknowledgeCurrent(),
//             );
//           },
//           onComplete: () {
//             if (entry.mounted) {
//               entry.remove();
//             }

//             if (identical(_activeEntry, entry)) {
//               _activeEntry = null;
//               _activeNotificationId = null;
//             }

//             if (!mounted) {
//               return;
//             }

//             unawaited(
//               ref.read(gamificationNotifierProvider.notifier).completeCurrent(),
//             );
//           },
//         );
//       },
//     );

//     _activeEntry = entry;

//     _activeNotificationId = notification.id;

//     overlay.insert(entry);
//   }

//   void _removeActiveOverlay() {
//     final entry = _activeEntry;

//     if (entry != null && entry.mounted) {
//       entry.remove();
//     }

//     _activeEntry = null;
//     _activeNotificationId = null;
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);

//     _removeActiveOverlay();

//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     ref.listen<GamificationState>(gamificationNotifierProvider, (
//       previous,
//       next,
//     ) {
//       final notification = next.currentNotification;

//       if (notification == null ||
//           notification.id == previous?.currentNotification?.id) {
//         return;
//       }

//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         if (!mounted) {
//           return;
//         }

//         _showNotification(notification);
//       });
//     });

//     return widget.child;
//   }
// }
