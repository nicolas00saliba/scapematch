import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/catalog/data/fake_catalog_repository.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_snapshot.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch/providers/repositories.dart';

enum PartnerSection { balance, reservations, agenda, rooms }

class PartnerSessionController extends Notifier<PartnerAccount?> {
  @override
  PartnerAccount? build() => null;

  /// Nulo quando a casa entrou. A frase quando o exemplo recusou.
  String? signIn({required String email, required String password}) {
    final account = matchPartnerLogin(email, password);
    if (account == null) {
      return PartnerMessages.badLogin;
    }
    state = account;
    return null;
  }

  void signOut() => state = null;
}

final partnerSessionProvider =
    NotifierProvider<PartnerSessionController, PartnerAccount?>(
      PartnerSessionController.new,
    );

class PartnerSectionController extends Notifier<PartnerSection> {
  @override
  PartnerSection build() => PartnerSection.balance;

  void select(PartnerSection section) => state = section;
}

final partnerSectionProvider =
    NotifierProvider<PartnerSectionController, PartnerSection>(
      PartnerSectionController.new,
    );

class PartnerRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final partnerRevisionProvider = NotifierProvider<PartnerRevision, int>(
  PartnerRevision.new,
);

final partnerRepositoryProvider = Provider<PartnerRepository>((ref) {
  final groups = ref.watch(groupRepositoryProvider);
  final catalog = ref.watch(catalogRepositoryProvider);
  if (groups is! FakeGroupRepository || catalog is! FakeCatalogRepository) {
    throw StateError('O Parceiro desta versão usa o livro em memória.');
  }
  return PartnerRepository(
    groups: groups,
    catalog: catalog,
    database: ref.watch(fakeDatabaseProvider),
    clock: ref.watch(clockProvider),
  );
});

final partnerDeskProvider = FutureProvider<PartnerSnapshot?>((ref) async {
  final session = ref.watch(partnerSessionProvider);
  ref.watch(partnerRevisionProvider);
  if (session == null) {
    return null;
  }
  return ref.read(partnerRepositoryProvider).load(session.houseId);
});
