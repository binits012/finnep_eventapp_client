import 'package:flutter/material.dart';

/// Brand indigo — shared across light/dark.
const Color _brand = Color(0xFF6366F1);

// --- Light ---
const Color _lightCanvas = Color(0xFFF4F4F5);
const Color _lightSurface = Color(0xFFFFFFFF);
const Color _lightSurfaceHigh = Color(0xFFECECEF);

// --- Light text (zinc scale) ---
const Color _lightOnSurface = Color(0xFF18181B);
const Color _lightOnSurfaceVariant = Color(0xFF52525B);
const Color _lightPrimaryContainer = Color(0xFFE0E7FF);
const Color _lightOnPrimaryContainer = Color(0xFF312E81);

// --- Dark (layered blacks / slate) ---
const Color _darkCanvas = Color(0xFF0C0C0F);
const Color _darkSurface = Color(0xFF151821);
const Color _darkSurfaceHigh = Color(0xFF1F2937);

/// Plain `TextStyle(...)` constructors default `inherit` to true, while
/// Typography / theme text styles use `inherit: false`. Lerping themes
/// (e.g. when toggling light/dark under [AnimatedTheme]) then hits
/// "different inherit values". Prefer `.copyWith` on [TextTheme] styles and
/// set `inherit: false` explicitly when building standalone overrides.
TextTheme _refinedTextTypography(
  TextTheme base,
  Brightness brightness,
  ColorScheme cs,
) {
  final bodyColor = cs.onSurfaceVariant;
  final headingColor = cs.onSurface;

  return base.copyWith(
    displaySmall: base.displaySmall?.copyWith(
      inherit: false,
      textBaseline: TextBaseline.alphabetic,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      height: 1.15,
      color: headingColor,
    ),
    headlineSmall: base.headlineSmall?.copyWith(
      inherit: false,
      textBaseline: TextBaseline.alphabetic,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.35,
      height: 1.22,
      color: headingColor,
    ),
    titleLarge: base.titleLarge?.copyWith(
      inherit: false,
      textBaseline: TextBaseline.alphabetic,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.28,
      height: 1.25,
      color: headingColor,
    ),
    titleMedium: base.titleMedium?.copyWith(
      inherit: false,
      textBaseline: TextBaseline.alphabetic,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.08,
      height: 1.28,
      color: headingColor,
    ),
    titleSmall: base.titleSmall?.copyWith(
      inherit: false,
      textBaseline: TextBaseline.alphabetic,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.04,
      color: cs.onSurfaceVariant,
      height: 1.33,
    ),
    bodyLarge: base.bodyLarge?.copyWith(
      inherit: false,
      textBaseline: TextBaseline.alphabetic,
      height: 1.5,
      letterSpacing: 0.1,
      color: bodyColor,
    ),
    bodyMedium: base.bodyMedium?.copyWith(
      inherit: false,
      textBaseline: TextBaseline.alphabetic,
      height: 1.45,
      letterSpacing: 0.06,
      color: bodyColor,
    ),
    bodySmall: base.bodySmall?.copyWith(
      inherit: false,
      textBaseline: TextBaseline.alphabetic,
      height: 1.38,
      color: cs.onSurfaceVariant,
    ),
    labelLarge: base.labelLarge?.copyWith(
      inherit: false,
      textBaseline: TextBaseline.alphabetic,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.15,
      height: 1.2,
      color: headingColor,
    ),
    labelMedium: base.labelMedium?.copyWith(
      inherit: false,
      textBaseline: TextBaseline.alphabetic,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.12,
      color: headingColor,
    ),
    labelSmall: base.labelSmall?.copyWith(
      inherit: false,
      textBaseline: TextBaseline.alphabetic,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      color: cs.onSurfaceVariant,
    ),
  );
}

ThemeData _baseFromScheme(ColorScheme cs, Brightness brightness) {
  return ThemeData(colorScheme: cs, brightness: brightness, useMaterial3: true);
}

