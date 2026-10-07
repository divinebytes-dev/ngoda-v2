import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/hive_service_provider.dart';
import 'package:ngoda/services/hive_service.dart';

class ThemeNotifier extends Notifier<ThemeMode> {
  static const String _isDarkKey = 'isDark';

  @override
  ThemeMode build() {
    final hiveService = ref.read(hiveServiceProvider);

    final isDark =
        hiveService
            .getItem<bool>(HiveBoxName.themeSettings, _isDarkKey)
            .result ??
        true;

    return isDark ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> toggle() async {
    final newMode = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;

    await setThemeMode(newMode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == ThemeMode.system) {
      return;
    }

    final hiveService = ref.read(hiveServiceProvider);

    state = mode;

    await hiveService.saveItem<bool>(
      HiveBoxName.themeSettings,
      _isDarkKey,
      mode == ThemeMode.dark,
    );
  }

  Future<void> setDarkMode(bool isDark) async {
    await setThemeMode(isDark ? ThemeMode.dark : ThemeMode.light);
  }
}

final themeModeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(
  ThemeNotifier.new,
);
