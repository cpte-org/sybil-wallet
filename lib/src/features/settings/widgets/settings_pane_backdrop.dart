import 'package:flutter/widgets.dart';

import '../../../core/widgets/familiar_widgets.dart';

/// Kept as an API for the existing security and recovery routes.
enum SettingsBackdropArt {
  castle('assets/illustrations/settings_backdrop_castle.png'),
  vault('assets/illustrations/settings_backdrop_vault.png');

  const SettingsBackdropArt(this.assetPath);
  final String assetPath;
}

/// Quiet paper backdrop shared by security and recovery screens.
class SettingsPaneBackdrop extends StatelessWidget {
  const SettingsPaneBackdrop({required this.art, super.key});

  final SettingsBackdropArt art;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ColoredBox(color: FamiliarPalette.of(context).paper),
    );
  }
}
