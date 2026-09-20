// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Border / divider weights.
///
/// * [subtle] — Hairline dividers, row separators.
/// * [subtleOpacity] — Alpha border used on strong filled controls.
/// * [inverseOpacity] — Alpha border used over inverted / strong fills.
/// * [regular] — Default field/card/chip border. (Named `regular` instead of
///   Figma's `default` because `default` is a reserved word in Dart.)
/// * [medium] — Active/filled field border.
/// * [strong] — Max-contrast border.
/// * [utilityDestructive] — Validation / destructive emphasis.
/// * [utilityDestructiveSubtle] — Soft destructive border.
/// * [utilitySuccess] — Success emphasis.
/// * [utilityPositiveStrong] — Positive-state emphasis on the green ramp.
/// * [brandCrimsonStrong] — Brand feedback / accent border.
class AppBorderColors {
  const AppBorderColors({
    required this.subtle,
    required this.subtleOpacity,
    required this.inverseOpacity,
    required this.regular,
    required this.medium,
    required this.strong,
    required this.utilityDestructive,
    required this.utilityDestructiveSubtle,
    required this.utilitySuccess,
    required this.utilityPositiveStrong,
    required this.brandCrimsonStrong,
  });

  final Color subtle;
  final Color subtleOpacity;
  final Color inverseOpacity;
  final Color regular;
  final Color medium;
  final Color strong;
  final Color utilityDestructive;
  final Color utilityDestructiveSubtle;
  final Color utilitySuccess;
  final Color utilityPositiveStrong;
  final Color brandCrimsonStrong;

  static const dark = AppBorderColors(
    subtle: SybilPrimitives.lineDark,
    subtleOpacity: Color(0x33EDF1DE),
    inverseOpacity: Color(0x262C3D31),
    regular: SybilPrimitives.lineDark,
    medium: SybilPrimitives.mutedDark,
    strong: SybilPrimitives.accentDark,
    utilityDestructive: SybilPrimitives.errorDark,
    utilityDestructiveSubtle: SybilPrimitives.errorSurfaceDark,
    utilitySuccess: SybilPrimitives.accentDark,
    utilityPositiveStrong: SybilPrimitives.accentDark,
    brandCrimsonStrong: SybilPrimitives.accentDark,
  );

  static const light = AppBorderColors(
    subtle: SybilPrimitives.lineLight,
    subtleOpacity: Color(0x26243B30),
    inverseOpacity: Color(0x1AFFFFF9),
    regular: SybilPrimitives.lineLight,
    medium: SybilPrimitives.mutedLight,
    strong: SybilPrimitives.accentLight,
    utilityDestructive: SybilPrimitives.errorLight,
    utilityDestructiveSubtle: SybilPrimitives.errorSurfaceLight,
    utilitySuccess: SybilPrimitives.accentLight,
    utilityPositiveStrong: SybilPrimitives.accentLight,
    brandCrimsonStrong: SybilPrimitives.accentLight,
  );
}
