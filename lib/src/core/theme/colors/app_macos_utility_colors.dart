// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
import 'package:flutter/painting.dart';

import '../primitives.dart';

/// macOS utility colors from the Desktop color-token export.
class AppMacosUtilityColors {
  const AppMacosUtilityColors({
    required this.window,
    required this.windowTransparent,
    required this.navPanel,
    required this.font,
    required this.thinBorder,
    required this.innerBorder,
  });

  final Color window;
  final Color windowTransparent;
  final Color navPanel;
  final Color font;
  final Color thinBorder;
  final Color innerBorder;

  static const dark = AppMacosUtilityColors(
    window: SybilPrimitives.paperDark,
    windowTransparent: Color(0x0019261F),
    navPanel: Color(0x4D13251C),
    font: SybilPrimitives.inkDark,
    thinBorder: SybilPrimitives.lineDark,
    // The glass panel's inner ring is a white highlight in both Figma
    // modes (inner shadow #FFFFFF @ 15%), not a dark outline.
    innerBorder: Color(0x26FFFFFF),
  );

  static const light = AppMacosUtilityColors(
    window: SybilPrimitives.paperLight,
    windowTransparent: Color(0x00F7F6EF),
    navPanel: Color(0x4DFFFEF9),
    font: SybilPrimitives.inkLight,
    thinBorder: SybilPrimitives.lineLight,
    innerBorder: Color(0x26FFFFFF),
  );
}
