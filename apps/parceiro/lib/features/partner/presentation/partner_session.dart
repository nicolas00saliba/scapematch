import 'package:dominio/dominio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/mode/app_mode.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/features/auth/data/auth_messages.dart';
import 'package:scapematch/features/catalog/data/fake_catalog_repository.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_account_loader.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_repository.dart';
import 'package:scapematch_parceiro/features/partner/data/supabase_partner_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_snapshot.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch/providers/repositories.dart';

enum PartnerSection {
  balance,
  reservations,
  agenda,
  rooms,
  invoices,
  reviews,
  ranking,
}

class PartnerFiscalController extends Notifier<VenueFiscalProfile> {
  @override
  VenueFiscalProfile build() => demoHouseFiscal;

  void save(VenueFiscalProfile profile) => state = profile;
}

final partnerFiscalProvider =
    NotifierProvider<PartnerFiscalController, VenueFiscalProfile>(
      PartnerFiscalController.new,
    );

class PartnerAcceptanceController extends Notifier<List<LegalAcceptance>> {
  @override
  List<LegalAcceptance> build() => const [];

  void record({required String userId, String? venueId, DateTime? at}) {
    final when = at ?? DateTime.now();
    state = [
      ...state,
      for (final code in partnerAcceptanceCodes)
        LegalAcceptance(
          userId: userId,
          venueId: venueId,
          audience: 'partner',
          documentCode: code,
          documentVersion: legalDocumentVersion,
          acceptedAt: when,
        ),
    ];
  }
}

final partnerAcceptanceProvider =
    NotifierProvider<PartnerAcceptanceController, List<LegalAcceptance>>(
      PartnerAcceptanceController.new,
    );

class PartnerSessionController extends Notifier<PartnerAccount?> {
  @override
  PartnerAccount? build() {
    if (!scapeUsesLiveBackend) return null;
    final user = scapeSupabase.auth.currentUser;
    if (user == null) return null;
    Future<void>(() async {
      final account = await loadPartnerAccount();
      if (!ref.mounted) return;
      state = account;
    });
    return PartnerAccount(
      email: user.email ?? '',
      houseId: '',
      houseName: '',
      userId: user.id,
      venueStatus: 'loading',
    );
  }

  /// Nulo quando a casa entrou. A frase quando a conta recusou.
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    if (scapeUsesLiveBackend) {
      try {
        await scapeSupabase.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );
        state = await loadPartnerAccount();
        return null;
      } on Object catch (error) {
        return authErrorMessage(error, fallback: PartnerMessages.badLoginLive);
      }
    }
    if (!kAllowSampleLogin) return PartnerMessages.badLoginLive;
    final account = matchPartnerLogin(email, password);
    if (account == null) return PartnerMessages.badLogin;
    state = account;
    return null;
  }

  void adopt(PartnerAccount account) => state = account;

  Future<void> reload() async {
    if (!scapeUsesLiveBackend) return;
    state = await loadPartnerAccount();
  }

  Future<void> signOut() async {
    if (scapeUsesLiveBackend) {
      await scapeSupabase.auth.signOut();
    }
    state = null;
  }
}

class PartnerPreferDesk extends Notifier<bool> {
  @override
  bool build() => false;

  void open() => state = true;

  void close() => state = false;
}

final partnerPreferDeskProvider = NotifierProvider<PartnerPreferDesk, bool>(
  PartnerPreferDesk.new,
);

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

final partnerRepositoryProvider = Provider<PartnerDesk>((ref) {
  if (kAllowSampleData) {
    if (!ref.watch(backendPlanProvider).connectsSupabase) {
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
    }
  }
  return SupabasePartnerRepository(clock: ref.watch(clockProvider));
});

final partnerDeskProvider = FutureProvider<PartnerSnapshot?>((ref) async {
  final session = ref.watch(partnerSessionProvider);
  ref.watch(partnerRevisionProvider);
  if (session == null) {
    return null;
  }
  final fiscal = ref.watch(partnerFiscalProvider);
  return ref
      .read(partnerRepositoryProvider)
      .load(session.houseId, fiscal: fiscal);
});
