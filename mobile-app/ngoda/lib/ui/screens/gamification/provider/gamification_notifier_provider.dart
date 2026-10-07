import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/gamification/notifier/gamification_notifier.dart';
import 'package:ngoda/ui/screens/gamification/state/gamification_state.dart';

final gamificationNotifierProvider =
    NotifierProvider<GamificationNotifier, GamificationState>(
      GamificationNotifier.new,
    );
