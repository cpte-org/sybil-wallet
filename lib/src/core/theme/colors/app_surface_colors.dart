// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
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
    card: SybilPrimitives.surfaceDark,
    input: AppInputSurfaceColors.dark,
    nav: SybilPrimitives.navDark,
    navActive: SybilPrimitives.limeDark,
    tooltip: SybilPrimitives.softDark,
    qrCode: Color(0xFFFFFFFF),
    scrollbarThumb: SybilPrimitives.lineDark,
  );

  static const light = AppSurfaceColors(
    card: SybilPrimitives.surfaceLight,
    input: AppInputSurfaceColors.light,
    nav: SybilPrimitives.paperLight,
    navActive: SybilPrimitives.limeLight,
    tooltip: SybilPrimitives.accentLight,
    qrCode: Color(0xFFFFFFFF),
    scrollbarThumb: SybilPrimitives.lineLight,
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
    primary: SybilPrimitives.surfaceDark,
    secondary: SybilPrimitives.softDark,
    focus: SybilPrimitives.paperDark,
  );

  static const light = AppInputSurfaceColors(
    primary: SybilPrimitives.surfaceLight,
    secondary: SybilPrimitives.softLight,
    focus: SybilPrimitives.paperLight,
  );
}
