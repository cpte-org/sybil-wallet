// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
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
    accent: SybilPrimitives.inkDark,
    primary: SybilPrimitives.textDark,
    secondary: SybilPrimitives.mutedDark,
    muted: SybilPrimitives.mutedDark,
    disabled: Color(0xFF7F9382),
    inverse: SybilPrimitives.onAccentDark,
    warning: SybilPrimitives.warningDark,
    positiveStrong: SybilPrimitives.accentDark,
    destructive: SybilPrimitives.errorDark,
    destructiveLight: SybilPrimitives.errorDark,
    success: SybilPrimitives.accentDark,
    brandCrimson: SybilPrimitives.accentDark,
    homeCard: SybilPrimitives.navInk,
  );

  static const light = AppTextColors(
    accent: SybilPrimitives.inkLight,
    primary: SybilPrimitives.textLight,
    secondary: SybilPrimitives.mutedLight,
    muted: SybilPrimitives.mutedLight,
    disabled: Color(0xFF899286),
    inverse: SybilPrimitives.onAccentLight,
    warning: SybilPrimitives.warningLight,
    positiveStrong: SybilPrimitives.accentLight,
    destructive: SybilPrimitives.errorLight,
    destructiveLight: SybilPrimitives.errorLight,
    success: SybilPrimitives.accentLight,
    brandCrimson: SybilPrimitives.accentLight,
    homeCard: SybilPrimitives.navInk,
  );
}
