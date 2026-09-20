// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Icon color hierarchy retained from the OLDSemantic icon tokens.
///
/// * [accent] — Active, selected, primary icons.
/// * [regular] — Standard UI icons. (Named `regular` instead of `default`
///   because `default` is a reserved word in Dart.)
/// * [muted] — Inactive, decorative icons. Theme-aware.
/// * [disabled] — Icons on disabled controls.
/// * [inverse] — Icons on inverted surfaces.
/// * [onPrimary] — Icons placed inside a primary button.
/// * [warning] — Caution icons. Uses the amber warning role.
/// * [destructive] — Destructive-state icons.
/// * [destructiveLight] — Softer destructive icon for secondary error affordances.
/// * [success] — Positive / success utility icons.
/// * [brandCrimson] — Brand-colored icons.
class AppIconColors {
  const AppIconColors({
    required this.accent,
    required this.regular,
    required this.muted,
    required this.disabled,
    required this.inverse,
    required this.onPrimary,
    required this.warning,
    required this.destructive,
    required this.destructiveLight,
    required this.success,
    required this.brandCrimson,
  });

  final Color accent;
  final Color regular;
  final Color muted;
  final Color disabled;
  final Color inverse;
  final Color onPrimary;
  final Color warning;
  final Color destructive;
  final Color destructiveLight;
  final Color success;
  final Color brandCrimson;

  static const dark = AppIconColors(
    accent: SybilPrimitives.accentDark,
    regular: SybilPrimitives.textDark,
    muted: SybilPrimitives.mutedDark,
    disabled: Color(0xFF7F9382),
    inverse: SybilPrimitives.onAccentDark,
    onPrimary: SybilPrimitives.onAccentDark,
    warning: SybilPrimitives.warningDark,
    destructive: SybilPrimitives.errorDark,
    destructiveLight: SybilPrimitives.errorDark,
    success: SybilPrimitives.accentDark,
    brandCrimson: SybilPrimitives.accentDark,
  );

  static const light = AppIconColors(
    accent: SybilPrimitives.accentLight,
    regular: SybilPrimitives.textLight,
    muted: SybilPrimitives.mutedLight,
    disabled: Color(0xFF899286),
    inverse: SybilPrimitives.onAccentLight,
    onPrimary: SybilPrimitives.onAccentLight,
    warning: SybilPrimitives.warningLight,
    destructive: SybilPrimitives.errorLight,
    destructiveLight: SybilPrimitives.errorLight,
    success: SybilPrimitives.accentLight,
    brandCrimson: SybilPrimitives.accentLight,
  );
}
