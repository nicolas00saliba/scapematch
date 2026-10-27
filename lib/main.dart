import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/scapematch_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The handle is intentionally not disposed: semantics stay on so screen
  // readers and the web accessibility tree can see the controls.
  SemanticsBinding.instance.ensureSemantics();
  await initializeDateFormatting('pt_BR');
  runApp(
    ProviderScope(
      // The screens already offer "Tentar de novo". A background retry
      // would hide the error state the user is supposed to see.
      retry: noAutomaticRetry,
      child: const ScapeMatchApp(),
    ),
  );
}
