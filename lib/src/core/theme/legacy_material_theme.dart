// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'app_radii.dart';

import 'app_theme.dart';
import 'primitives.dart';

/// Material compatibility theme for screens and platform controls that still
/// read `Theme.of(context)`. It uses the same Sybil colours and build-time
/// typography tokens as the semantic AppTheme API.

const _lightColorScheme = ColorScheme(
  brightness: Brightness.light,
  surface: SybilPrimitives.paperLight,
  onSurface: SybilPrimitives.inkLight,
  surfaceContainerLowest: SybilPrimitives.paperLight,
  surfaceContainerLow: SybilPrimitives.surfaceLight,
  surfaceContainer: SybilPrimitives.surfaceLight,
  surfaceContainerHigh: SybilPrimitives.softLight,
  surfaceContainerHighest: SybilPrimitives.lineLight,
  onSurfaceVariant: SybilPrimitives.mutedLight,
  primary: SybilPrimitives.accentLight,
  onPrimary: SybilPrimitives.onAccentLight,
  primaryContainer: SybilPrimitives.limeLight,
  onPrimaryContainer: SybilPrimitives.inkLight,
  secondary: SybilPrimitives.accentLight,
  onSecondary: SybilPrimitives.onAccentLight,
  secondaryContainer: SybilPrimitives.sageLight,
  onSecondaryContainer: SybilPrimitives.inkLight,
  tertiary: SybilPrimitives.accentLight,
  onTertiary: SybilPrimitives.onAccentLight,
  tertiaryContainer: SybilPrimitives.sageLight,
  onTertiaryContainer: SybilPrimitives.inkLight,
  error: SybilPrimitives.errorLight,
  onError: SybilPrimitives.surfaceLight,
  errorContainer: SybilPrimitives.errorSurfaceLight,
  onErrorContainer: SybilPrimitives.errorLight,
  outline: SybilPrimitives.mutedLight,
  outlineVariant: SybilPrimitives.lineLight,
  inverseSurface: SybilPrimitives.accentLight,
  onInverseSurface: SybilPrimitives.onAccentLight,
  inversePrimary: SybilPrimitives.onAccentLight,
  shadow: SybilPrimitives.shadow,
  scrim: SybilPrimitives.scrim,
);

// ---------------------------------------------------------------------------
// Dark Sybil palette
// ---------------------------------------------------------------------------

const _darkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  surface: SybilPrimitives.paperDark,
  onSurface: SybilPrimitives.inkDark,
  surfaceContainerLowest: SybilPrimitives.paperDark,
  surfaceContainerLow: SybilPrimitives.surfaceDark,
  surfaceContainer: SybilPrimitives.surfaceDark,
  surfaceContainerHigh: SybilPrimitives.softDark,
  surfaceContainerHighest: SybilPrimitives.lineDark,
  onSurfaceVariant: SybilPrimitives.mutedDark,
  primary: SybilPrimitives.accentDark,
  onPrimary: SybilPrimitives.onAccentDark,
  primaryContainer: SybilPrimitives.limeDark,
  onPrimaryContainer: SybilPrimitives.inkDark,
  secondary: SybilPrimitives.accentDark,
  onSecondary: SybilPrimitives.onAccentDark,
  secondaryContainer: SybilPrimitives.sageDark,
  onSecondaryContainer: SybilPrimitives.inkDark,
  tertiary: SybilPrimitives.accentDark,
  onTertiary: SybilPrimitives.onAccentDark,
  tertiaryContainer: SybilPrimitives.sageDark,
  onTertiaryContainer: SybilPrimitives.inkDark,
  error: SybilPrimitives.errorDark,
  onError: SybilPrimitives.errorSurfaceDark,
  errorContainer: SybilPrimitives.errorSurfaceDark,
  onErrorContainer: SybilPrimitives.errorDark,
  outline: SybilPrimitives.mutedDark,
  outlineVariant: SybilPrimitives.lineDark,
  inverseSurface: SybilPrimitives.accentDark,
  onInverseSurface: SybilPrimitives.onAccentDark,
  inversePrimary: SybilPrimitives.onAccentDark,
  shadow: SybilPrimitives.shadow,
  scrim: SybilPrimitives.scrim,
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
    dialogTheme: defaultTargetPlatform == TargetPlatform.iOS
        ? const DialogThemeData(
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadii.xLarge)),
            ),
          )
        : null,
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
