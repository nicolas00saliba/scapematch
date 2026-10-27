import 'dart:async';

import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> testExecutable(Future<void> Function() testMain) async {
  await initializeDateFormatting('pt_BR');
  SharedPreferences.setMockInitialValues({});
  await testMain();
}
