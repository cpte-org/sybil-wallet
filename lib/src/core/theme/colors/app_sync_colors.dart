// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
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
    text: SybilPrimitives.textDark,
    textSyncing: SybilPrimitives.mutedDark,
    textError: SybilPrimitives.errorDark,
    glow: SybilPrimitives.sageDark,
    lightSuccess: SybilPrimitives.accentDark,
    lightError: SybilPrimitives.errorDark,
  );

  static const light = AppSyncColors(
    text: SybilPrimitives.textLight,
    textSyncing: SybilPrimitives.mutedLight,
    textError: SybilPrimitives.errorLight,
    glow: SybilPrimitives.sageLight,
    lightSuccess: SybilPrimitives.accentLight,
    lightError: SybilPrimitives.errorLight,
  );
}
