import 'package:ngoda/data_models/gamification/notifications/gamification_notification.dart';

const Object _gamificationUnset = Object();

class GamificationState {
  final bool isStarted;
  final bool isLoading;
  final List<GamificationNotification> pendingNotifications;
  final GamificationNotification? currentNotification;
  final String? error;

  const GamificationState({
    this.isStarted = false,
    this.isLoading = false,
    this.pendingNotifications = const [],
    this.currentNotification,
    this.error,
  });

  GamificationState copyWith({
    bool? isStarted,
    bool? isLoading,
    List<GamificationNotification>? pendingNotifications,
    Object? currentNotification = _gamificationUnset,
    Object? error = _gamificationUnset,
  }) {
    return GamificationState(
      isStarted: isStarted ?? this.isStarted,
      isLoading: isLoading ?? this.isLoading,
      pendingNotifications: pendingNotifications ?? this.pendingNotifications,
      currentNotification: identical(currentNotification, _gamificationUnset)
          ? this.currentNotification
          : currentNotification as GamificationNotification?,
      error: identical(error, _gamificationUnset)
          ? this.error
          : error as String?,
    );
  }
}
