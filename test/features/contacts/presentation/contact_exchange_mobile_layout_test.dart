@Tags(['mobile'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

import 'contact_exchange_capture_support.dart';
import 'contact_exchange_behavior_support.dart';

void main() {
  runContactExchangeBehaviorTests();
  runContactExchangeLayoutTests(formFactor: AppFormFactor.mobile, width: 390);
}