ColorScheme _lightColorScheme() {
  final seeded = ColorScheme.fromSeed(
    seedColor: _brand,
    brightness: Brightness.light,
  );
  return seeded.copyWith(
    primary: _brand,
    onPrimary: Colors.white,
    primaryContainer: _lightPrimaryContainer,
    onPrimaryContainer: _lightOnPrimaryContainer,
    secondary: _lightOnSurfaceVariant,
    onSecondary: Colors.white,
    secondaryContainer: _lightCanvas,
    onSecondaryContainer: _lightOnSurface,
    tertiary: const Color(0xFF71717A),
    tertiaryContainer: _lightCanvas,
    onTertiaryContainer: _lightOnSurface,
    onSurface: _lightOnSurface,
    onSurfaceVariant: _lightOnSurfaceVariant,
    surfaceTint: Colors.transparent,
    surface: _lightSurface,
    surfaceContainerLowest: _lightCanvas,
    surfaceContainerHighest: _lightSurfaceHigh,
    outline: const Color(0xFFD4D4D8),
    outlineVariant: const Color(0xFFE4E4E7),
    inverseSurface: const Color(0xFF27272A),
    onInverseSurface: const Color(0xFFF4F4F5),
    scrim: Colors.black.withValues(alpha: 0.45),
  );
}

ColorScheme _darkColorScheme() {
  final seeded = ColorScheme.fromSeed(
    seedColor: _brand,
    brightness: Brightness.dark,
  );
  return seeded.copyWith(
    surfaceTint: Colors.transparent,
    surface: _darkSurface,
    surfaceContainerLowest: _darkCanvas,
    surfaceContainerHighest: _darkSurfaceHigh,
    outline: const Color(0xFF3F3F46),
    outlineVariant: const Color(0xFF3F3F46),
    scrim: Colors.black.withValues(alpha: 0.65),
  );
}

ThemeData _sharedMotionAndInteraction(ColorScheme cs) {
  const zoom = ZoomPageTransitionsBuilder();
  final cupertino = CupertinoPageTransitionsBuilder();
  return ThemeData(colorScheme: cs).copyWith(
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        TargetPlatform.android: zoom,
        TargetPlatform.fuchsia: zoom,
        TargetPlatform.linux: zoom,
        TargetPlatform.windows: zoom,
        TargetPlatform.iOS: cupertino,
        TargetPlatform.macOS: cupertino,
      },
    ),
    scrollbarTheme: ScrollbarThemeData(
      radius: const Radius.circular(8),
      thickness: WidgetStateProperty.all(5),
      thumbColor: WidgetStateProperty.all(cs.primary.withValues(alpha: 0.38)),
      trackColor: WidgetStateProperty.all(
        cs.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      trackBorderColor: WidgetStateProperty.all(Colors.transparent),
      crossAxisMargin: 4,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: _brand,
      linearTrackColor: cs.surfaceContainerHighest,
      circularTrackColor: cs.surfaceContainerHighest,
    ),
    splashFactory: InkSparkle.splashFactory,
    splashColor: _brand.withValues(alpha: 0.12),
    highlightColor: _brand.withValues(alpha: 0.06),
  );
}

