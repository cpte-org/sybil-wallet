import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'zns_capture_support.dart';

void main() =>
    runZnsLayoutTests(formFactor: AppFormFactor.desktop, width: 1000);
