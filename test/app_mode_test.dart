import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/mode/app_mode.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/features/auth/data/fake_auth_repository.dart';
import 'package:scapematch/features/auth/data/supabase_auth_repository.dart';
import 'package:scapematch/features/catalog/data/fake_catalog_repository.dart';
import 'package:scapematch/features/catalog/data/supabase_catalog_repository.dart';
import 'package:scapematch/features/cities/data/fake_city_repository.dart';
import 'package:scapematch/features/cities/data/supabase_city_repository.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/data/supabase_group_repository.dart';
import 'package:scapematch/features/news/data/fake_news_repository.dart';
import 'package:scapematch/features/news/data/supabase_news_repository.dart';
import 'package:scapematch/features/promos/presentation/promo_carousel.dart';
import 'package:scapematch/features/social/data/memory_social_repository.dart';
import 'package:scapematch/features/social/data/supabase_social_repository.dart';
import 'package:scapematch/features/wallet/data/fake_wallet_repository.dart';
import 'package:scapematch/providers/repositories.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('o nome do define vira real ou demo', () {
    expect(parseAppMode('real'), AppMode.real);
    expect(parseAppMode('demo'), AppMode.demo);
    expect(kAppMode, parseAppMode(appModeName));
    expect(() => parseAppMode('staging'), throwsFormatException);
  });

  test('o plano real liga o Supabase e não carrega exemplo', () {
    final plan = planFor(AppMode.real);
    expect(plan.connectsSupabase, isTrue);
    expect(plan.loadsSampleDatabase, isFalse);
  });

  test('o plano demo fica na memória', () {
    final plan = planFor(AppMode.demo);
    expect(plan.connectsSupabase, isFalse);
    expect(plan.loadsSampleDatabase, isTrue);
  });

  test('a demonstração não chama o Supabase', () async {
    final previous = scapeUsesLiveBackend;
    addTearDown(() => scapeUsesLiveBackend = previous);
    var called = false;
    await applyBackendPlan(
      AppMode.demo,
      startSupabase: () async {
        called = true;
      },
    );
    expect(called, isFalse);
    expect(scapeUsesLiveBackend, isFalse);
  });

  test('o modo real pede o arranque e não monta o banco de exemplo', () async {
    final previous = scapeUsesLiveBackend;
    addTearDown(() => scapeUsesLiveBackend = previous);
    var called = false;
    await applyBackendPlan(
      AppMode.real,
      startSupabase: () async {
        called = true;
        scapeUsesLiveBackend = true;
      },
    );
    expect(called, isTrue);
    expect(scapeUsesLiveBackend, isTrue);

    var sampleBuilt = false;
    var clientReads = 0;
    final container = ProviderContainer(
      overrides: [
        backendPlanProvider.overrideWithValue(planFor(AppMode.real)),
        supabaseClientProvider.overrideWith((ref) {
          clientReads += 1;
          return SupabaseClient('https://example.supabase.co', 'anon-test');
        }),
        fakeDatabaseProvider.overrideWith((ref) {
          sampleBuilt = true;
          return buildSampleDatabase(now: DateTime.utc(2026));
        }),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(cityRepositoryProvider),
      isA<SupabaseCityRepository>(),
    );
    expect(
      container.read(catalogRepositoryProvider),
      isA<SupabaseCatalogRepository>(),
    );
    expect(
      container.read(groupRepositoryProvider),
      isA<SupabaseGroupRepository>(),
    );
    expect(
      container.read(newsRepositoryProvider),
      isA<SupabaseNewsRepository>(),
    );
    expect(
      container.read(authRepositoryProvider),
      isA<SupabaseAuthRepository>(),
    );
    expect(
      container.read(socialRepositoryProvider),
      isA<SupabaseSocialRepository>(),
    );
    final wallet = container.read(walletRepositoryProvider);
    expect(wallet, isA<FakeWalletRepository>());
    expect(await wallet.transactions(), isEmpty);
    expect(container.read(visiblePromoFlyersProvider), isEmpty);
    expect(sampleBuilt, isFalse);
    expect(clientReads, greaterThan(0));
  });

  test('a demonstração não lê o cliente Supabase', () {
    var clientReads = 0;
    final container = ProviderContainer(
      overrides: [
        backendPlanProvider.overrideWithValue(planFor(AppMode.demo)),
        supabaseClientProvider.overrideWith((ref) {
          clientReads += 1;
          return SupabaseClient('https://example.supabase.co', 'anon-test');
        }),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(cityRepositoryProvider), isA<FakeCityRepository>());
    expect(
      container.read(catalogRepositoryProvider),
      isA<FakeCatalogRepository>(),
    );
    expect(container.read(groupRepositoryProvider), isA<FakeGroupRepository>());
    expect(container.read(newsRepositoryProvider), isA<FakeNewsRepository>());
    expect(container.read(authRepositoryProvider), isA<FakeAuthRepository>());
    expect(
      container.read(socialRepositoryProvider),
      isA<MemorySocialRepository>(),
    );
    expect(container.read(visiblePromoFlyersProvider), isNotEmpty);
    expect(clientReads, 0);
  });
}
