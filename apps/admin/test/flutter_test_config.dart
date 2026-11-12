import 'dart:async';

import '../../../test/support/folga_golden.dart';

Future<void> testExecutable(Future<void> Function() testMain) async {
  usarFolgaGolden();
  await testMain();
}
