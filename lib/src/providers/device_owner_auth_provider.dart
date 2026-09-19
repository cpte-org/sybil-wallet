// Apache-2.0 section 4(b): modified from upstream by the Sigil fork.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/device_owner_auth.dart';

const kWalletResetDeviceAuthReason = 'Confirm reset Sigil';
const kWalletResetDeviceAuthRequiredMessage =
    'Device authentication is required to reset Sigil.';
const kWalletResetDeviceAuthFailedMessage =
    "Couldn't verify device ownership. Please try again.";
const kWalletResetFailedMessage = "Couldn't reset Sigil. Please try again.";

final deviceOwnerAuthProvider = Provider<DeviceOwnerAuth>(
  (ref) => DeviceOwnerAuth(),
);

Future<bool> verifyDeviceOwnerForWalletReset(WidgetRef ref) {
  return ref
      .read(deviceOwnerAuthProvider)
      .verify(reason: kWalletResetDeviceAuthReason);
}
