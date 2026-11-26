import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_app.dart';
import 'package:scapematch_admin/admin_ops.dart';
import 'package:scapematch_admin/admin_people.dart';
import 'package:scapematch_admin/admin_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tela da casa no tamanho de um celular (a do Nícolas no Android): cada botão
/// grava, a tela relê o valor e o aviso aparece à vista, não no fim da página.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Salvar dados grava a cidade escolhida na lista e relê', (
    tester,
  ) async {
    final api = MemoryAdminApi();
    await _openHouse(tester, api, 'Ninja Escape');
    expect(find.byKey(const Key('admin-cidade-escolhida')), findsOneWidget);

    await _reveal(tester, find.byKey(const Key('admin-cidade-uf')));
    // A UF abre na da casa (PR). A busca ignora acento e caixa.
    await tester.enterText(
      find.byKey(const Key('admin-cidade-busca')),
      'ARAPOTI',
    );
    await tester.pump();
    await _reveal(
      tester,
      find.byKey(const Key('admin-cidade-opcao-arapoti-pr')),
    );
    await tester.tap(find.byKey(const Key('admin-cidade-opcao-arapoti-pr')));
    await tester.pump();
    expect(find.text('Cidade: Arapoti · PR'), findsOneWidget);

    await _tapSave(tester, 'admin-salvar-casa');
    expect(api.houses.first.cityId, 'arapoti-pr');
    expect(api.houses.first.cityName, 'Arapoti');
    expect(find.text('Cidade: Arapoti · PR'), findsOneWidget);
    _expectNotice(tester, 'Dados gravados.');
  });

  testWidgets('a cidade só aceita o que existe na lista, de outra UF também', (
    tester,
  ) async {
    final api = MemoryAdminApi();
    await _openHouse(tester, api, 'Ninja Escape');
    await _reveal(tester, find.byKey(const Key('admin-cidade-uf')));
    await tester.tap(find.byKey(const Key('admin-cidade-uf')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('SP').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const Key('admin-cidade-busca')),
      'sao jose',
    );
    await tester.pump();
    await _reveal(
      tester,
      find.byKey(const Key('admin-cidade-opcao-sao-jose-do-rio-preto-sp')),
    );
    await tester.tap(
      find.byKey(const Key('admin-cidade-opcao-sao-jose-do-rio-preto-sp')),
    );
    await tester.pump();
    await _tapSave(tester, 'admin-salvar-casa');
    expect(api.houses.first.cityId, 'sao-jose-do-rio-preto-sp');
    _expectNotice(tester, 'Dados gravados.');
  });

  testWidgets('Salvar dados diz qual campo está errado e não grava', (
    tester,
  ) async {
    final api = MemoryAdminApi();
    await _openHouse(tester, api, 'Ninja Escape');
    await _reveal(tester, find.byKey(const Key('admin-casa-cep')));
    await tester.enterText(find.byKey(const Key('admin-casa-cep')), '123');
    await _tapSave(tester, 'admin-salvar-casa');
    expect(api.houses.first.postalCode, '80420010');
    _expectNotice(tester, 'CEP: 8 números, sem hífen.', error: true);
  });

  testWidgets('CEP e telefone com símbolos são limpos ao gravar', (
    tester,
  ) async {
    final api = MemoryAdminApi();
    await _openHouse(tester, api, 'Ninja Escape');
    await _reveal(tester, find.byKey(const Key('admin-casa-cep')));
    await tester.enterText(
      find.byKey(const Key('admin-casa-cep')),
      '84990-000',
    );
    await tester.enterText(
      find.byKey(const Key('admin-casa-telefone')),
      '(43) 99119-0055',
    );
    await _tapSave(tester, 'admin-salvar-casa');
    expect(api.houses.first.postalCode, '84990000');
    expect(api.houses.first.phone, '43991190055');
    _expectNotice(tester, 'Dados gravados.');
  });

  testWidgets('Gravar comissão confirma, grava e a caixa mostra o valor lido', (
    tester,
  ) async {
    final api = MemoryAdminApi();
    await _openHouse(tester, api, 'Ninja Escape');
    await tester.enterText(find.byKey(const Key('admin-comissao')), '22,5');
    await tester.pump();
    await _tapSave(tester, 'admin-gravar-comissao', settle: false);
    await tester.tap(find.byKey(const Key('admin-confirmar-comissao')));
    await _frames(tester);
    expect(api.houses.first.commissionBps, 2250);
    expect(api.houses.first.commissionOverride, isTrue);
    _expectNotice(
      tester,
      'Comissão gravada em 22,5%. As reservas antigas não mudam.',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('admin-comissao')))
          .controller!
          .text,
      '22,5',
    );
  });

  testWidgets('comissão fora de 0 a 30 mostra o erro à vista', (tester) async {
    final api = MemoryAdminApi();
    await _openHouse(tester, api, 'Ninja Escape');
    await tester.enterText(find.byKey(const Key('admin-comissao')), '45');
    await _tapSave(tester, 'admin-gravar-comissao');
    _expectNotice(
      tester,
      'A comissão fica entre 0% e 30%, com até duas casas decimais.',
      error: true,
    );
  });

  testWidgets('Gravar contato oficial grava e relê o valor normalizado', (
    tester,
  ) async {
    final api = MemoryAdminApi();
    await _openHouse(tester, api, 'Ninja Escape');
    await tester.enterText(
      find.byKey(const Key('admin-contato-email')),
      'Oficial@Ninja.Example',
    );
    await tester.enterText(
      find.byKey(const Key('admin-contato-telefone')),
      '(41) 99999-0001',
    );
    await _tapSave(tester, 'admin-gravar-contato');
    _expectNotice(tester, 'Contato oficial gravado.');
    expect(api.houses.first.officialEmail, 'oficial@ninja.example');
    // A caixa mostra o que o servidor guardou, não o que foi digitado.
    expect(find.text('oficial@ninja.example'), findsOneWidget);
    expect(find.text('41999990001'), findsOneWidget);
  });

  testWidgets('contato oficial vazio avisa à vista', (tester) async {
    final api = MemoryAdminApi();
    await _openHouse(tester, api, 'Ninja Escape');
    await _tapSave(tester, 'admin-gravar-contato');
    _expectNotice(
      tester,
      'Informe o e-mail ou o telefone oficial.',
      error: true,
    );
  });

  testWidgets('a chave Casa de teste grava e continua ligada ao reabrir', (
    tester,
  ) async {
    final api = MemoryAdminApi();
    final people = MemoryAdminPeopleApi(venues: api);
    await _openHouse(tester, api, 'Ninja Escape', people: people);
    await _reveal(tester, find.byKey(const Key('admin-casa-teste')));
    await tester.tap(find.byKey(const Key('admin-casa-teste')));
    await _frames(tester);
    expect(people.venueTest, isTrue);
    expect(api.houses.first.isTest, isTrue);
    _expectNotice(tester, 'Casa marcada como teste.');
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('admin-casa-teste')))
          .value,
      isTrue,
    );
  });

  testWidgets('Suspender e Reativar gravam e mudam o estado da tela', (
    tester,
  ) async {
    final api = MemoryAdminApi();
    await _openHouse(tester, api, 'Ninja Escape');
    await tester.tap(find.byKey(const Key('admin-suspender')));
    await _frames(tester);
    expect(api.houses.first.suspended, isTrue);
    expect(find.text('Reativar'), findsOneWidget);
    expect(find.textContaining('suspensa ·'), findsOneWidget);
    _expectNotice(
      tester,
      'Casa suspensa. Ela some para o jogador até reativar.',
    );

    await tester.tap(find.byKey(const Key('admin-suspender')));
    await _frames(tester);
    expect(api.houses.first.suspended, isFalse);
    _expectNotice(tester, 'Casa reativada.');
  });

  testWidgets('Mesclar pede a palavra, aceita minúscula e marca a origem', (
    tester,
  ) async {
    final api = MemoryAdminApi();
    final people = MemoryAdminPeopleApi(venues: api);
    await _openHouse(tester, api, 'Casa da Fila', people: people);
    await _reveal(tester, find.byKey(const Key('admin-mesclar')));

    // Sem escolher a casa que fica, avisa e não abre confirmação.
    await tester.tap(find.byKey(const Key('admin-mesclar')));
    await _frames(tester);
    _expectNotice(
      tester,
      'Escolha a casa que fica antes de mesclar.',
      error: true,
    );
    expect(find.byKey(const Key('admin-confirm-word')), findsNothing);

    await tester.tap(find.byKey(const Key('admin-mesclar-destino')));
    await _frames(tester);
    await tester.tap(find.textContaining('Ninja Escape · curitiba').last);
    await _frames(tester);
    await _reveal(tester, find.byKey(const Key('admin-mesclar')));
    await tester.tap(find.byKey(const Key('admin-mesclar')));
    await _frames(tester);

    // Palavra errada: o botão diz por quê, em vez de ficar mudo.
    await tester.enterText(find.byKey(const Key('admin-confirm-word')), 'nao');
    await tester.tap(find.byKey(const Key('admin-confirm-ok')));
    await _frames(tester);
    expect(find.text('Digite exatamente MESCLAR.'), findsOneWidget);
    expect(people.merged, isFalse);

    // O teclado do celular entrega minúscula: vale.
    await tester.enterText(
      find.byKey(const Key('admin-confirm-word')),
      'mesclar',
    );
    await tester.tap(find.byKey(const Key('admin-confirm-ok')));
    await _frames(tester);
    expect(people.merged, isTrue);
    expect(api.houses.last.status, 'merged');
    expect(find.textContaining('unida a outra'), findsOneWidget);
    _expectNotice(
      tester,
      'Casas mescladas. Casa da Fila ficou como mesclada em Ninja Escape.',
    );
  });

  testWidgets('Voltar à comissão oficial limpa a taxa própria', (tester) async {
    final api = MemoryAdminApi();
    final people = MemoryAdminPeopleApi(venues: api);
    await _openHouse(tester, api, 'Ninja Escape', people: people);
    expect(api.houses.first.commissionOverride, isTrue);
    expect(_fieldText(tester, 'admin-comissao'), '20');

    await _reveal(tester, find.byKey(const Key('admin-comissao-oficial')));
    await tester.tap(find.byKey(const Key('admin-comissao-oficial')));
    await _frames(tester);
    await tester.enterText(
      find.byKey(const Key('admin-confirm-word')),
      'oficial',
    );
    await tester.tap(find.byKey(const Key('admin-confirm-ok')));
    await _frames(tester);
    expect(people.cleared, isTrue);
    expect(api.houses.first.commissionOverride, isFalse);
    _expectNotice(tester, 'A casa voltou a usar a comissão oficial.');
    expect(_fieldText(tester, 'admin-comissao'), '25');
  });

  testWidgets('Voltar à comissão oficial diz quando a casa já usa a oficial', (
    tester,
  ) async {
    final api = MemoryAdminApi();
    await _openHouse(tester, api, 'Casa da Fila');
    await _reveal(tester, find.byKey(const Key('admin-comissao-oficial')));
    await tester.tap(find.byKey(const Key('admin-comissao-oficial')));
    await _frames(tester);
    expect(find.byKey(const Key('admin-confirm-word')), findsNothing);
    _expectNotice(tester, 'Esta casa já usa a comissão oficial (25%).');
  });

  testWidgets('Gravar comissão oficial pede COMISSAO e grava', (tester) async {
    final api = MemoryAdminApi();
    await _openHouse(tester, api, 'Ninja Escape');
    await tester.enterText(
      find.byKey(const Key('admin-comissao-plataforma')),
      '24',
    );
    await _tapSave(tester, 'admin-gravar-plataforma', settle: false);
    await tester.enterText(
      find.byKey(const Key('admin-confirm-word')),
      'comissao',
    );
    await tester.tap(find.byKey(const Key('admin-confirm-ok')));
    await _frames(tester);
    expect(api.platformBps, 2400);
    _expectNotice(tester, 'Comissão oficial gravada em 24%.');
  });

  testWidgets('Salas e sessões abre a operação da casa', (tester) async {
    final api = MemoryAdminApi();
    await _openHouse(tester, api, 'Ninja Escape', ops: MemoryAdminOpsApi());
    await _reveal(tester, find.byKey(const Key('admin-casa-operacao')));
    await tester.tap(find.byKey(const Key('admin-casa-operacao')));
    await _frames(tester);
    expect(find.byKey(const Key('admin-operacao')), findsOneWidget);
    expect(find.byTooltip('Voltar à casa'), findsOneWidget);
  });

  testWidgets('erro de rede ou de permissão aparece, nunca silêncio', (
    tester,
  ) async {
    final api = _FailingApi();
    await _openHouse(tester, api, 'Ninja Escape');
    await tester.enterText(find.byKey(const Key('admin-comissao')), '20');
    await _tapSave(tester, 'admin-gravar-comissao', settle: false);
    await tester.tap(find.byKey(const Key('admin-confirmar-comissao')));
    await _frames(tester);
    _expectNotice(tester, 'Esta conta não é admin.', error: true);

    api.failContacts = true;
    await tester.enterText(
      find.byKey(const Key('admin-contato-email')),
      'a@b.example',
    );
    await _tapSave(tester, 'admin-gravar-contato');
    _expectNotice(
      tester,
      'Sem resposta do servidor. Confira a internet e tente de novo.',
      error: true,
    );
  });

  testWidgets('toque duplo em Salvar dados grava uma vez só', (tester) async {
    final api = _SlowApi();
    await _openHouse(tester, api, 'Ninja Escape');
    await _reveal(tester, find.byKey(const Key('admin-salvar-casa')));
    await tester.tap(find.byKey(const Key('admin-salvar-casa')));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('admin-salvar-casa')),
      warnIfMissed: false,
    );
    await tester.pump();
    api.release();
    await _frames(tester);
    expect(api.updates, 1);
  });
}

