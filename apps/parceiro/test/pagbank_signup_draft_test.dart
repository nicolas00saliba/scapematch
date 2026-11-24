import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_parceiro/features/partner/domain/pagbank_signup.dart';

void main() {
  final clock = DateTime.utc(2026, 11, 24);

  test('aceita CPF e CNPJ válidos e recusa menor de idade', () {
    expect(pagbankBusinessCategoryLabels.length, 52);
    expect(
      PagbankSignupDraft.issue(
        documentKind: 'cpf',
        documentNumber: '529.982.247-25',
        companyName: 'Casa Escape',
        postalCode: '80010-010',
        street: 'Rua das Salas',
        number: '10',
        complement: '',
        locality: 'Centro',
        city: 'Curitiba',
        regionCode: 'pr',
        responsibleName: 'Ana Souza',
        responsibleCpf: '',
        birthDate: '1991-10-10',
        phone: '(11) 98765-4321',
        email: 'ana@casa.example',
        businessCategory: 'ENTERTAINMENT',
        termsAccepted: true,
        today: clock,
      ),
      isNull,
    );
    final company = PagbankSignupDraft.tryParse(
      documentKind: 'cnpj',
      documentNumber: '11.222.333/0001-81',
      companyName: 'Casa Escape Ltda',
      postalCode: '80010010',
      street: 'Rua das Salas',
      number: '10',
      complement: 'sala 2',
      locality: 'Centro',
      city: 'Curitiba',
      regionCode: 'PR',
      responsibleName: 'Ana Souza',
      responsibleCpf: '52998224725',
      birthDate: '1991-10-10',
      phone: '11987654321',
      email: 'ana@casa.example',
      businessCategory: 'ENTERTAINMENT',
      termsAccepted: true,
      today: clock,
    );
    expect(company?.documentNumber, '11222333000181');
    expect(company?.responsibleCpf, '52998224725');
    expect(company?.toCreateJson('casa')['terms_accepted'], isTrue);
    expect(
      PagbankSignupDraft.issue(
        documentKind: 'cpf',
        documentNumber: '52998224725',
        companyName: 'Casa Escape',
        postalCode: '80010010',
        street: 'Rua das Salas',
        number: '10',
        complement: '',
        locality: 'Centro',
        city: 'Curitiba',
        regionCode: 'PR',
        responsibleName: 'Ana Souza',
        responsibleCpf: '',
        birthDate: '2010-01-01',
        phone: '11987654321',
        email: 'ana@casa.example',
        businessCategory: 'ENTERTAINMENT',
        termsAccepted: true,
        today: clock,
      ),
      'nascimento',
    );
    expect(
      PagbankSignupDraft.issue(
        documentKind: 'cpf',
        documentNumber: '52998224725',
        companyName: 'Casa Escape',
        postalCode: '80010010',
        street: 'Rua das Salas',
        number: '10',
        complement: '',
        locality: 'Centro',
        city: 'Curitiba',
        regionCode: 'PR',
        responsibleName: 'Ana Souza',
        responsibleCpf: '',
        birthDate: '1991-10-10',
        phone: '11987654321',
        email: 'ana@casa.example',
        businessCategory: 'ESCAPE_ROOM',
        termsAccepted: true,
        today: clock,
      ),
      'categoria',
    );
  });
}
