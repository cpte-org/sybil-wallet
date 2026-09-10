@Tags(['mobile'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'contact_introduction_behavior_support.dart';

void main() => introductionWidgetTests(AppFormFactor.mobile);
