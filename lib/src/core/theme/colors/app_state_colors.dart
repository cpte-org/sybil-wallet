// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Interaction-state colors from the Figma `Semantic/State` group.
///
/// [hover], [pressed], and [selected] are standalone neutral backgrounds.
/// [hoverOpacity] is the matching alpha overlay token for hover states that
/// need to preserve the underlying surface.
/// [selectedOpacity] is the matching alpha overlay token for selected states
/// that need to preserve the underlying surface.
///
/// [focusRing] + [focusGap] form the 2dp focus indicator: a ring with max
/// contrast against the page, separated from the element by a 2dp gap so it
/// reads cleanly on any surface.
///
/// [focusRingBrand] is the retained brand-crimson focus variant for one-off
/// accent cases. The current button component uses the neutral ring for its
/// primary variant.
class AppStateColors {
  const AppStateColors({
    required this.hover,
    required this.hoverOpacity,
    required this.pressed,
    required this.focus,
    required this.selected,
    required this.selectedOpacity,
    required this.focusRing,
    required this.focusGap,
    required this.focusRingBrand,
    required this.focusRingDestructive,
  });

  final Color hover;
  final Color hoverOpacity;
  final Color pressed;
  final Color focus;
  final Color selected;
  final Color selectedOpacity;
  final Color focusRing;
  final Color focusGap;
  final Color focusRingBrand;
  final Color focusRingDestructive;

  static const dark = AppStateColors(
    hover: SybilPrimitives.softDark,
    hoverOpacity: Color(0x1ADDEAAA),
    pressed: SybilPrimitives.sageDark,
    focus: SybilPrimitives.lineDark,
    selected: SybilPrimitives.limeDark,
    selectedOpacity: Color(0x33DDEAAA),
    focusRing: SybilPrimitives.accentDark,
    focusGap: SybilPrimitives.paperDark,
    focusRingBrand: SybilPrimitives.accentDark,
    focusRingDestructive: SybilPrimitives.errorDark,
  );

  static const light = AppStateColors(
    hover: SybilPrimitives.softLight,
    hoverOpacity: Color(0x0D294A35),
    pressed: SybilPrimitives.sageLight,
    focus: SybilPrimitives.lineLight,
    selected: SybilPrimitives.limeLight,
    selectedOpacity: Color(0x26294A35),
    focusRing: SybilPrimitives.accentLight,
    focusGap: SybilPrimitives.paperLight,
    focusRingBrand: SybilPrimitives.accentLight,
    focusRingDestructive: SybilPrimitives.errorLight,
  );
}
