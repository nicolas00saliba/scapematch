import 'dart:async';

import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../test/support/folga_golden.dart';

Future<void> testExecutable(Future<void> Function() testMain) async {
  await initializeDateFormatting('pt_BR');
  SharedPreferences.setMockInitialValues({});
  usarFolgaGolden();
  await testMain();
}
