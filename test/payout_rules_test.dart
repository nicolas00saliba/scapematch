import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/groups/data/group_rpc_errors.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';

void main() {
  test('casa sem a coluna continua na vitrine e false sai da criação', () {
    expect(venueReceivesGroups({'id': 'a'}), isTrue);
    expect(venueReceivesGroups({'receives_payments': true}), isTrue);
    expect(venueReceivesGroups({'receives_payments': false}), isFalse);
    expect(venueReceivesGroups({'receives_payments': null}), isTrue);
  });

  test('o erro da subconta vira a frase da conta de recebimento', () {
    final reason = createGroupFailure('p0001 conta de recebimento pendente');
    expect(reason, CreateGroupFailureReason.payoutPending);
    expect(
      GroupMessages.createFailure(reason),
      'Conta de recebimento pendente',
    );
    expect(
      partyCreateFailure('P0001 conta de recebimento pendente'),
      CreateGroupFailureReason.payoutPending,
    );
  });
}
