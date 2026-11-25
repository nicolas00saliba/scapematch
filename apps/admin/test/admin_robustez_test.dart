import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_errors.dart';
import 'package:scapematch_admin/admin_format.dart';
import 'package:scapematch_admin/admin_pages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RecordingApi extends MemoryAdminApi {
  final highlightCalls = <int?>[];
  final rewardPatches = <Map<String, Object?>>[];
  bool failVenue = false;
  bool failAudit = false;

  @override
  Future<void> setHighlight(String kind, String id, int? rank) async {
    highlightCalls.add(rank);
    await super.setHighlight(kind, id, rank);
  }

  @override
  Future<Map<String, Object?>> saveRewardSettings(
    Map<String, Object?> patch,
  ) async {
    rewardPatches.add(patch);
    return super.saveRewardSettings(patch);
  }

  @override
  Future<VenueProfile> venue(String id) async {
    if (failVenue) {
      throw const PostgrestException(message: 'mfa obrigatorio', code: '42501');
    }
    return super.venue(id);
  }

  @override
  Future<List<AuditRow>> audit() async {
    if (failAudit) throw const PostgrestException(message: 'boom');
    return super.audit();
  }
}

Future<void> _pump(
  WidgetTester tester,
  AdminApi api,
  Widget page, {
  double height = 2400,
}) async {
  tester.view.physicalSize = Size(1280, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [adminApiProvider.overrideWithValue(api)],
      child: MaterialApp(home: Scaffold(body: page)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('hora do painel é a de Brasília, não a do aparelho', () {
    // 02:30 UTC do dia 1 ainda é 23:30 do dia anterior em Curitiba.
    expect(whenLabel(DateTime.utc(2026, 12, 1, 2, 30)), '30/11/2026 23:30');
    expect(whenLabel(DateTime.utc(2026, 11, 25, 15)), '25/11/2026 12:00');
  });

  test('"Este mês" começa à meia-noite de Brasília', () {
    expect(
      brasiliaMonthStartUtc(DateTime.utc(2026, 11, 25, 12)),
      DateTime.utc(2026, 11, 1, 3),
    );
    // 01:00 UTC de 1º/12 ainda é novembro em Curitiba.
    expect(
      brasiliaMonthStartUtc(DateTime.utc(2026, 12, 1, 1)),
      DateTime.utc(2026, 11, 1, 3),
    );
  });

  test('erro do servidor vira texto curto', () {
    expect(
      adminErrorText(const PostgrestException(message: 'mfa obrigatorio')),
      'A sessão perdeu o segundo fator. Saia e entre de novo.',
    );
    expect(adminErrorText(const AdminRejected('x')), 'x');
    expect(adminErrorText(StateError('y')), 'Não deu certo. Tente de novo.');
  });

  testWidgets('ordem inválida em Destaques não tira o item', (tester) async {
    final api = _RecordingApi();
    await _pump(tester, api, const DestaquesPage());
    final field = find.byType(TextField).first;
    await tester.enterText(field, 'abc');
    await tester.tap(find.byTooltip('Gravar').first);
    await tester.pumpAndSettle();
    expect(api.highlightCalls, isEmpty);
    expect(
      find.text(
        'A ordem é um número inteiro a partir de 1. Vazio tira o item.',
      ),
      findsOneWidget,
    );
    await tester.enterText(field, '2');
    await tester.tap(find.byTooltip('Gravar').first);
    await tester.pumpAndSettle();
    expect(api.highlightCalls, [2]);
  });

  testWidgets('campo vazio em Regras não grava zero', (tester) async {
    final api = _RecordingApi();
    await _pump(tester, api, const RegrasPage(), height: 12000);
    await tester.enterText(
      find.byKey(const Key('admin-regra-first_booking_discount_bps')),
      '',
    );
    await tester.tap(find.byKey(const Key('admin-salvar-regras')));
    await tester.pumpAndSettle();
    expect(api.rewardPatches, isEmpty);
    expect(
      tester.widget<Text>(find.byKey(const Key('admin-regras-aviso'))).data,
      contains('Campo vazio não vira zero'),
    );
  });

  testWidgets('casa que não carrega mostra o motivo', (tester) async {
    final api = _RecordingApi()..failVenue = true;
    await _pump(tester, api, const CasaPage(id: 'casa-ninja'));
    expect(find.text('Carregando casa…'), findsNothing);
    expect(
      find.text('A sessão perdeu o segundo fator. Saia e entre de novo.'),
      findsOneWidget,
    );
  });

  testWidgets('auditoria que falha não diz "nenhuma ação"', (tester) async {
    final api = _RecordingApi()..failAudit = true;
    await _pump(tester, api, const AuditoriaPage());
    expect(find.text('Nenhuma ação ainda.'), findsNothing);
    expect(find.byKey(const Key('admin-auditoria-aviso')), findsOneWidget);
  });
}
