// Apache-2.0 section 4(b): modified from upstream by the Sigil fork.
import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Component-level surface colors.
///
/// * [card] — Card components, list rows.
/// * [input] — Text input surface colors.
/// * [nav] — Navigation rail background.
/// * [navActive] — Active nav item indicator.
/// * [tooltip] — Tooltip / popover background.
/// * [qrCode] — QR code backing surface. Theme-invariant for scan contrast.
/// * [scrollbarThumb] — Opaque desktop pane overlay scrollbar thumb.
class AppSurfaceColors {
  const AppSurfaceColors({
    required this.card,
    required this.input,
    required this.nav,
    required this.navActive,
    required this.tooltip,
    required this.qrCode,
    required this.scrollbarThumb,
  });

  final Color card;
  final AppInputSurfaceColors input;
  final Color nav;
  final Color navActive;
  final Color tooltip;
  final Color qrCode;
  final Color scrollbarThumb;

  static const dark = AppSurfaceColors(
    card: FamiliarPrimitives.surfaceDark,
    input: AppInputSurfaceColors.dark,
    nav: FamiliarPrimitives.navDark,
    navActive: FamiliarPrimitives.limeDark,
    tooltip: FamiliarPrimitives.softDark,
    qrCode: Color(0xFFFFFFFF),
    scrollbarThumb: FamiliarPrimitives.lineDark,
  );

  static const light = AppSurfaceColors(
    card: FamiliarPrimitives.surfaceLight,
    input: AppInputSurfaceColors.light,
    nav: FamiliarPrimitives.paperLight,
    navActive: FamiliarPrimitives.limeLight,
    tooltip: FamiliarPrimitives.accentLight,
    qrCode: Color(0xFFFFFFFF),
    scrollbarThumb: FamiliarPrimitives.lineLight,
  );
}

/// Text input surface colors grouped by field variant/state.
class AppInputSurfaceColors {
  const AppInputSurfaceColors({
    required this.primary,
    required this.secondary,
    required this.focus,
  });

  final Color primary;
  final Color secondary;
  final Color focus;

  static const dark = AppInputSurfaceColors(
    primary: FamiliarPrimitives.surfaceDark,
    secondary: FamiliarPrimitives.softDark,
    focus: FamiliarPrimitives.paperDark,
  );

  static const light = AppInputSurfaceColors(
    primary: FamiliarPrimitives.surfaceLight,
    secondary: FamiliarPrimitives.softLight,
    focus: FamiliarPrimitives.paperLight,
  );
}
