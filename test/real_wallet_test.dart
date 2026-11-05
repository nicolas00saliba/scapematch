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
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/account/presentation/account_screen.dart';
import 'package:scapematch/features/auth/data/fake_auth_repository.dart';
import 'package:scapematch/features/payments/data/fake_payment_methods_repository.dart';
import 'package:scapematch/features/payments/data/player_payments_repository.dart';
import 'package:scapematch/features/payments/domain/payment_method.dart';
import 'package:scapematch/features/payments/domain/player_charge.dart';
import 'package:scapematch/providers/repositories.dart';

void main() {
  testWidgets('a demonstração mantém saldo fictício e adicionar saldo', (
    tester,
  ) async {
    await _pump(tester, real: false);
    expect(find.text('Adicionar saldo'), findsOneWidget);
    expect(find.text('Meus pagamentos'), findsNothing);
    expect(
      find.text(
        'Créditos fictícios. Reembolsos simulados apareceriam aqui. Nada é cobrado.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('o modo real lista cartão, remove e mostra pagamentos', (
    tester,
  ) async {
    await tester.runAsync(_loadFonts);
    final cards = FakePaymentMethodsRepository(
      methods: [
        PaymentMethod(
          id: 'card-1',
          brand: CardBrand.visa,
          last4: '4242',
          nickname: 'Cartão',
        ),
      ],
    );
    final previous = scapeUsesLiveBackend;
    scapeUsesLiveBackend = true;
    addTearDown(() => scapeUsesLiveBackend = previous);
    await _pump(
      tester,
      real: true,
      cards: cards,
      payments: MemoryPlayerPaymentsRepository([
        PlayerCharge(
          id: 'pay-1',
          amountCents: 8000,
          roomName: 'Sala Sem Subconta',
          chargedAt: DateTime(2026, 6, 1, 19),
          status: 'paid',
          refunded: false,
        ),
        PlayerCharge(
          id: 'pay-2',
          amountCents: 4000,
          roomName: 'Sala Sem Subconta',
          chargedAt: DateTime(2026, 6, 2, 19),
          status: 'refunded',
          refunded: true,
        ),
      ]),
    );

    expect(find.text('Adicionar saldo'), findsNothing);
    expect(find.textContaining('Créditos fictícios'), findsNothing);
    expect(find.text('Cartão · Visa · 4242'), findsOneWidget);
    expect(find.text('Meus pagamentos'), findsOneWidget);
    expect(find.textContaining('Pago'), findsOneWidget);
    expect(find.textContaining('Reembolsado'), findsOneWidget);
    expect(find.text('Sala Sem Subconta'), findsNWidgets(2));

    await _capture(tester, find.byKey(AppKeys.accountWallet), 'carteira-real');
    await tester.tap(find.byKey(AppKeys.removeSavedCard('card-1')));
    await tester.pumpAndSettle();
    expect(find.text('Cartão · Visa · 4242'), findsNothing);
    expect(find.text('Nenhum cartão cadastrado'), findsOneWidget);
    expect(cards.list(), completion(isEmpty));
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required bool real,
  FakePaymentMethodsRepository? cards,
  PlayerPaymentsRepository? payments,
}) async {
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [
        if (real) ...[
          backendPlanProvider.overrideWithValue(planFor(AppMode.real)),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          paymentMethodsRepositoryProvider.overrideWithValue(
            cards ?? FakePaymentMethodsRepository(),
          ),
          playerPaymentsRepositoryProvider.overrideWithValue(
            payments ?? const EmptyPlayerPaymentsRepository(),
          ),
        ],
      ],
      child: MaterialApp(theme: _shotTheme(), home: const AccountScreen()),
    ),
  );
  await tester.pumpAndSettle();
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

Future<void> _capture(WidgetTester tester, Finder anchor, String name) async {
  final dir = Directory('/opt/cursor/artifacts');
  dir.createSync(recursive: true);
  await tester.ensureVisible(anchor);
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
  if (image == null) return;
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  if (bytes == null) return;
  File('${dir.path}/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
}
