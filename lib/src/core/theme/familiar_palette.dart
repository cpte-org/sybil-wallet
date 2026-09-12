import 'package:flutter/widgets.dart';

import 'app_theme.dart';
import 'primitives.dart';

/// Familiar's expressive surfaces, alongside the wallet's semantic tokens.
///
/// [forest] is the action colour: forest on paper, and soft lime at night.
/// Use [onForest] for content placed on that colour.
class FamiliarPalette {
  const FamiliarPalette._(this._dark);

  final bool _dark;

  static const light = FamiliarPalette._(false);
  static const dark = FamiliarPalette._(true);

  static FamiliarPalette of(BuildContext context) {
    final ground = AppTheme.of(context).colors.background.ground;
    return ground.computeLuminance() < 0.5 ? dark : light;
  }

  Color get paper =>
      _dark ? FamiliarPrimitives.paperDark : FamiliarPrimitives.paperLight;
  Color get surface =>
      _dark ? FamiliarPrimitives.surfaceDark : FamiliarPrimitives.surfaceLight;
  Color get soft =>
      _dark ? FamiliarPrimitives.softDark : FamiliarPrimitives.softLight;
  Color get ink =>
      _dark ? FamiliarPrimitives.inkDark : FamiliarPrimitives.inkLight;
  Color get muted =>
      _dark ? FamiliarPrimitives.mutedDark : FamiliarPrimitives.mutedLight;
  Color get forest =>
      _dark ? FamiliarPrimitives.accentDark : FamiliarPrimitives.accentLight;
  Color get onForest => _dark
      ? FamiliarPrimitives.onAccentDark
      : FamiliarPrimitives.onAccentLight;
  Color get lime =>
      _dark ? FamiliarPrimitives.limeDark : FamiliarPrimitives.limeLight;
  Color get peach =>
      _dark ? FamiliarPrimitives.peachDark : FamiliarPrimitives.peachLight;
  Color get lilac =>
      _dark ? FamiliarPrimitives.lilacDark : FamiliarPrimitives.lilacLight;
  Color get sage =>
      _dark ? FamiliarPrimitives.sageDark : FamiliarPrimitives.sageLight;
  Color get sky =>
      _dark ? FamiliarPrimitives.skyDark : FamiliarPrimitives.skyLight;
  Color get line =>
      _dark ? FamiliarPrimitives.lineDark : FamiliarPrimitives.lineLight;
}
