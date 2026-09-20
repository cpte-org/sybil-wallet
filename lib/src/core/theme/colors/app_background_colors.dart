// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
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
    window: SybilPrimitives.paperDark,
    ground: SybilPrimitives.paperDark,
    base: SybilPrimitives.surfaceDark,
    raised: SybilPrimitives.surfaceDark,
    overlay: SybilPrimitives.softDark,
    inverse: SybilPrimitives.accentDark,
    neutralScrim: SybilPrimitives.scrim,
    neutralSubtleOpacity: Color(0x33415345),
    neutralStrongOpacity: Color(0x80415345),
    brandCrimsonSubtle: SybilPrimitives.sageDark,
    brandCrimsonStrong: SybilPrimitives.accentDark,
    brandCrimsonAlpha: Color(0x33DDEAAA),
    utilityDestructiveSubtle: SybilPrimitives.errorSurfaceDark,
    utilityDestructiveStrong: Color(0xFFAC352C),
    utilityDestructiveAlphaSubtle: Color(0x14F8AAA0),
    utilityDestructiveAlpha: Color(0x40F8AAA0),
    utilitySuccessSubtle: SybilPrimitives.sageDark,
    utilitySuccessStrong: SybilPrimitives.accentDark,
    utilitySuccessAlpha: Color(0x26DDEAAA),
    homeCard: SybilPrimitives.navLight,
  );

  static const light = AppBackgroundColors(
    window: SybilPrimitives.paperLight,
    ground: SybilPrimitives.paperLight,
    base: SybilPrimitives.surfaceLight,
    raised: SybilPrimitives.surfaceLight,
    overlay: SybilPrimitives.softLight,
    inverse: SybilPrimitives.accentLight,
    neutralScrim: SybilPrimitives.scrim,
    neutralSubtleOpacity: Color(0x33D9DFD3),
    neutralStrongOpacity: Color(0x59D9DFD3),
    brandCrimsonSubtle: SybilPrimitives.sageLight,
    brandCrimsonStrong: SybilPrimitives.accentLight,
    brandCrimsonAlpha: Color(0x26294A35),
    utilityDestructiveSubtle: SybilPrimitives.errorSurfaceLight,
    utilityDestructiveStrong: Color(0xFFAC352C),
    utilityDestructiveAlphaSubtle: Color(0x14AC352C),
    utilityDestructiveAlpha: Color(0x26AC352C),
    utilitySuccessSubtle: SybilPrimitives.sageLight,
    utilitySuccessStrong: SybilPrimitives.accentLight,
    utilitySuccessAlpha: Color(0x26294A35),
    homeCard: SybilPrimitives.navLight,
  );
}
