import 'package:flutter/widgets.dart';

import 'app_theme.dart';
import 'primitives.dart';

/// Sybil's expressive surfaces, alongside the wallet's semantic tokens.
///
/// [forest] is the action colour: forest on paper, and soft lime at night.
/// Use [onForest] for content placed on that colour.
class SybilPalette {
  const SybilPalette._(this._dark);

  final bool _dark;

  static const light = SybilPalette._(false);
  static const dark = SybilPalette._(true);

  static SybilPalette of(BuildContext context) {
    final ground = AppTheme.of(context).colors.background.ground;
    return ground.computeLuminance() < 0.5 ? dark : light;
  }

  Color get paper =>
      _dark ? SybilPrimitives.paperDark : SybilPrimitives.paperLight;
  Color get surface =>
      _dark ? SybilPrimitives.surfaceDark : SybilPrimitives.surfaceLight;
  Color get soft =>
      _dark ? SybilPrimitives.softDark : SybilPrimitives.softLight;
  Color get ink =>
      _dark ? SybilPrimitives.inkDark : SybilPrimitives.inkLight;
  Color get muted =>
      _dark ? SybilPrimitives.mutedDark : SybilPrimitives.mutedLight;
  Color get forest =>
      _dark ? SybilPrimitives.accentDark : SybilPrimitives.accentLight;
  Color get onForest => _dark
      ? SybilPrimitives.onAccentDark
      : SybilPrimitives.onAccentLight;
  Color get lime =>
      _dark ? SybilPrimitives.limeDark : SybilPrimitives.limeLight;
  Color get peach =>
      _dark ? SybilPrimitives.peachDark : SybilPrimitives.peachLight;
  Color get lilac =>
      _dark ? SybilPrimitives.lilacDark : SybilPrimitives.lilacLight;
  Color get sage =>
      _dark ? SybilPrimitives.sageDark : SybilPrimitives.sageLight;
  Color get sky =>
      _dark ? SybilPrimitives.skyDark : SybilPrimitives.skyLight;
  Color get line =>
      _dark ? SybilPrimitives.lineDark : SybilPrimitives.lineLight;
}
