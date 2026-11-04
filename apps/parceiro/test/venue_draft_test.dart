import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_draft.dart';

void main() {
  VenueDraft draft({
    String documentKind = 'cnpj',
    String documentNumber = '04.252.011/0001-10',
    String inviteCode = 'ninja-cwb',
    String phone = '(41) 99999-0000',
    String postalCode = '80020-310',
  }) {
    return VenueDraft(
      name: 'Ninja Escape Room',
      cityId: 'curitiba',
      neighborhood: 'Centro',
      street: 'Rua XV de Novembro',
      number: '100',
      postalCode: postalCode,
      phone: phone,
      documentKind: documentKind,
      documentNumber: documentNumber,
      category: 'escape-room',
      incomeReais: '5000',
      inviteCode: inviteCode,
    );
  }

  test('a house draft accepts cpf or cnpj and an invite code', () {
    expect(draft().validate(), isNull);
    expect(
      draft(documentKind: 'cpf', documentNumber: '123.456.789-09').validate(),
      isNull,
    );
    expect(draft(inviteCode: '').validate(), isNull);
    expect(VenueDraft.digits('04.252.011/0001-10'), '04252011000110');
  });

  test('a house draft rejects a short document and a bad invite', () {
    expect(
      draft(documentKind: 'cpf', documentNumber: '123').validate(),
      contains('CPF'),
    );
    expect(draft(inviteCode: 'Ninja CWB').validate(), contains('convite'));
    expect(draft(postalCode: '800').validate(), contains('CEP'));
    expect(draft(phone: '123').validate(), contains('telefone'));
  });
}
