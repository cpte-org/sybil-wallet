import 'package:flutter/material.dart';

import '../config/app_version_config.dart';
import '../widgets/app_button.dart';
import 'sybil_legal_notices.dart';

class SybilLicensesButton extends StatelessWidget {
  const SybilLicensesButton({super.key});

  @override
  Widget build(BuildContext context) => AppButton(
    variant: AppButtonVariant.ghost,
    onPressed: () {
      registerSybilLegalNotices();
      showLicensePage(
        context: context,
        applicationName: 'Sybil',
        applicationVersion: kVizorAboutVersionLabel,
      );
    },
    child: const Text('Open-source licenses'),
  );
}
