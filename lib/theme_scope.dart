import 'package:flutter/material.dart';

class ThemeScope extends InheritedWidget {
  const ThemeScope({
    super.key,
    required this.themeMode,
    required this.toggleTheme,
    required super.child,
  });

  final ThemeMode themeMode;
  final VoidCallback toggleTheme;

  static ThemeScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'No ThemeScope found');
    return scope!;
  }

  @override
  bool updateShouldNotify(ThemeScope oldWidget) {
    return themeMode != oldWidget.themeMode;
  }
}
