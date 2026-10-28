import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/features/auth/data/fake_auth_repository.dart';
import 'package:scapematch/features/auth/data/pending_invite_store.dart';
import 'package:scapematch/features/auth/domain/auth_repository.dart';
import 'package:scapematch/features/catalog/data/asset_experience_source.dart';
import 'package:scapematch/features/catalog/data/catalog_repository.dart';
import 'package:scapematch/features/catalog/data/fake_catalog_repository.dart';
import 'package:scapematch/features/catalog/domain/experience_source.dart';
import 'package:scapematch/features/cities/data/city_repository.dart';
import 'package:scapematch/features/cities/data/fake_city_repository.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/data/group_repository.dart';
import 'package:scapematch/features/news/data/fake_news_repository.dart';
import 'package:scapematch/features/news/data/news_repository.dart';
import 'package:scapematch/features/news/data/sample_news.dart';

/// Wall clock for rules that compare a session with "now".
///
/// Tests override this with a [FixedClock]. Sample groups are built from
/// the same instant, so a session that starts in 90 minutes stays inside
/// the refund window for the whole session.
final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// Sessão fictícia. O app começa com Nícolas. Um teste de convite passa
/// `signedIn: null` para ver a tela sem login.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FakeAuthRepository();
});

/// Grupo que a pessoa escolheu antes de entrar na conta.
final pendingInviteStoreProvider = Provider<PendingInviteStore>((ref) {
  return PendingInviteStore();
});

/// One in-memory database for the whole session.
///
/// The three repositories below share it, so a group created on one screen
/// shows up on the others. Tests can override any of these providers.
final fakeDatabaseProvider = Provider<FakeDatabase>((ref) {
  return buildSampleDatabase(now: ref.watch(clockProvider).now());
});

final cityRepositoryProvider = Provider<CityRepository>((ref) {
  return FakeCityRepository(ref.watch(fakeDatabaseProvider));
});

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return FakeCatalogRepository(ref.watch(fakeDatabaseProvider));
});

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return FakeGroupRepository(
    ref.watch(fakeDatabaseProvider),
    clock: ref.watch(clockProvider),
  );
});

/// Feed fictício. A Home lê [newsRepositoryProvider], não a lista de exemplo.
/// Trocar pela fonte real é apontar este provider para outra classe.
final newsRepositoryProvider = Provider<NewsRepository>((ref) {
  final now = ref.watch(clockProvider).now();
  return FakeNewsRepository(items: buildSampleNews(now));
});

/// Example house feed. The screens do not read this yet.
/// The catalog still comes from [fakeDatabaseProvider]. Wiring a real
/// source means teaching the catalog repository to call [ExperienceSource]
/// for each house, which is described in docs/DADOS_REAIS.md.
final exampleExperienceSourceProvider = Provider<ExperienceSource>((ref) {
  return AssetExperienceSource.example();
});
