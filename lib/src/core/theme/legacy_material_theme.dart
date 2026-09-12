import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'primitives.dart';

/// Material compatibility theme for screens and platform controls that still
/// read `Theme.of(context)`. It uses the same Familiar colours and build-time
/// typography tokens as the semantic AppTheme API.

const _lightColorScheme = ColorScheme(
  brightness: Brightness.light,
  surface: FamiliarPrimitives.paperLight,
  onSurface: FamiliarPrimitives.inkLight,
  surfaceContainerLowest: FamiliarPrimitives.paperLight,
  surfaceContainerLow: FamiliarPrimitives.surfaceLight,
  surfaceContainer: FamiliarPrimitives.surfaceLight,
  surfaceContainerHigh: FamiliarPrimitives.softLight,
  surfaceContainerHighest: FamiliarPrimitives.lineLight,
  onSurfaceVariant: FamiliarPrimitives.mutedLight,
  primary: FamiliarPrimitives.accentLight,
  onPrimary: FamiliarPrimitives.onAccentLight,
  primaryContainer: FamiliarPrimitives.limeLight,
  onPrimaryContainer: FamiliarPrimitives.inkLight,
  secondary: FamiliarPrimitives.accentLight,
  onSecondary: FamiliarPrimitives.onAccentLight,
  secondaryContainer: FamiliarPrimitives.sageLight,
  onSecondaryContainer: FamiliarPrimitives.inkLight,
  tertiary: FamiliarPrimitives.accentLight,
  onTertiary: FamiliarPrimitives.onAccentLight,
  tertiaryContainer: FamiliarPrimitives.sageLight,
  onTertiaryContainer: FamiliarPrimitives.inkLight,
  error: FamiliarPrimitives.errorLight,
  onError: FamiliarPrimitives.surfaceLight,
  errorContainer: FamiliarPrimitives.errorSurfaceLight,
  onErrorContainer: FamiliarPrimitives.errorLight,
  outline: FamiliarPrimitives.mutedLight,
  outlineVariant: FamiliarPrimitives.lineLight,
  inverseSurface: FamiliarPrimitives.accentLight,
  onInverseSurface: FamiliarPrimitives.onAccentLight,
  inversePrimary: FamiliarPrimitives.onAccentLight,
  shadow: FamiliarPrimitives.shadow,
  scrim: FamiliarPrimitives.scrim,
);

// ---------------------------------------------------------------------------
// Dark Familiar palette
// ---------------------------------------------------------------------------

const _darkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  surface: FamiliarPrimitives.paperDark,
  onSurface: FamiliarPrimitives.inkDark,
  surfaceContainerLowest: FamiliarPrimitives.paperDark,
  surfaceContainerLow: FamiliarPrimitives.surfaceDark,
  surfaceContainer: FamiliarPrimitives.surfaceDark,
  surfaceContainerHigh: FamiliarPrimitives.softDark,
  surfaceContainerHighest: FamiliarPrimitives.lineDark,
  onSurfaceVariant: FamiliarPrimitives.mutedDark,
  primary: FamiliarPrimitives.accentDark,
  onPrimary: FamiliarPrimitives.onAccentDark,
  primaryContainer: FamiliarPrimitives.limeDark,
  onPrimaryContainer: FamiliarPrimitives.inkDark,
  secondary: FamiliarPrimitives.accentDark,
  onSecondary: FamiliarPrimitives.onAccentDark,
  secondaryContainer: FamiliarPrimitives.sageDark,
  onSecondaryContainer: FamiliarPrimitives.inkDark,
  tertiary: FamiliarPrimitives.accentDark,
  onTertiary: FamiliarPrimitives.onAccentDark,
  tertiaryContainer: FamiliarPrimitives.sageDark,
  onTertiaryContainer: FamiliarPrimitives.inkDark,
  error: FamiliarPrimitives.errorDark,
  onError: FamiliarPrimitives.errorSurfaceDark,
  errorContainer: FamiliarPrimitives.errorSurfaceDark,
  onErrorContainer: FamiliarPrimitives.errorDark,
  outline: FamiliarPrimitives.mutedDark,
  outlineVariant: FamiliarPrimitives.lineDark,
  inverseSurface: FamiliarPrimitives.accentDark,
  onInverseSurface: FamiliarPrimitives.onAccentDark,
  inversePrimary: FamiliarPrimitives.onAccentDark,
  shadow: FamiliarPrimitives.shadow,
  scrim: FamiliarPrimitives.scrim,
);

// ---------------------------------------------------------------------------
// Text themes
// ---------------------------------------------------------------------------

const _bodyFamily = 'Geist';

TextTheme _buildTextTheme(Color textColor) {
  return TextTheme(
    displayLarge: AppTypography.displayLarge.copyWith(color: textColor),
    displayMedium: AppTypography.displayMedium.copyWith(color: textColor),
    displaySmall: AppTypography.displaySmall.copyWith(color: textColor),
    headlineLarge: AppTypography.headlineLarge.copyWith(color: textColor),
    headlineMedium: AppTypography.headlineMedium.copyWith(color: textColor),
    headlineSmall: AppTypography.headlineSmall.copyWith(color: textColor),
    titleLarge: AppTypography.headlineSmall.copyWith(color: textColor),
    titleMedium: AppTypography.bodyLarge.copyWith(color: textColor),
    bodyLarge: AppTypography.bodyLarge.copyWith(color: textColor),
    bodyMedium: AppTypography.bodyMedium.copyWith(color: textColor),
    bodySmall: AppTypography.bodySmall.copyWith(color: textColor),
    labelLarge: AppTypography.labelLarge.copyWith(color: textColor),
    labelMedium: AppTypography.labelMedium.copyWith(color: textColor),
    labelSmall: AppTypography.labelSmall.copyWith(color: textColor),
  );
}

// ---------------------------------------------------------------------------
// ThemeData builder — single source of truth for both light and dark
// ---------------------------------------------------------------------------

// Desktop platforms get instant page transitions (no slide/fade/zoom).
// Individual routes can still override via CustomTransitionPage in GoRouter.
class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

bool get _isDesktop =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

ThemeData _buildTheme(ColorScheme colorScheme) {
  return ThemeData(
    useMaterial3: true,
    brightness: colorScheme.brightness,
    colorScheme: colorScheme,
    textTheme: _buildTextTheme(colorScheme.onSurface),
    fontFamily: _bodyFamily,
    scaffoldBackgroundColor: colorScheme.surface,
    pageTransitionsTheme: _isDesktop
        ? const PageTransitionsTheme(
            builders: {
              TargetPlatform.macOS: _NoTransitionsBuilder(),
              TargetPlatform.windows: _NoTransitionsBuilder(),
              TargetPlatform.linux: _NoTransitionsBuilder(),
            },
          )
        : null,
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: AppTypography.headlineSmall.copyWith(
        color: colorScheme.onSurface,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: AppTypography.labelLarge,
        minimumSize: const Size(0, 50),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.onSurface,
        side: BorderSide(color: colorScheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: AppTypography.labelLarge,
        minimumSize: const Size(0, 50),
      ),
    ),
  );
}

ThemeData buildLegacyLightTheme() => _buildTheme(_lightColorScheme);
ThemeData buildLegacyDarkTheme() => _buildTheme(_darkColorScheme);
