import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/app/url_strategy.dart';
import 'package:scapematch/features/theme/data/theme_choice_store.dart';
import 'package:scapematch/features/theme/presentation/theme_choice_controller.dart';
import 'package:scapematch_parceiro/parceiro_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await startScapeSupabase();
  configureUrlStrategy();
  SemanticsBinding.instance.ensureSemantics();
  await initializeDateFormatting('pt_BR');
  final themeStore = ThemeChoiceStore();
  await themeStore.load();
  runApp(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [themeChoiceStoreProvider.overrideWithValue(themeStore)],
      child: const ParceiroApp(),
    ),
  );
}
