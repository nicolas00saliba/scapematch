import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/mode/app_mode.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scapematch/features/account/data/player_cpf_store.dart';
import 'package:scapematch/features/auth/data/fake_auth_repository.dart';
import 'package:scapematch/features/auth/data/pending_invite_store.dart';
import 'package:scapematch/features/auth/data/supabase_auth_repository.dart';
import 'package:scapematch/features/auth/domain/auth_repository.dart';
import 'package:scapematch/features/community/domain/community_board.dart';
import 'package:scapematch/features/catalog/data/asset_experience_source.dart';
import 'package:scapematch/features/catalog/data/catalog_repository.dart';
import 'package:scapematch/features/catalog/data/fake_catalog_repository.dart';
import 'package:scapematch/features/catalog/data/supabase_catalog_repository.dart';
import 'package:scapematch/features/catalog/domain/experience_source.dart';
import 'package:scapematch/features/cities/data/city_repository.dart';
import 'package:scapematch/features/cities/data/fake_city_repository.dart';
import 'package:scapematch/features/cities/data/supabase_city_repository.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/data/supabase_group_repository.dart';
import 'package:scapematch/features/groups/data/group_repository.dart';
import 'package:scapematch/features/social/data/memory_social_repository.dart';
import 'package:scapematch/features/social/data/social_repository.dart';
import 'package:scapematch/features/social/data/supabase_social_repository.dart';
import 'package:scapematch/features/map/data/geolocator_user_location.dart';
import 'package:scapematch/features/map/data/sample_live_presence.dart';
import 'package:scapematch/features/map/data/user_location.dart';
import 'package:scapematch/features/news/data/fake_news_repository.dart';
import 'package:scapematch/features/news/data/news_repository.dart';
import 'package:scapematch/features/news/data/supabase_news_repository.dart';
import 'package:scapematch/features/news/data/sample_news.dart';
import 'package:scapematch/features/payments/data/fake_payment_methods_repository.dart';
import 'package:scapematch/features/payments/data/payment_methods_repository.dart';
import 'package:scapematch/features/payments/data/player_payments_repository.dart';
import 'package:scapematch/features/payments/data/supabase_payment_methods_repository.dart';
import 'package:scapematch/features/reviews/data/room_review_gateway.dart';
import 'package:scapematch/features/wallet/data/fake_wallet_repository.dart';
import 'package:scapematch/features/wallet/data/wallet_repository.dart';
import 'package:scapematch/features/wallet/domain/wallet_transaction.dart';

/// Wall clock for rules that compare a session with "now".
///
/// Tests override this with a [FixedClock]. Sample groups are built from
/// the same instant, so a session that starts in 90 minutes stays inside
/// the refund window for the whole session.
final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// Plano deste processo. O [bootScapeBackend] liga o Supabase no modo real
/// antes do primeiro frame. Testes não chamam o boot, então ficam na memória.
/// Um teste troca o plano sem subir o cliente de verdade.
final backendPlanProvider = Provider<BackendPlan>((ref) {
  return planFor(scapeUsesLiveBackend ? AppMode.real : AppMode.demo);
});

/// Cliente do modo real. A demonstração não lê este provider.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return scapeSupabase;
});

/// Sessão fictícia. O app começa com Nícolas nesta mesma instância.
/// `signOut` zera a sessão; um `FakeAuthRepository` novo não é criado,
/// então o app continua deslogado até um login.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (kAllowSampleData) {
    if (!ref.watch(backendPlanProvider).connectsSupabase) {
      return FakeAuthRepository();
    }
  }
  return SupabaseAuthRepository(ref.watch(supabaseClientProvider));
});

/// Demonstração não pergunta CPF. No modo real o número fica no perfil.
final playerCpfStoreProvider = Provider<PlayerCpfStore>((ref) {
  if (!ref.watch(backendPlanProvider).connectsSupabase) {
    return MemoryPlayerCpfStore(saved: true);
  }
  return SupabasePlayerCpfStore(ref.watch(supabaseClientProvider));
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
  if (kAllowSampleData) {
    if (!ref.watch(backendPlanProvider).connectsSupabase) {
      return FakeCityRepository(ref.watch(fakeDatabaseProvider));
    }
  }
  return SupabaseCityRepository(ref.watch(supabaseClientProvider));
});

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  if (kAllowSampleData) {
    if (!ref.watch(backendPlanProvider).connectsSupabase) {
      return FakeCatalogRepository(ref.watch(fakeDatabaseProvider));
    }
  }
  return SupabaseCatalogRepository(ref.watch(supabaseClientProvider));
});

