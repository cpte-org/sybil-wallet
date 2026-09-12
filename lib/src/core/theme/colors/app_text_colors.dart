import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Text color hierarchy.
///
/// * [accent] — Titles, headings; max contrast.
/// * [primary] — Default body text, paragraphs.
/// * [secondary] — Subtitles, timestamps, metadata.
/// * [muted] — Descriptions. Theme-aware.
/// * [disabled] — Inactive, unavailable labels.
/// * [inverse] — Text placed on inverted surfaces (e.g. dark text on a light
///   chip inside dark mode).
/// * [warning] — Inline caution copy. Uses the amber warning role.
/// * [positiveStrong] — Positive-state copy backed by the green utility ramp.
/// * [destructive] — Destructive utility copy.
/// * [destructiveLight] — Softer destructive copy for secondary error text.
/// * [success] — Positive / success utility copy.
/// * [brandCrimson] — Brand-colored inline text accent.
/// * [homeCard] — Exception text used on the home balance card. Theme-aware.
class AppTextColors {
  const AppTextColors({
    required this.accent,
    required this.primary,
    required this.secondary,
    required this.muted,
    required this.disabled,
    required this.inverse,
    required this.warning,
    required this.positiveStrong,
    required this.destructive,
    required this.destructiveLight,
    required this.success,
    required this.brandCrimson,
    required this.homeCard,
  });

  final Color accent;
  final Color primary;
  final Color secondary;
  final Color muted;
  final Color disabled;
  final Color inverse;
  final Color warning;
  final Color positiveStrong;
  final Color destructive;
  final Color destructiveLight;
  final Color success;
  final Color brandCrimson;
  final Color homeCard;

  static const dark = AppTextColors(
    accent: FamiliarPrimitives.inkDark,
    primary: FamiliarPrimitives.textDark,
    secondary: FamiliarPrimitives.mutedDark,
    muted: FamiliarPrimitives.mutedDark,
    disabled: Color(0xFF7F9382),
    inverse: FamiliarPrimitives.onAccentDark,
    warning: FamiliarPrimitives.warningDark,
    positiveStrong: FamiliarPrimitives.accentDark,
    destructive: FamiliarPrimitives.errorDark,
    destructiveLight: FamiliarPrimitives.errorDark,
    success: FamiliarPrimitives.accentDark,
    brandCrimson: FamiliarPrimitives.accentDark,
    homeCard: FamiliarPrimitives.navInk,
  );

  static const light = AppTextColors(
    accent: FamiliarPrimitives.inkLight,
    primary: FamiliarPrimitives.textLight,
    secondary: FamiliarPrimitives.mutedLight,
    muted: FamiliarPrimitives.mutedLight,
    disabled: Color(0xFF899286),
    inverse: FamiliarPrimitives.onAccentLight,
    warning: FamiliarPrimitives.warningLight,
    positiveStrong: FamiliarPrimitives.accentLight,
    destructive: FamiliarPrimitives.errorLight,
    destructiveLight: FamiliarPrimitives.errorLight,
    success: FamiliarPrimitives.accentLight,
    brandCrimson: FamiliarPrimitives.accentLight,
    homeCard: FamiliarPrimitives.navInk,
  );
}
