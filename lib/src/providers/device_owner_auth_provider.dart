// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/device_owner_auth.dart';

const kWalletResetDeviceAuthReason = 'Confirm reset Sybil';
const kWalletResetDeviceAuthRequiredMessage =
    'Device authentication is required to reset Sybil.';
const kWalletResetDeviceAuthFailedMessage =
    "Couldn't verify device ownership. Please try again.";
const kWalletResetFailedMessage = "Couldn't reset Sybil. Please try again.";

final deviceOwnerAuthProvider = Provider<DeviceOwnerAuth>(
  (ref) => DeviceOwnerAuth(),
);

Future<bool> verifyDeviceOwnerForWalletReset(WidgetRef ref) {
  return ref
      .read(deviceOwnerAuthProvider)
      .verify(reason: kWalletResetDeviceAuthReason);
}
