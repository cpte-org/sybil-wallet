// Apache-2.0 section 4(b): modified from upstream by the Sigil fork.
import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Sync-specific sidebar colors retained from the OLDSemantic sync tokens.
class AppSyncColors {
  const AppSyncColors({
    required this.text,
    required this.textSyncing,
    required this.textError,
    required this.glow,
    required this.lightSuccess,
    required this.lightError,
  });

  final Color text;
  final Color textSyncing;
  final Color textError;
  final Color glow;
  final Color lightSuccess;
  final Color lightError;

  static const dark = AppSyncColors(
    text: FamiliarPrimitives.textDark,
    textSyncing: FamiliarPrimitives.mutedDark,
    textError: FamiliarPrimitives.errorDark,
    glow: FamiliarPrimitives.sageDark,
    lightSuccess: FamiliarPrimitives.accentDark,
    lightError: FamiliarPrimitives.errorDark,
  );

  static const light = AppSyncColors(
    text: FamiliarPrimitives.textLight,
    textSyncing: FamiliarPrimitives.mutedLight,
    textError: FamiliarPrimitives.errorLight,
    glow: FamiliarPrimitives.sageLight,
    lightSuccess: FamiliarPrimitives.accentLight,
    lightError: FamiliarPrimitives.errorLight,
  );
}
