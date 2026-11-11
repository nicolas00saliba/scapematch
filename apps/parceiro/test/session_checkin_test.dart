import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

import 'support/pump_parceiro.dart';

void main() {
  testWidgets('a casa confirma o comparecimento na sessão que já começou', (
    tester,
  ) async {
    await pumpParceiro(tester, size: const Size(900, 1400));
    await tester.enterText(
      find.byKey(PartnerKeys.partnerEmail),
      partnerDemoAccount.email,
    );
    await tester.enterText(
      find.byKey(PartnerKeys.partnerPassword),
      partnerDemoPassword,
    );
    await tester.tap(find.byKey(PartnerKeys.partnerSubmit));
    await tester.pumpAndSettle();

    await tester.tap(find.text(PartnerMessages.reservations));
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.confirmAttendance), findsNothing);

    await tester.tap(find.text(PartnerMessages.done));
    await tester.pumpAndSettle();
    final olga = '${SampleIds.groupCwbClosed}-p0';
    final checkin = find.byKey(
      PartnerKeys.partnerCheckin(SampleIds.groupCwbClosed, olga),
    );
    await tester.scrollUntilVisible(
      checkin,
      400,
      scrollable: verticalScrollable,
    );
    await tester.ensureVisible(checkin);
    await tester.pumpAndSettle();
    await tester.tap(checkin);
    await tester.pumpAndSettle();

    expect(
      find.byKey(PartnerKeys.partnerCheckedIn(SampleIds.groupCwbClosed, olga)),
      findsOneWidget,
    );
    expect(find.text(PartnerMessages.attended), findsWidgets);
    expect(
      find.byKey(PartnerKeys.partnerCheckin(SampleIds.groupCwbClosed, olga)),
      findsNothing,
    );
  });
}
