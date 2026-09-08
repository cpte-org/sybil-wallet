@Tags(['mobile'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'zns_capture_support.dart';

void main() => runZnsLayoutTests(formFactor: AppFormFactor.mobile, width: 390);
