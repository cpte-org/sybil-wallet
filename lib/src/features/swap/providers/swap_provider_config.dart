// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/near_intents_endpoint_config.dart';

import '../integrations/near_intents/near_intents_one_click_swap_adapter.dart';
import '../models/swap_models.dart';

final swapIntentProvider = Provider<SwapProvider>((ref) {
  return NearIntentsOneClickSwapAdapter(
    endpointConfig: NearIntentsEndpointConfig.build,
  );
});

final swapStatusPollIntervalProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 20);
});

final swapPriceRefreshIntervalProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 30);
});
