import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/mode/app_mode.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/account/data/player_cpf_store.dart';
import 'package:scapematch/features/account/presentation/cpf_screen.dart';
import 'package:scapematch/features/payments/data/fake_payment_methods_repository.dart';
import 'package:scapematch/features/wallet/presentation/payment_methods_body.dart';
import 'package:scapematch/providers/repositories.dart';

void main() {
  test('os dígitos verificadores rejeitam CPF repetido', () async {
    final store = MemoryPlayerCpfStore();
    expect(await store.save('111.111.111-11'), 'CPF inválido.');
    expect(store.saved, isFalse);
    expect(await store.save('529.982.247-25'), isNull);
    expect(store.digits, '52998224725');
  });

  testWidgets('a tela pede o CPF, recusa número inválido e guarda o válido', (
    tester,
  ) async {
    await tester.runAsync(_loadFonts);
    final store = MemoryPlayerCpfStore();
    await _pump(tester, store);
    await tester.tap(find.text('pagar'));
    await tester.pumpAndSettle();

    expect(find.text('CPF'), findsWidgets);
    expect(
      find.text('Para pagar com Pix ou cartão, o Asaas precisa do seu CPF.'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(AppKeys.playerCpf), '111.111.111-11');
    await tester.tap(find.byKey(AppKeys.playerCpfSave));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.playerCpfError), findsOneWidget);
    expect(find.text('CPF inválido.'), findsOneWidget);
    expect(store.saved, isFalse);
    await _capture(tester, 'cpf-jogador-invalido');

    await tester.enterText(find.byKey(AppKeys.playerCpf), '529.982.247-25');
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.playerCpfError), findsNothing);
    await _capture(tester, 'cpf-jogador');
    await tester.tap(find.byKey(AppKeys.playerCpfSave));
    await tester.pumpAndSettle();
    expect(store.digits, '52998224725');
    expect(find.text('pagar'), findsOneWidget);
    expect(find.byKey(AppKeys.playerCpf), findsNothing);
  });

  testWidgets('a demonstração paga sem pedir CPF', (tester) async {
    final store = MemoryPlayerCpfStore();
    await _pump(tester, store, real: false);
    await tester.tap(find.text('pagar'));
    await tester.pumpAndSettle();
    expect(find.text('ok'), findsOneWidget);
    expect(find.byKey(AppKeys.playerCpf), findsNothing);
  });

  testWidgets('guardar cartão no modo real abre o CPF antes da tokenização', (
    tester,
  ) async {
    final store = MemoryPlayerCpfStore();
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [
          backendPlanProvider.overrideWithValue(planFor(AppMode.real)),
          playerCpfStoreProvider.overrideWithValue(store),
          paymentMethodsRepositoryProvider.overrideWithValue(
            FakePaymentMethodsRepository(),
          ),
        ],
        child: MaterialApp(home: const Scaffold(body: PaymentMethodsBody())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.addCard));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(AppKeys.cardHolder), 'Ana');
    await tester.enterText(find.byKey(AppKeys.cardNumber), '4111111111111111');
    await tester.enterText(find.byKey(AppKeys.cardMonth), '12');
    await tester.enterText(find.byKey(AppKeys.cardYear), '2028');
    await tester.enterText(find.byKey(AppKeys.cardSecurity), '123');
    await tester.tap(find.byKey(AppKeys.addCardSave));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.playerCpf), findsOneWidget);
    expect(store.saved, isFalse);
  });
}

Future<void> _pump(
  WidgetTester tester,
  MemoryPlayerCpfStore store, {
  bool real = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [
        backendPlanProvider.overrideWithValue(
          planFor(real ? AppMode.real : AppMode.demo),
        ),
        playerCpfStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp(theme: _shotTheme(), home: const _PayGate()),
    ),
  );
  await tester.pumpAndSettle();
}

class _PayGate extends ConsumerWidget {
  const _PayGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: ListView(
        children: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
            onPressed: () async {
              final ok = await ensurePlayerCpf(context, ref);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(ok ? 'ok' : 'nao')));
            },
            child: const Text('pagar'),
          ),
        ],
      ),
    );
  }
}

ThemeData _shotTheme() {
  final theme = buildAppTheme(Brightness.light);
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Roboto'),
  );
}

Future<void> _loadFonts() async {
  final dir = _fontDir();
  if (dir == null) return;
  Future<ByteData> bytes(String name) async {
    final data = File('$dir/$name').readAsBytesSync();
    return ByteData.view(Uint8List.fromList(data).buffer);
  }

  final roboto = FontLoader('Roboto')
    ..addFont(bytes('Roboto-Regular.ttf'))
    ..addFont(bytes('Roboto-Medium.ttf'))
    ..addFont(bytes('Roboto-Bold.ttf'));
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('MaterialIcons-Regular.otf'));
  await roboto.load();
  await icons.load();
}

String? _fontDir() {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    final candidate = '${dir.path}/artifacts/material_fonts';
    if (File('$candidate/Roboto-Regular.ttf').existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

Future<void> _capture(WidgetTester tester, String name) async {
  final dir = Directory('/opt/cursor/artifacts');
  dir.createSync(recursive: true);
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(AppKeys.playerCpfScreen),
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
  if (image == null) return;
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  if (bytes == null) return;
  File('${dir.path}/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
}
