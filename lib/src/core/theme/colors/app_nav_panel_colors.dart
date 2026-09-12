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
    badgeBg: FamiliarPrimitives.accentDark,
    activeBg: FamiliarPrimitives.navActive,
    activeIcon: FamiliarPrimitives.navLight,
    activeLabel: FamiliarPrimitives.navLight,
  );

  static const light = AppNavPanelColors(
    badgeBg: FamiliarPrimitives.accentLight,
    activeBg: FamiliarPrimitives.limeLight,
    activeIcon: FamiliarPrimitives.accentLight,
    activeLabel: FamiliarPrimitives.inkLight,
  );
}