/// Amigos e turmas. Com sessão real, as funções de
/// `20261104120700_friends_crews.sql`. Sem ela, a memória da demonstração.
final socialRepositoryProvider = Provider<SocialRepository>((ref) {
  if (kAllowSampleData) {
    if (!ref.watch(backendPlanProvider).connectsSupabase) {
      return MemorySocialRepository(
        board: ref.watch(communityBoardProvider),
        clock: ref.watch(clockProvider),
      );
    }
  }
  final client = ref.watch(supabaseClientProvider);
  return SupabaseSocialRepository((function, args) {
    return client.rpc(function, params: args);
  });
});

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  if (kAllowSampleData) {
    if (!ref.watch(backendPlanProvider).connectsSupabase) {
      return FakeGroupRepository(
        ref.watch(fakeDatabaseProvider),
        clock: ref.watch(clockProvider),
        board: ref.watch(communityBoardProvider),
        friends: ref.watch(socialRepositoryProvider),
      );
    }
  }
  return SupabaseGroupRepository(
    client: ref.watch(supabaseClientProvider),
    clock: ref.watch(clockProvider),
  );
});

/// Presença fictícia do mapa. O desenho do canal real está no esquema.
final userLocationSourceProvider = Provider<UserLocationSource>((ref) {
  return GeolocatorUserLocation();
});

final sampleLivePresenceProvider = Provider<SampleLivePresence>((ref) {
  if (!kAllowSampleData || ref.watch(backendPlanProvider).connectsSupabase) {
    throw StateError('Presença de exemplo não existe no modo real.');
  }
  return SampleLivePresence(
    database: ref.watch(fakeDatabaseProvider),
    clock: ref.watch(clockProvider),
  );
});

/// Feed fictício. A Home lê [newsRepositoryProvider], não a lista de exemplo.
/// Trocar pela fonte real é apontar este provider para outra classe.
/// Saldo fictício da Conta. A tela lê este provider, não um número solto.
/// Trocar pelo livro-razão real é apontar para outra classe.
final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  if (kAllowSampleData) {
    if (!ref.watch(backendPlanProvider).connectsSupabase) {
      return FakeWalletRepository();
    }
  }
  return FakeWalletRepository(transactions: const <WalletTransaction>[]);
});

/// Cartões cadastrados. Na demonstração a lista vem vazia. No modo real,
/// `my_saved_cards` devolve só id, final e bandeira.
final paymentMethodsRepositoryProvider = Provider<PaymentMethodsRepository>((
  ref,
) {
  if (kAllowSampleData) {
    if (!ref.watch(backendPlanProvider).connectsSupabase) {
      return FakePaymentMethodsRepository();
    }
  }
  return SupabasePaymentMethodsRepository(ref.watch(supabaseClientProvider));
});

/// Pagamentos reais da conta. A demonstração não mostra esta lista.
final playerPaymentsRepositoryProvider = Provider<PlayerPaymentsRepository>((
  ref,
) {
  if (kAllowSampleData) {
    if (!ref.watch(backendPlanProvider).connectsSupabase) {
      return const EmptyPlayerPaymentsRepository();
    }
  }
  return SupabasePlayerPaymentsRepository(ref.watch(supabaseClientProvider));
});

/// A demonstração deixa a flag desligada. No app real a função do banco
/// devolve o interruptor do Admin, que nasce falso.
final reviewsEnabledProvider = FutureProvider<bool>((ref) async {
  if (!ref.watch(backendPlanProvider).connectsSupabase) return false;
  final value = await ref.watch(supabaseClientProvider).rpc('reviews_enabled');
  return value == true;
});

final roomReviewGatewayProvider = Provider<RoomReviewGateway>((ref) {
  if (!ref.watch(backendPlanProvider).connectsSupabase) {
    return MemoryRoomReviewGateway();
  }
  return SupabaseRoomReviewGateway(ref.watch(supabaseClientProvider));
});

final newsRepositoryProvider = Provider<NewsRepository>((ref) {
  if (kAllowSampleData) {
    if (!ref.watch(backendPlanProvider).connectsSupabase) {
      final now = ref.watch(clockProvider).now();
      return FakeNewsRepository(items: buildSampleNews(now));
    }
  }
  return SupabaseNewsRepository(ref.watch(supabaseClientProvider));
});

/// Example house feed. The screens do not read this yet.
/// The catalog still comes from [fakeDatabaseProvider]. Wiring a real
/// source means teaching the catalog repository to call [ExperienceSource]
/// for each house, which is described in docs/DADOS_REAIS.md.
final exampleExperienceSourceProvider = Provider<ExperienceSource>((ref) {
  return AssetExperienceSource.example();
});
