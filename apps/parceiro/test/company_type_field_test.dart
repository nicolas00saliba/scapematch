import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_parceiro/features/partner/presentation/company_type_field.dart';

void main() {
  testWidgets('CNPJ pergunta o tipo e CPF esconde a pergunta', (tester) async {
    var value = 'LIMITED';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CompanyTypeField(
              documentKind: 'cnpj',
              value: value,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Sociedade limitada (LTDA)'), findsOneWidget);
    await tester.tap(find.byKey(CompanyTypeField.fieldKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MEI').last);
    await tester.pumpAndSettle();
    expect(value, 'MEI');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CompanyTypeField(
            documentKind: 'cpf',
            value: 'LIMITED',
            onChanged: _ignore,
          ),
        ),
      ),
    );
    expect(find.byKey(CompanyTypeField.fieldKey), findsNothing);
  });
}

void _ignore(String value) {}
