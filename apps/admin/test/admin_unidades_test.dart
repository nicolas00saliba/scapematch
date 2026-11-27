import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_unidades.dart';

class _FakeUnits implements AdminUnitsApi {
  _FakeUnits(this.current, {this.fail});

  AdminUnitState current;
  final String? fail;
  final calls = <String>[];

  @override
  Future<AdminUnitState> state(String venueId) async => current;

  @override
  Future<void> reactivate(String venueId) async {
    calls.add('reactivate:$venueId');
    if (fail != null) throw AdminRejected(fail!);
    current = AdminUnitState(
      deactivated: false,
      deactivatedByOwner: false,
      hasAccount: current.hasAccount,
      sharedFromName: current.sharedFromName,
      sources: current.sources,
    );
  }

  @override
  Future<void> share(String venueId, String sourceVenueId) async {
    calls.add('share:$venueId:$sourceVenueId');
    if (fail != null) throw AdminRejected(fail!);
    current = const AdminUnitState(
      deactivated: false,
      deactivatedByOwner: false,
      hasAccount: true,
      sharedFromName: 'Minos Curitiba',
      sources: [],
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeUnits api, {
  VoidCallback? onChanged,
}) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminUnitsApiProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: Scaffold(
          body: AdminUnitsCard(venueId: 'cvel', onChanged: onChanged),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester, String word) async {
  await tester.enterText(find.byType(TextField).last, word);
  await tester.pumpAndSettle();
  final buttons = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byWidgetPredicate(
      (widget) => widget is FilledButton || widget is ElevatedButton,
    ),
  );
  await tester.tap(buttons.last);
  await tester.pumpAndSettle();
}

void main() {
  test('lê o estado de unidade do servidor', () {
    final state = AdminUnitState.fromJson({
      'deactivated': true,
      'deactivated_by_owner': true,
      'has_account': false,
      'shared_from_name': null,
      'share_sources': [
        {
          'venue_id': 'cwb',
          'venue_name': 'Minos Curitiba',
          'city_name': 'Curitiba',
          'account_last4': '4321',
        },
        {'sem': 'id'},
      ],
    });
    expect(state.deactivated, isTrue);
    expect(state.deactivatedByOwner, isTrue);
    expect(state.sources, hasLength(1));
    expect(
      state.sources.single.label,
      'Curitiba (Minos Curitiba) · conta final 4321',
    );
    expect(AdminUnitState.fromJson(null).sources, isEmpty);
  });

  testWidgets('sem nada a fazer, o cartão não aparece', (tester) async {
    await _pump(
      tester,
      _FakeUnits(
        const AdminUnitState(
          deactivated: false,
          deactivatedByOwner: false,
          hasAccount: true,
          sharedFromName: null,
          sources: [],
        ),
      ),
    );
    expect(find.byKey(const Key('admin-unidades')), findsNothing);
  });

  testWidgets('reativa cidade removida com confirmação digitada', (
    tester,
  ) async {
    var changed = 0;
    final api = _FakeUnits(
      const AdminUnitState(
        deactivated: true,
        deactivatedByOwner: false,
        hasAccount: false,
        sharedFromName: null,
        sources: [],
      ),
    );
    await _pump(tester, api, onChanged: () => changed++);
    expect(find.textContaining('removida pelo suporte'), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin-reativar-cidade')));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    await _confirm(tester, 'REATIVAR');
    expect(api.calls, ['reactivate:cvel']);
    expect(changed, 1);
    expect(find.text('Cidade reativada.'), findsOneWidget);
  });

  testWidgets('compartilha a conta de outra cidade do dono', (tester) async {
    final api = _FakeUnits(
      const AdminUnitState(
        deactivated: false,
        deactivatedByOwner: false,
        hasAccount: false,
        sharedFromName: null,
        sources: [
          AdminShareSource(
            venueId: 'cwb',
            venueName: 'Minos Curitiba',
            cityName: 'Curitiba',
            accountLast4: '4321',
          ),
        ],
      ),
    );
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('admin-compartilhar-cwb')));
    await tester.pumpAndSettle();
    await _confirm(tester, 'COMPARTILHAR');
    expect(api.calls, ['share:cvel:cwb']);
    expect(
      find.textContaining('Recebe pela conta PagBank de Minos Curitiba'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('admin-compartilhar-cwb')), findsNothing);
  });

  testWidgets('recusa do servidor aparece no cartão', (tester) async {
    final api = _FakeUnits(
      const AdminUnitState(
        deactivated: false,
        deactivatedByOwner: false,
        hasAccount: false,
        sharedFromName: null,
        sources: [
          AdminShareSource(
            venueId: 'cwb',
            venueName: 'Minos Curitiba',
            cityName: '',
            accountLast4: '',
          ),
        ],
      ),
      fail: 'pagbank_share_invalid',
    );
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('admin-compartilhar-cwb')));
    await tester.pumpAndSettle();
    await _confirm(tester, 'COMPARTILHAR');
    expect(find.textContaining('mesmo dono'), findsOneWidget);
  });
}