ThemeData get appThemeLight {
  final cs = _lightColorScheme();
  final baseline = _baseFromScheme(cs, Brightness.light);
  final motion = _sharedMotionAndInteraction(cs);
  final borderRadius = BorderRadius.circular(12);
  final inputRadius = BorderRadius.circular(10);

  return baseline.copyWith(
    scaffoldBackgroundColor: cs.surfaceContainerLowest,
    canvasColor: cs.surfaceContainerLowest,
    visualDensity: VisualDensity.standard,
    textTheme: _refinedTextTypography(baseline.textTheme, Brightness.light, cs),
    primaryTextTheme: _refinedTextTypography(
      baseline.primaryTextTheme,
      Brightness.light,
      cs,
    ),
    dividerTheme: DividerThemeData(
      color: cs.outlineVariant,
      thickness: 1,
      space: 1,
    ),

    splashFactory: motion.splashFactory,
    splashColor: motion.splashColor,
    highlightColor: motion.highlightColor,
    pageTransitionsTheme: motion.pageTransitionsTheme,
    scrollbarTheme: motion.scrollbarTheme,
    progressIndicatorTheme: motion.progressIndicatorTheme,

    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      backgroundColor: cs.surfaceContainerLowest,
      foregroundColor: cs.onSurface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      iconTheme: IconThemeData(color: cs.onSurface, size: 22),
      actionsIconTheme: IconThemeData(color: cs.onSurface, size: 22),
      titleTextStyle: baseline.textTheme.titleLarge?.copyWith(
        inherit: false,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
      toolbarTextStyle: baseline.textTheme.bodyMedium?.copyWith(
        inherit: false,
        color: cs.onSurface,
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: cs.surface,
      disabledColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      selectedColor: cs.primaryContainer,
      secondarySelectedColor: cs.primaryContainer,
      labelStyle: baseline.textTheme.labelLarge!.copyWith(
        inherit: false,
        color: cs.onSurface,
        fontWeight: FontWeight.w500,
      ),
      secondaryLabelStyle: baseline.textTheme.labelLarge!.copyWith(
        inherit: false,
        color: cs.onPrimaryContainer,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      side: BorderSide(color: cs.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      showCheckmark: false,
    ),

    tooltipTheme: TooltipThemeData(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: baseline.textTheme.bodySmall!.copyWith(
        inherit: false,
        color: cs.onInverseSurface,
        fontSize: 12,
        height: 1.25,
      ),
    ),

    badgeTheme: BadgeThemeData(
      backgroundColor: _brand,
      textColor: Colors.white,
    ),

    cardTheme: CardThemeData(
      color: cs.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
    ),

    dialogTheme: DialogThemeData(
      elevation: 3,
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      dragHandleColor: cs.onSurfaceVariant.withValues(alpha: 0.38),
      showDragHandle: true,
      modalBarrierColor: cs.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 4,
      backgroundColor: cs.inverseSurface,
      contentTextStyle: baseline.textTheme.bodyMedium!.copyWith(
        inherit: false,
        color: cs.onInverseSurface,
        fontWeight: FontWeight.w500,
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: cs.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: cs.onSurfaceVariant,
      textColor: cs.onSurface,
      titleTextStyle: baseline.textTheme.titleMedium?.copyWith(
        inherit: false,
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: baseline.textTheme.bodySmall?.copyWith(
        inherit: false,
        color: cs.onSurfaceVariant,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      minVerticalPadding: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),

    iconTheme: IconThemeData(color: cs.onSurfaceVariant, size: 22),

    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      backgroundColor: cs.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      indicatorColor: cs.secondaryContainer.withValues(alpha: 0.6),
      labelTextStyle: WidgetStateProperty.all(
        baseline.textTheme.labelLarge!.copyWith(
          inherit: false,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    ),

    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStateProperty.all(cs.surface),
        elevation: WidgetStateProperty.all(3),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surface,
      hoverColor: Colors.transparent,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      floatingLabelAlignment: FloatingLabelAlignment.start,
      floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
        final baseStyle = baseline.textTheme.bodySmall!.copyWith(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          fontWeight: FontWeight.w600,
        );
        if (states.contains(WidgetState.error)) {
          return baseStyle.copyWith(color: cs.error);
        }
        if (states.contains(WidgetState.focused)) {
          return baseStyle.copyWith(color: _brand);
        }
        return baseStyle.copyWith(color: cs.onSurfaceVariant);
      }),
      helperStyle: baseline.textTheme.bodySmall!.copyWith(
        inherit: false,
        textBaseline: TextBaseline.alphabetic,
        color: cs.onSurfaceVariant,
        fontSize: 12,
      ),
      hintStyle: baseline.textTheme.bodyMedium!.copyWith(
        inherit: false,
        textBaseline: TextBaseline.alphabetic,
        color: cs.onSurfaceVariant.withValues(alpha: 0.55),
      ),
      errorStyle: baseline.textTheme.bodySmall!.copyWith(
        inherit: false,
        textBaseline: TextBaseline.alphabetic,
        color: cs.error,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      labelStyle: baseline.textTheme.labelLarge!.copyWith(
        inherit: false,
        textBaseline: TextBaseline.alphabetic,
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: inputRadius,
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: inputRadius,
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: inputRadius,
        borderSide: const BorderSide(color: _brand, width: 2),
      ),
      errorBorder: OutlineInputBorder(borderRadius: inputRadius),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: inputRadius,
        borderSide: BorderSide(color: cs.error, width: 2),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        shadowColor: Colors.transparent,
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        disabledBackgroundColor: cs.onSurface.withValues(alpha: 0.12),
        disabledForegroundColor: cs.onSurface.withValues(alpha: 0.38),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: baseline.textTheme.labelLarge!.copyWith(
          inherit: false,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        minimumSize: const Size(52, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: baseline.textTheme.labelLarge!.copyWith(
          inherit: false,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: cs.onSurface,
        side: BorderSide(color: cs.outline),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        minimumSize: const Size(52, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: baseline.textTheme.labelLarge!.copyWith(
          inherit: false,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _brand,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: baseline.textTheme.labelLarge!.copyWith(
          inherit: false,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    radioTheme: RadioThemeData(
      fillColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return _brand;
        return cs.outline;
      }),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return cs.onPrimary;
        return cs.surface;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return _brand;
        return cs.outlineVariant;
      }),
    ),

    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return _brand;
        if (states.contains(WidgetState.disabled)) {
          return cs.surfaceContainerHighest;
        }
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return cs.onSurfaceVariant;
        return Colors.white;
      }),
      side: BorderSide(color: cs.outline),
    ),

    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        side: WidgetStateProperty.all(BorderSide(color: cs.outline)),
      ),
    ),
  );
}

ThemeData get appThemeDark {
  final cs = _darkColorScheme();
  final baseline = _baseFromScheme(cs, Brightness.dark);
  final motion = _sharedMotionAndInteraction(cs);
  final borderRadius = BorderRadius.circular(12);
  final inputRadius = BorderRadius.circular(10);

  return baseline.copyWith(
    scaffoldBackgroundColor: cs.surfaceContainerLowest,
    canvasColor: cs.surfaceContainerLowest,
    visualDensity: VisualDensity.standard,
    textTheme: _refinedTextTypography(baseline.textTheme, Brightness.dark, cs),
    primaryTextTheme: _refinedTextTypography(
      baseline.primaryTextTheme,
      Brightness.dark,
      cs,
    ),
    dividerTheme: DividerThemeData(
      color: cs.outlineVariant.withValues(alpha: 0.85),
      thickness: 1,
      space: 1,
    ),

    splashFactory: motion.splashFactory,
    splashColor: motion.splashColor,
    highlightColor: motion.highlightColor,
    pageTransitionsTheme: motion.pageTransitionsTheme,
    scrollbarTheme: motion.scrollbarTheme,
    progressIndicatorTheme: motion.progressIndicatorTheme,

    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      backgroundColor: cs.surfaceContainerLowest,
      foregroundColor: cs.onSurface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      iconTheme: IconThemeData(color: cs.onSurface, size: 22),
      actionsIconTheme: IconThemeData(color: cs.onSurface, size: 22),
      titleTextStyle: baseline.textTheme.titleLarge?.copyWith(
        inherit: false,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
      toolbarTextStyle: baseline.textTheme.bodyMedium?.copyWith(
        inherit: false,
        color: cs.onSurface,
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: cs.surfaceContainerHighest,
      disabledColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      selectedColor: cs.primaryContainer.withValues(alpha: 0.5),
      secondarySelectedColor: cs.secondaryContainer,
      labelStyle: baseline.textTheme.labelLarge!.copyWith(
        inherit: false,
        color: cs.onSurface.withValues(alpha: 0.9),
        fontWeight: FontWeight.w500,
      ),
      secondaryLabelStyle: baseline.textTheme.labelLarge!.copyWith(
        inherit: false,
        color: cs.onSecondaryContainer,
        fontWeight: FontWeight.w500,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.95)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),

    tooltipTheme: TooltipThemeData(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF374151),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: baseline.textTheme.bodySmall!.copyWith(
        inherit: false,
        color: cs.onInverseSurface.withValues(alpha: 0.95),
        fontSize: 12,
      ),
    ),

    badgeTheme: BadgeThemeData(
      backgroundColor: _brand,
      textColor: Colors.white,
    ),

    cardTheme: CardThemeData(
      color: cs.surface,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.45),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
    ),

    dialogTheme: DialogThemeData(
      elevation: 3,
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      showDragHandle: true,
      modalBarrierColor: cs.scrim,
      dragHandleColor: cs.onSurfaceVariant.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 4,
      backgroundColor: cs.inverseSurface,
      contentTextStyle: baseline.textTheme.bodyMedium!.copyWith(
        inherit: false,
        color: cs.onInverseSurface,
        fontWeight: FontWeight.w500,
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: cs.surface,
      elevation: 3,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: cs.onSurfaceVariant,
      textColor: cs.onSurface,
      titleTextStyle: baseline.textTheme.titleMedium?.copyWith(
        inherit: false,
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: baseline.textTheme.bodySmall?.copyWith(
        inherit: false,
        color: cs.onSurfaceVariant,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      minVerticalPadding: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),

    iconTheme: IconThemeData(color: cs.onSurfaceVariant, size: 22),

    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      backgroundColor: cs.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      indicatorColor: cs.secondaryContainer.withValues(alpha: 0.6),
      labelTextStyle: WidgetStateProperty.all(
        baseline.textTheme.labelLarge!.copyWith(
          inherit: false,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    ),

    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStateProperty.all(cs.surface),
        elevation: WidgetStateProperty.all(3),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surface,
      hoverColor: Colors.transparent,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      floatingLabelAlignment: FloatingLabelAlignment.start,
      floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
        final baseStyle = baseline.textTheme.bodySmall!.copyWith(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          fontWeight: FontWeight.w600,
        );
        if (states.contains(WidgetState.error)) {
          return baseStyle.copyWith(color: cs.error);
        }
        if (states.contains(WidgetState.focused)) {
          return baseStyle.copyWith(color: _brand);
        }
        return baseStyle.copyWith(color: cs.onSurfaceVariant);
      }),
      helperStyle: baseline.textTheme.bodySmall!.copyWith(
        inherit: false,
        textBaseline: TextBaseline.alphabetic,
        color: cs.onSurfaceVariant,
        fontSize: 12,
      ),
      hintStyle: baseline.textTheme.bodyMedium!.copyWith(
        inherit: false,
        textBaseline: TextBaseline.alphabetic,
        color: cs.onSurfaceVariant.withValues(alpha: 0.52),
      ),
      errorStyle: baseline.textTheme.bodySmall!.copyWith(
        inherit: false,
        textBaseline: TextBaseline.alphabetic,
        color: cs.error,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      labelStyle: baseline.textTheme.labelLarge!.copyWith(
        inherit: false,
        textBaseline: TextBaseline.alphabetic,
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: inputRadius,
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: inputRadius,
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: inputRadius,
        borderSide: const BorderSide(color: _brand, width: 2),
      ),
      errorBorder: OutlineInputBorder(borderRadius: inputRadius),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: inputRadius,
        borderSide: BorderSide(color: cs.error, width: 2),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.35),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: baseline.textTheme.labelLarge!.copyWith(
          inherit: false,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        minimumSize: const Size(52, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: baseline.textTheme.labelLarge!.copyWith(
          inherit: false,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: cs.onSurface,
        side: BorderSide(color: cs.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        minimumSize: const Size(52, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: baseline.textTheme.labelLarge!.copyWith(
          inherit: false,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: cs.primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: baseline.textTheme.labelLarge!.copyWith(
          inherit: false,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return _brand;
        return Colors.transparent;
      }),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return _brand;
        return cs.outline;
      }),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return cs.onPrimary;
        return cs.surface;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return _brand;
        return cs.outlineVariant;
      }),
    ),

    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        side: WidgetStateProperty.all(BorderSide(color: cs.outlineVariant)),
      ),
    ),
  );
}
