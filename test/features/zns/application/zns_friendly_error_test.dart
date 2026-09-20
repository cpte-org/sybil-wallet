import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/integrations/near_intents/near_intents_one_click_swap_adapter.dart';
import 'package:zcash_wallet/src/features/zns/application/zns_controller.dart';

void main() {
  test(
    'bridge configuration errors retain their reason without class prefix',
    () {
      const message =
          'Sybil swaps and bridge funding are not configured for this build.';
      const error = OneClickApiException(message, operation: 'configuration');
      expect(znsFriendlyError(error), message);
      expect(znsFriendlyError(error.toString()), message);
      expect(znsFriendlyError(null), '');
      expect(
        znsFriendlyError('A saved operation needs review.'),
        'A saved operation needs review.',
      );
    },
  );
}
