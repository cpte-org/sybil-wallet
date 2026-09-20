// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Button colors grouped by variant.
///
/// Each variant owns its own sub-palette so widgets reference them as
/// `button.primary.bg`, `button.ghost.bgHover`, etc.
class AppButtonColors {
  const AppButtonColors({
    required this.primary,
    required this.secondary,
    required this.ghost,
    required this.disabled,
    required this.destructive,
  });

  final AppPrimaryButtonColors primary;
  final AppSecondaryButtonColors secondary;
  final AppGhostButtonColors ghost;
  final AppDisabledButtonColors disabled;
  final AppDestructiveButtonColors destructive;

  static const dark = AppButtonColors(
    primary: AppPrimaryButtonColors.dark,
    secondary: AppSecondaryButtonColors.dark,
    ghost: AppGhostButtonColors.dark,
    disabled: AppDisabledButtonColors.dark,
    destructive: AppDestructiveButtonColors.dark,
  );

  static const light = AppButtonColors(
    primary: AppPrimaryButtonColors.light,
    secondary: AppSecondaryButtonColors.light,
    ghost: AppGhostButtonColors.light,
    disabled: AppDisabledButtonColors.light,
    destructive: AppDestructiveButtonColors.light,
  );
}

class AppPrimaryButtonColors {
  const AppPrimaryButtonColors({
    required this.bg,
    required this.bgHover,
    required this.bgPressed,
    required this.border,
    required this.borderHover,
    required this.borderPressed,
    required this.label,
    required this.labelHover,
  });

  final Color bg;
  final Color bgHover;
  final Color bgPressed;
  final Color border;
  final Color borderHover;
  final Color borderPressed;
  final Color label;
  final Color labelHover;

  static const dark = AppPrimaryButtonColors(
    bg: SybilPrimitives.accentDark,
    bgHover: Color(0xFFE8F1C1),
    bgPressed: Color(0xFFCEDC94),
    border: SybilPrimitives.accentDark,
    borderHover: SybilPrimitives.accentDark,
    borderPressed: SybilPrimitives.accentDark,
    label: SybilPrimitives.onAccentDark,
    labelHover: SybilPrimitives.onAccentDark,
  );

  static const light = AppPrimaryButtonColors(
    bg: SybilPrimitives.accentLight,
    bgHover: Color(0xFF365D43),
    bgPressed: Color(0xFF233A2E),
    border: SybilPrimitives.accentLight,
    borderHover: SybilPrimitives.accentLight,
    borderPressed: SybilPrimitives.accentLight,
    label: SybilPrimitives.onAccentLight,
    labelHover: SybilPrimitives.onAccentLight,
  );
}

class AppSecondaryButtonColors {
  const AppSecondaryButtonColors({
    required this.bg,
    required this.bgHover,
    required this.bgPressed,
    required this.label,
  });

  final Color bg;
  final Color bgHover;
  final Color bgPressed;
  final Color label;

  static const dark = AppSecondaryButtonColors(
    bg: SybilPrimitives.surfaceDark,
    bgHover: SybilPrimitives.softDark,
    bgPressed: SybilPrimitives.sageDark,
    label: SybilPrimitives.inkDark,
  );

  static const light = AppSecondaryButtonColors(
    bg: SybilPrimitives.surfaceLight,
    bgHover: SybilPrimitives.softLight,
    bgPressed: SybilPrimitives.sageLight,
    label: SybilPrimitives.inkLight,
  );
}

class AppGhostButtonColors {
  const AppGhostButtonColors({
    required this.bg,
    required this.bgHover,
    required this.border,
    required this.label,
  });

  // Transparent-looking base; the concrete token equals ground so the fill
  // reads as "no fill" against Scaffold.
  final Color bg;
  final Color bgHover;
  final Color border;
  final Color label;

  static const dark = AppGhostButtonColors(
    bg: SybilPrimitives.paperDark,
    bgHover: SybilPrimitives.softDark,
    border: SybilPrimitives.lineDark,
    label: SybilPrimitives.inkDark,
  );

  static const light = AppGhostButtonColors(
    bg: SybilPrimitives.paperLight,
    bgHover: SybilPrimitives.softLight,
    border: SybilPrimitives.lineLight,
    label: SybilPrimitives.inkLight,
  );
}

class AppDisabledButtonColors {
  const AppDisabledButtonColors({required this.bg, required this.label});

  final Color bg;
  final Color label;

  static const dark = AppDisabledButtonColors(
    bg: SybilPrimitives.softDark,
    label: Color(0xFF7F9382),
  );

  static const light = AppDisabledButtonColors(
    bg: SybilPrimitives.softLight,
    label: Color(0xFF899286),
  );
}

class AppDestructiveButtonColors {
  const AppDestructiveButtonColors({
    required this.bg,
    required this.bgHover,
    required this.bgPressed,
    required this.border,
    required this.borderHover,
    required this.borderPressed,
    required this.label,
  });

  final Color bg;
  final Color bgHover;
  final Color bgPressed;
  final Color border;
  final Color borderHover;
  final Color borderPressed;
  final Color label;

  static const dark = AppDestructiveButtonColors(
    bg: SybilPrimitives.errorDark,
    bgHover: Color(0xFFFCC1B9),
    bgPressed: Color(0xFFE99186),
    border: SybilPrimitives.errorDark,
    borderHover: SybilPrimitives.errorDark,
    borderPressed: SybilPrimitives.errorDark,
    label: SybilPrimitives.errorSurfaceDark,
  );

  static const light = AppDestructiveButtonColors(
    bg: SybilPrimitives.errorLight,
    bgHover: Color(0xFF922D25),
    bgPressed: Color(0xFF7B251F),
    border: SybilPrimitives.errorLight,
    borderHover: SybilPrimitives.errorLight,
    borderPressed: SybilPrimitives.errorLight,
    label: SybilPrimitives.surfaceLight,
  );
}
