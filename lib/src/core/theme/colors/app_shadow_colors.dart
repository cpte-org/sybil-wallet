// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Shadow colors from the Figma `Semantic/Shadows` tokens.
class AppShadowColors {
  const AppShadowColors({
    required this.shadow1,
    required this.shadow2,
    required this.shadow3,
    required this.subtle,
    required this.regular,
  });

  final Color shadow1;
  final Color shadow2;
  final Color shadow3;
  final Color subtle;
  final Color regular;

  static const dark = AppShadowColors(
    shadow1: Color(0x00000000),
    shadow2: Color(0x00000000),
    shadow3: Color(0x33122119),
    subtle: Color(0x00000000),
    regular: Color(0x00000000),
  );

  static const light = AppShadowColors(
    shadow1: SybilPrimitives.shadow,
    shadow2: SybilPrimitives.shadow,
    shadow3: Color(0x33122119),
    subtle: Color(0x0D1F3622),
    regular: SybilPrimitives.shadow,
  );
}