class _FailingApi extends MemoryAdminApi {
  bool failContacts = false;

  @override
  Future<void> setCommission({String? venueId, required int bps}) async {
    throw const PostgrestException(message: 'not admin', code: '42501');
  }

  @override
  Future<void> setVenueContacts(String venueId, String email, String phone) {
    if (failContacts) throw _ClientException();
    return super.setVenueContacts(venueId, email, phone);
  }
}

class _ClientException implements Exception {}

class _SlowApi extends MemoryAdminApi {
  final _gate = Completer<void>();
  int updates = 0;

  void release() => _gate.complete();

  @override
  Future<VenueProfile> updateVenue(
    String id,
    Map<String, Object?> patch,
  ) async {
    updates++;
    await _gate.future;
    return super.updateVenue(id, patch);
  }
}

const _phone = Size(390, 844);

Future<void> _openHouse(
  WidgetTester tester,
  MemoryAdminApi api,
  String name, {
  MemoryAdminPeopleApi? people,
  AdminOpsApi? ops,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _phone;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [
        adminApiProvider.overrideWithValue(api),
        adminPeopleProvider.overrideWithValue(
          people ?? MemoryAdminPeopleApi(venues: api),
        ),
        if (ops != null) adminOpsProvider.overrideWithValue(ops),
        adminSessionProvider.overrideWith(_Ready.new),
      ],
      child: const AdminApp(),
    ),
  );
  await _frames(tester);
  await tester.tap(find.text(name));
  await _frames(tester);
  expect(find.byKey(const Key('admin-comissao')), findsOneWidget);
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  // Um quadro antes e dois depois: o rolar do campo e o do botão assentam.
  await tester.pump();
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

String _fieldText(WidgetTester tester, String key) {
  return tester.widget<TextField>(find.byKey(Key(key))).controller!.text;
}

/// Rola até o botão, toca e espera a gravação terminar.
Future<void> _tapSave(
  WidgetTester tester,
  String key, {
  bool settle = true,
}) async {
  final finder = find.byKey(Key(key));
  await _reveal(tester, finder);
  await tester.tap(finder);
  await _frames(tester);
  if (!settle) return;
}

/// O aviso existe, tem o texto e está dentro da tela do celular.
void _expectNotice(WidgetTester tester, String text, {bool error = false}) {
  final finder = find.byKey(const Key('admin-casa-aviso'));
  expect(finder, findsOneWidget, reason: 'sem aviso: esperava "$text"');
  expect(tester.widget<Text>(finder).data, text);
  final rect = tester.getRect(finder);
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(_phone.height));
  expect(
    find.byIcon(error ? Icons.error_outline : Icons.check_circle_outline),
    findsOneWidget,
  );
}

class _Ready extends AdminSessionController {
  @override
  AdminSession build() {
    return const AdminSession(
      phase: AdminPhase.ready,
      name: 'Nícolas',
      email: 'admin@scapematch.exemplo',
    );
  }
}
