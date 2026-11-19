import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class AppLayout {
  static const dialogMinWidth = 600.0;
  static const navigationRailMinWidth = 840.0;
  static const extendedRailMinWidth = 1280.0;
  static const workspaceListMinWidth = 760.0;
  static const workspaceMinWidth = 1000.0;
  static const workspaceMaxWidth = 1600.0;
  static const workspacePadding = 24.0;
  static const paneGap = 20.0;
  static const detailPaneWidth = 360.0;
  static const contentMaxWidth = 1040.0;
  static const pagePadding = 20.0;
  static const sectionGap = 24.0;
  static const panelRadius = 24.0;
}

abstract final class AppTheme {
  // Shared callers still pass brightness; LXY always renders the Mocha palette.
  static const _buttonMinimumSize = Size(48, 48);
  static const _buttonPadding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 12,
  );

  static Color courseAccent(Brightness _, String groupKey) {
    var hash = 0;
    for (final code in groupKey.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    const colors = _Catppuccin.mochaCourses;
    // Keep hashing into the original eight accents so event-category colors
    // stay unchanged after the course palette grew to twelve; courses use
    // courseColorAssignments instead.
    return colors[hash % 8];
  }

  /// Assigns one Catppuccin accent per course name, spreading the palette in
  /// iteration order instead of hashing so identical names always share a
  /// color and distinct names reuse colors only after the palette is
  /// exhausted. Callers must pass [names] in a deterministic order so every
  /// schedule surface agrees on the assignment.
  static Map<String, Color> courseColorAssignments(
    Brightness _,
    Iterable<String> names,
  ) {
    const colors = _Catppuccin.mochaCourses;
    final assignments = <String, Color>{};
    var index = 0;
    for (final name in names) {
      assignments.putIfAbsent(name, () => colors[index++ % colors.length]);
    }
    return assignments;
  }

  static SystemUiOverlayStyle systemOverlayStyle(Brightness _) {
    return const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );
  }

  static ThemeData build(Brightness _) {
    const palette = _Catppuccin.mocha;
    final accentContainer = Color.alphaBlend(
      palette.mauve.withValues(alpha: 0.10),
      palette.base,
    );
    final errorContainer = Color.alphaBlend(
      palette.red.withValues(alpha: 0.08),
      palette.base,
    );
    final colors = ColorScheme(
      brightness: Brightness.dark,
      primary: palette.mauve,
      onPrimary: palette.base,
      primaryContainer: accentContainer,
      onPrimaryContainer: palette.text,
      primaryFixed: accentContainer,
      primaryFixedDim: palette.crust,
      onPrimaryFixed: palette.text,
      onPrimaryFixedVariant: palette.subtext1,
      secondary: palette.mauve,
      onSecondary: palette.base,
      secondaryContainer: accentContainer,
      onSecondaryContainer: palette.text,
      secondaryFixed: accentContainer,
      secondaryFixedDim: palette.crust,
      onSecondaryFixed: palette.text,
      onSecondaryFixedVariant: palette.subtext1,
      tertiary: palette.subtext1,
      onTertiary: palette.base,
      tertiaryContainer: palette.crust,
      onTertiaryContainer: palette.text,
      tertiaryFixed: palette.mantle,
      tertiaryFixedDim: palette.crust,
      onTertiaryFixed: palette.text,
      onTertiaryFixedVariant: palette.subtext1,
      error: palette.red,
      onError: palette.base,
      errorContainer: errorContainer,
      onErrorContainer: palette.text,
      surface: palette.base,
      onSurface: palette.text,
      surfaceDim: palette.crust,
      surfaceBright: palette.surface0,
      surfaceContainerLowest: palette.base,
      surfaceContainerLow: palette.base,
      surfaceContainer: palette.mantle,
      surfaceContainerHigh: palette.crust,
      surfaceContainerHighest: palette.surface0,
      onSurfaceVariant: palette.subtext1,
      outline: palette.overlay2,
      outlineVariant: palette.surface0,
      shadow: palette.crust,
      scrim: palette.crust,
      inverseSurface: palette.text,
      onInverseSurface: palette.base,
      inversePrimary: palette.base,
      surfaceTint: Colors.transparent,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      applyElevationOverlayColor: false,
      scaffoldBackgroundColor: colors.surface,
      dividerColor: colors.outlineVariant,
      shadowColor: colors.shadow,
      focusColor: colors.primary.withValues(alpha: 0.12),
      hoverColor: colors.onSurface.withValues(alpha: 0.04),
      highlightColor: colors.primary.withValues(alpha: 0.12),
      splashColor: colors.primary.withValues(alpha: 0.12),
      disabledColor: colors.onSurface.withValues(alpha: 0.38),
      hintColor: colors.onSurfaceVariant,
      unselectedWidgetColor: colors.onSurfaceVariant,
      iconTheme: IconThemeData(color: colors.onSurfaceVariant),
      primaryIconTheme: IconThemeData(color: colors.onPrimary),
      appBarTheme: AppBarThemeData(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: systemOverlayStyle(Brightness.dark),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppLayout.panelRadius),
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceContainer,
        elevation: 0,
        indicatorColor: colors.primary,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.onPrimary
                : colors.onSurfaceVariant,
          ),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.surfaceContainer,
        indicatorColor: colors.primary,
        selectedIconTheme: IconThemeData(color: colors.onPrimary),
        unselectedIconTheme: IconThemeData(color: colors.onSurfaceVariant),
        useIndicator: true,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: colors.surface,
        border: const OutlineInputBorder(),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.primary,
        selectionColor: colors.primary.withValues(alpha: 0.18),
        selectionHandleColor: colors.primary,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        barrierColor: colors.scrim.withValues(alpha: 0.44),
      ),
      popupMenuTheme: PopupMenuThemeData(color: colors.surface),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: colors.onInverseSurface, fontSize: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: _buttonMinimumSize,
          padding: _buttonPadding,
          iconSize: 20,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: _buttonMinimumSize,
          padding: _buttonPadding,
          iconSize: 20,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: _buttonMinimumSize,
          padding: _buttonPadding,
          iconSize: 20,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: _buttonMinimumSize,
          padding: _buttonPadding,
          iconSize: 20,
        ),
      ),
    );
  }
}

// Official swatches: https://github.com/catppuccin/palette
// Keep the original accent colors instead of generating tones from a seed.
abstract final class _Catppuccin {
  static const mochaCourses = [
    Color(0xFFCBA6F7),
    Color(0xFF89B4FA),
    Color(0xFF94E2D5),
    Color(0xFFFAB387),
    Color(0xFFF5C2E7),
    Color(0xFFA6E3A1),
    Color(0xFFF38BA8),
    Color(0xFFB4BEFE),
    Color(0xFFF9E2AF),
    Color(0xFF89DCEB),
    Color(0xFF74C7EC),
    Color(0xFFEBA0AC),
  ];

  static const mocha = (
    base: Color(0xFF1E1E2E),
    mantle: Color(0xFF181825),
    crust: Color(0xFF11111B),
    surface0: Color(0xFF313244),
    overlay2: Color(0xFF9399B2),
    subtext1: Color(0xFFBAC2DE),
    text: Color(0xFFCDD6F4),
    mauve: Color(0xFFCBA6F7),
    red: Color(0xFFF38BA8),
  );
}
