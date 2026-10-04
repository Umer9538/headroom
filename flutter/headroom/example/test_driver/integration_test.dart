import 'package:integration_test/integration_test_driver.dart';

/// Lets the probe test run under `flutter drive`, including in profile mode:
///
///     flutter drive --driver=test_driver/integration_test.dart \
///       --target=integration_test/probe_test.dart --profile -d <device>
Future<void> main() => integrationDriver();
