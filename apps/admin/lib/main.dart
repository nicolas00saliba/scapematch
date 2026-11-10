import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/url_strategy.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch_admin/admin_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootScapeBackend();
  configureUrlStrategy();
  await initializeDateFormatting('pt_BR');
  runApp(
    ProviderScope(
      retry: noAutomaticRetry,
      child: const AdminApp(),
    ),
  );
}
