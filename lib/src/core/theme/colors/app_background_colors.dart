// Apache-2.0 section 4(b): modified from upstream by the Sigil fork.
import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Depth hierarchy for the app shell.
///
/// Layered from deepest to highest:
/// * [window] — Desktop window backing and matching onboarding pane background.
/// * [ground] — Scaffold background, deepest layer.
/// * [base] — Primary content surface, main panels.
/// * [raised] — Cards, modals, sidebars, drawers.
/// * [overlay] — Dropdowns, popovers, floating elements.
/// * [neutralScrim] / [neutralSubtleOpacity] / [neutralStrongOpacity] —
///   Alpha neutral overlays.
/// * [brandCrimsonSubtle] / [brandCrimsonStrong] — Brand-accent backgrounds.
/// * [brandCrimsonAlpha] — Alpha brand overlay.
/// * [utilityDestructiveSubtle] / [utilityDestructiveStrong] /
///   [utilitySuccessSubtle] / [utilitySuccessStrong] — Utility backgrounds.
/// * [utilityDestructiveAlphaSubtle] / [utilityDestructiveAlpha] /
///   [utilitySuccessAlpha] — Alpha utility overlays.
/// * [homeCard] — Exception surface for the home balance card. Theme-aware.
class AppBackgroundColors {
  const AppBackgroundColors({
    required this.window,
    required this.ground,
    required this.base,
    required this.raised,
    required this.overlay,
    required this.inverse,
    required this.neutralScrim,
    required this.neutralSubtleOpacity,
    required this.neutralStrongOpacity,
    required this.brandCrimsonSubtle,
    required this.brandCrimsonStrong,
    required this.brandCrimsonAlpha,
    required this.utilityDestructiveSubtle,
    required this.utilityDestructiveStrong,
    required this.utilityDestructiveAlphaSubtle,
    required this.utilityDestructiveAlpha,
    required this.utilitySuccessSubtle,
    required this.utilitySuccessStrong,
    required this.utilitySuccessAlpha,
    required this.homeCard,
  });

  final Color window;
  final Color ground;
  final Color base;
  final Color raised;
  final Color overlay;
  final Color inverse;
  final Color neutralScrim;
  final Color neutralSubtleOpacity;
  final Color neutralStrongOpacity;
  final Color brandCrimsonSubtle;
  final Color brandCrimsonStrong;
  final Color brandCrimsonAlpha;
  final Color utilityDestructiveSubtle;
  final Color utilityDestructiveStrong;
  final Color utilityDestructiveAlphaSubtle;
  final Color utilityDestructiveAlpha;
  final Color utilitySuccessSubtle;
  final Color utilitySuccessStrong;
  final Color utilitySuccessAlpha;
  final Color homeCard;

  static const dark = AppBackgroundColors(
    window: FamiliarPrimitives.paperDark,
    ground: FamiliarPrimitives.paperDark,
    base: FamiliarPrimitives.surfaceDark,
    raised: FamiliarPrimitives.surfaceDark,
    overlay: FamiliarPrimitives.softDark,
    inverse: FamiliarPrimitives.accentDark,
    neutralScrim: FamiliarPrimitives.scrim,
    neutralSubtleOpacity: Color(0x33415345),
    neutralStrongOpacity: Color(0x80415345),
    brandCrimsonSubtle: FamiliarPrimitives.sageDark,
    brandCrimsonStrong: FamiliarPrimitives.accentDark,
    brandCrimsonAlpha: Color(0x33DDEAAA),
    utilityDestructiveSubtle: FamiliarPrimitives.errorSurfaceDark,
    utilityDestructiveStrong: Color(0xFFAC352C),
    utilityDestructiveAlphaSubtle: Color(0x14F8AAA0),
    utilityDestructiveAlpha: Color(0x40F8AAA0),
    utilitySuccessSubtle: FamiliarPrimitives.sageDark,
    utilitySuccessStrong: FamiliarPrimitives.accentDark,
    utilitySuccessAlpha: Color(0x26DDEAAA),
    homeCard: FamiliarPrimitives.navLight,
  );

  static const light = AppBackgroundColors(
    window: FamiliarPrimitives.paperLight,
    ground: FamiliarPrimitives.paperLight,
    base: FamiliarPrimitives.surfaceLight,
    raised: FamiliarPrimitives.surfaceLight,
    overlay: FamiliarPrimitives.softLight,
    inverse: FamiliarPrimitives.accentLight,
    neutralScrim: FamiliarPrimitives.scrim,
    neutralSubtleOpacity: Color(0x33D9DFD3),
    neutralStrongOpacity: Color(0x59D9DFD3),
    brandCrimsonSubtle: FamiliarPrimitives.sageLight,
    brandCrimsonStrong: FamiliarPrimitives.accentLight,
    brandCrimsonAlpha: Color(0x26294A35),
    utilityDestructiveSubtle: FamiliarPrimitives.errorSurfaceLight,
    utilityDestructiveStrong: Color(0xFFAC352C),
    utilityDestructiveAlphaSubtle: Color(0x14AC352C),
    utilityDestructiveAlpha: Color(0x26AC352C),
    utilitySuccessSubtle: FamiliarPrimitives.sageLight,
    utilitySuccessStrong: FamiliarPrimitives.accentLight,
    utilitySuccessAlpha: Color(0x26294A35),
    homeCard: FamiliarPrimitives.navLight,
  );
}
