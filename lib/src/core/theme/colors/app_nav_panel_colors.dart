// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Navigation-panel colors from the Figma `Semantic/Nav Panel` tokens.
class AppNavPanelColors {
  const AppNavPanelColors({
    required this.badgeBg,
    required this.activeBg,
    required this.activeIcon,
    required this.activeLabel,
  });

  final Color badgeBg;
  final Color activeBg;
  final Color activeIcon;
  final Color activeLabel;

  static const dark = AppNavPanelColors(
    badgeBg: SybilPrimitives.accentDark,
    activeBg: SybilPrimitives.navActive,
    activeIcon: SybilPrimitives.navLight,
    activeLabel: SybilPrimitives.navLight,
  );

  static const light = AppNavPanelColors(
    badgeBg: SybilPrimitives.accentLight,
    activeBg: SybilPrimitives.limeLight,
    activeIcon: SybilPrimitives.accentLight,
    activeLabel: SybilPrimitives.inkLight,
  );
}
