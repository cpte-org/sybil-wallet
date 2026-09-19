import 'package:flutter/material.dart';

import '../config/app_version_config.dart';
import '../widgets/app_button.dart';
import 'sigil_legal_notices.dart';

class SigilLicensesButton extends StatelessWidget {
  const SigilLicensesButton({super.key});

  @override
  Widget build(BuildContext context) => AppButton(
    variant: AppButtonVariant.ghost,
    onPressed: () {
      registerSigilLegalNotices();
      showLicensePage(
        context: context,
        applicationName: 'Sigil',
        applicationVersion: kVizorAboutVersionLabel,
      );
    },
    child: const Text('Open-source licenses'),
  );
}
