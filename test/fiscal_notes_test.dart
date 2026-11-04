import 'package:dominio/dominio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/features/auth/data/fake_auth_repository.dart';
import 'package:scapematch/features/fiscal/presentation/service_invoice_card.dart';
import 'package:scapematch/features/groups/domain/attendance.dart';

import 'support/sample_clock.dart';

void main() {
  test('signup stores the terms version and the date', () async {
    final auth = FakeAuthRepository(signedIn: null);
    final now = DateTime(2026, 11, 4, 15, 30);
    final error = await auth.signUp(
      name: 'Ana',
      email: 'ana@exemplo.invalid',
      password: 'senha',
      birthDate: DateTime(1990, 1, 1),
      now: now,
      acceptedTerms: true,
    );
    expect(error, isNull);
    expect(auth.acceptances, hasLength(playerAcceptanceCodes.length));
    expect(
      auth.acceptances.map((row) => row.documentCode),
      containsAll(playerAcceptanceCodes),
    );
    expect(
      auth.acceptances.every(
        (row) =>
            row.audience == 'player' &&
            row.documentVersion == legalDocumentVersion &&
            row.acceptedAt == now,
      ),
      isTrue,
    );
  });

  test('the sample player sees a service invoice on the closed group', () {
    final database = loadSampleDatabase();
    final group = database.groups.firstWhere(
      (item) => item.id == SampleIds.groupCwbClosed,
    );
    final seat = group.participantForUser('user-local');
    expect(seat, isNotNull);
    expect(seat!.payment, PaymentStatus.paid);
    final invoice = serviceInvoiceFor(group: group, seat: seat);
    expect(invoice, isNotNull);
    expect(invoice!.kind, FiscalInvoiceKind.service);
    expect(invoice.status, FiscalInvoiceStatus.simulated);
    expect(invoice.playerName, 'Nícolas');
    expect(invoice.canDownload, isTrue);
    expect(invoice.pdfUrl, contains('api-sandbox.asaas.com'));
  });
}
